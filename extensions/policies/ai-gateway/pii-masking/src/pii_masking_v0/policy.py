# Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from __future__ import annotations

import json
import logging
import threading
import time
import uuid
from typing import Any

from apip_sdk_core import (
    BodyProcessingMode,
    DownstreamResponseModifications,
    ExecutionContext,
    ImmediateResponse,
    ProcessingMode,
    RequestAction,
    RequestContext,
    RequestPolicy,
    ResponseAction,
    ResponseContext,
    ResponsePolicy,
    UpstreamRequestModifications,
)

MODEL_NAME = "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1"
SKIP_KEYS = {"model", "role"}

logger = logging.getLogger("pii-masking")
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler()
_handler.setFormatter(logging.Formatter("%(message)s"))
logger.addHandler(_handler)
logger.propagate = False


class PiiMaskingPolicy(RequestPolicy, ResponsePolicy):
    """Redact PII on the way to the LLM and restore it on the way back, in-process.

    Request phase: every free-text string in the buffered body is redacted with
    openmed's privacy gateway — each entity becomes a delimited placeholder
    (``<<OPENMED_PHI_NAME_..._000001>>``) and the placeholder -> original-value
    mapping is kept in memory. Response phase: the validating reidentifier
    swaps the placeholders the LLM echoed back for the real values — and
    rejects hallucinated or mangled ones, in which case the still-redacted
    response is passed through unchanged.
    """

    def __init__(self) -> None:
        self._mappings: dict[str, dict[str, str]] = {}

    def mode(self) -> ProcessingMode:
        return ProcessingMode(
            request_body_mode=BodyProcessingMode.BUFFER,
            response_body_mode=BodyProcessingMode.BUFFER,
        )

    def _redact_text(self, text_blob: str, mapping: dict[str, str]) -> str:
        if not text_blob.strip():
            return text_blob
        from openmed import extract_pii
        from openmed.service.privacy_gateway import coerce_gateway_entities, redact_text

        entities = coerce_gateway_entities(extract_pii(text_blob, model_name=MODEL_NAME), text_blob)
        session = redact_text(text_blob, entities, request_id=uuid.uuid4().hex)
        mapping.update(session.placeholder_map)
        return session.redacted_text

    def _redact_structure(self, node: Any, mapping: dict[str, str]) -> Any:
        if isinstance(node, dict):
            return {k: (v if k in SKIP_KEYS else self._redact_structure(v, mapping)) for k, v in node.items()}
        if isinstance(node, list):
            return [self._redact_structure(item, mapping) for item in node]
        if isinstance(node, str):
            return self._redact_text(node, mapping)
        return node

    def _restore_text(self, text_blob: str, mapping: dict[str, str]) -> str:
        from openmed.service.privacy_gateway import reidentify_placeholders

        return reidentify_placeholders(text_blob, mapping)

    def _restore_structure(self, node: Any, mapping: dict[str, str]) -> Any:
        if isinstance(node, dict):
            return {
                self._restore_text(k, mapping) if isinstance(k, str) else k:
                    self._restore_structure(v, mapping)
                for k, v in node.items()
            }
        if isinstance(node, list):
            return [self._restore_structure(item, mapping) for item in node]
        if isinstance(node, str):
            return self._restore_text(node, mapping)
        return node

    def on_request_body(
        self,
        execution_ctx: ExecutionContext,
        ctx: RequestContext,
        params: dict[str, Any],
    ) -> RequestAction:
        if ctx.body is None or not ctx.body.present or ctx.body.content is None:
            return None

        try:
            payload = json.loads(ctx.body.content)
        except (json.JSONDecodeError, UnicodeDecodeError):
            logger.info("request %s: non-JSON body, rejected", ctx.shared.request_id)
            return ImmediateResponse(
                status_code=400,
                body=b'{"error": "request body must be JSON"}',
                headers={"content-type": "application/json"},
            )

        logger.info("request %s: received %d-byte body", ctx.shared.request_id, len(ctx.body.content))
        mapping: dict[str, str] = {}
        try:
            redacted = self._redact_structure(payload, mapping)
        except Exception:
            # Fail closed: never forward a payload we could not redact cleanly.
            logger.exception("request %s: PII redaction failed", ctx.shared.request_id)
            return ImmediateResponse(
                status_code=502,
                body=b'{"error": "PII redaction failed"}',
                headers={"content-type": "application/json"},
            )

        masked = json.dumps(redacted).encode()
        if mapping:
            self._mappings[ctx.shared.request_id] = mapping
        logger.info("request %s: forwarded %d-byte redacted body", ctx.shared.request_id, len(masked))
        return UpstreamRequestModifications(
            body=masked,
            headers_to_set={"content-length": str(len(masked))},
        )

    def on_response_body(
        self,
        execution_ctx: ExecutionContext,
        ctx: ResponseContext,
        params: dict[str, Any],
    ) -> ResponseAction:
        mapping = self._mappings.pop(ctx.shared.request_id, None)
        if not mapping or ctx.response_body is None or not ctx.response_body.present:
            return None
        if ctx.response_body.content is None:
            return None

        logger.info("request %s: received %d-byte response", ctx.shared.request_id, len(ctx.response_body.content))
        try:
            payload = json.loads(ctx.response_body.content)
            restored = self._restore_structure(payload, mapping)
            body = json.dumps(restored).encode()
        except ValueError:
            # Failed to parse or safely restore the response; pass the redacted body through unchanged.
            logger.warning("request %s: reidentification rejected, leaving redacted", ctx.shared.request_id)
            return None

        logger.info("request %s: returned %d-byte restored body", ctx.shared.request_id, len(body))
        return DownstreamResponseModifications(
            body=body,
            headers_to_set={"content-length": str(len(body))},
        )


def get_policy(metadata, params):
    return PiiMaskingPolicy()


def _warm_up_model() -> None:
    try:
        started = time.perf_counter()
        from openmed import extract_pii

        extract_pii("warm up", model_name=MODEL_NAME)
        logger.info("OpenMed model loaded in %.1f s", time.perf_counter() - started)
    except Exception:
        logger.exception("model warm-up failed; the first request will load the model instead")


# The policy engine imports this module at startup, so this warms the model before traffic arrives.
threading.Thread(target=_warm_up_model, name="openmed-warmup", daemon=True).start()
