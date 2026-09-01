# PII Masking (OpenMed) — AI Gateway Policy

A custom Python policy for the WSO2 API Platform AI Gateway. It runs the
OpenMed deidentification model in-process: every PII entity in an incoming LLM
request becomes a delimited placeholder (`<<OPENMED_PHI_NAME_..._000001>>`)
before the body reaches the LLM provider, and the placeholders the model echoes
back are validated and swapped for the real values on the response flow. No
sidecar service — the model lives inside the gateway runtime and the provider
never sees the real data.

## Using the policy

Reference it from your gateway project's `build.yaml` with `pipPackage`. The
gateway builder fetches it as a pip package from this repository at a version
tag:

```yaml
version: v1
gateway:
  version: 1.2.1
policies:
  - name: advanced-ratelimit
    gomodule: github.com/wso2/gateway-controllers/policies/advanced-ratelimit@v1
  - name: pii-masking-openmed
    pipPackage: github.com/wso2/healthcare-accelerator/extensions/policies/ai-gateway/llm-proxy-pii-masking@v0
```

`@v0` resolves to the highest `extensions/policies/ai-gateway/llm-proxy-pii-masking/v0.*`
tag on this repository (e.g. `v0.1.0`).

Then build the gateway image:

```sh
ap gateway image build --name <gateway-name> --path <gateway-project-dir>
```

## Tagging

Each AI Gateway policy is published as a git tag named
`<path>/v<major>.<minor>.<patch>` on this repository. The `@v0` ref in
`build.yaml` resolves to the highest `v0.*` tag, so a tag must exist before the
policy can be fetched. Cut it after merge:

```sh
git tag -a extensions/policies/ai-gateway/llm-proxy-pii-masking/v0.1.0 \
  -m "pii-masking-openmed policy v0.1.0"
git push origin extensions/policies/ai-gateway/llm-proxy-pii-masking/v0.1.0
```

Bump the patch/minor version and re-tag on any change to the policy.

## Layout

- `policy-definition.yaml` — policy metadata (`pii-masking-openmed`).
- `pyproject.toml` — pip package build config (hatchling).
- `src/pii_masking_openmed_v0/policy.py` — the policy implementation (`get_policy` entrypoint).
- `requirements.txt` — runtime dependencies (torch CPU, openmed, fastapi).

## Notes

- The policy pins CPU-only PyTorch wheels (`torch==2.13.0+cpu`) to keep the
  gateway image small; the PyTorch CPU index
  (`https://download.pytorch.org/whl/cpu`) is required to resolve that wheel.
- Responses are buffered, so `stream: true` isn't supported yet.

See [Customizing the Gateway by Adding and Removing Policies](https://github.com/wso2/api-platform/blob/main/docs/cli/customizing-gateway-policies.md) in the API Platform docs.
