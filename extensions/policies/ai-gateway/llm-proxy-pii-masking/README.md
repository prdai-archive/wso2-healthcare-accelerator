# PII Masking — AI Gateway Policy

A Python policy for the WSO2 API Platform AI Gateway that masks
personally identifiable information (PII) in LLM traffic using the OpenMed
deidentification model, running in-process inside the gateway — no sidecar
service required.

## What it does

Before an LLM request leaves the gateway, every PII entity (names, dates, IDs,
and other PHI) detected by the OpenMed model is replaced with a delimited
placeholder such as `<<OPENMED_PHI_NAME_..._000001>>`. The real values never
reach the LLM provider.

On the response, the placeholders the model echoes back are swapped for the
original values, so the client sees a coherent reply while the provider only
ever saw redacted text.

## When to use it

- You send PHI/PII to a third-party LLM (e.g. OpenAI) and need it
  de-identified at the edge, before it leaves your infrastructure.
- You want masking without running a separate de-identification service — the
  model lives inside the gateway runtime.

## How it works

1. **Request flow** — the buffered body is redacted in-process; a
   placeholder → value map is kept in memory for the request.
2. **Response flow** — placeholders are validated and restored. A hallucinated
   or mangled placeholder rejects the restore, and the still-redacted response
   is passed through unchanged rather than leaking data.

Structural fields such as `model` and `role` are left untouched; only free-text
strings are redacted.

## Using the policy

Add it to your gateway project's `build.yaml`:

```yaml
version: v1
gateway:
  version: 1.2.1
policies:
  - name: pii-masking
    pipPackage: github.com/wso2/healthcare-accelerator/extensions/policies/ai-gateway/llm-proxy-pii-masking@v0
```

Then build the gateway image:

```sh
ap gateway image build --name <gateway-name> --path <gateway-project-dir>
```

Attach `pii-masking` to the LLM provider or route you want masked, the
same way you would any gateway policy.

## Behavior

- Requests must be JSON; non-JSON bodies are rejected with `400`.
- If redaction fails, the request fails closed with `502` — the raw payload is
  never forwarded.
- If the response can't be restored cleanly, the still-redacted response is
  returned instead of leaking the original values.
- The model is warmed up in the background at startup, so the first request
  doesn't pay the full download/load cost (and it's cached across restarts).

## Configuration

The policy takes no parameters — it works out of the box. See
`policy-definition.yaml` for the (empty) parameter schema.

## Limitations

- Request and response bodies are buffered, so streaming (`stream: true`) isn't
  supported yet.
- Uses the `OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1` model and pins
  CPU-only PyTorch wheels to keep the gateway image small.
