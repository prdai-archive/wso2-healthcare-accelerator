# AI Gateway Request Monitoring for PII Information using OpenMed Model(s)

WSO2 API Platform **AI Gateway** (the Go/Envoy-based gateway) experiment: a custom Python gateway policy runs an OpenMed deidentification model **in-process**: every PII entity in an incoming LLM request becomes a delimited placeholder (`<<OPENMED_PHI_NAME_..._000001>>`) before the body reaches OpenAI, and the placeholders the model echoes back are validated and swapped for the real values on the response flow. No sidecar service — the model lives inside the gateway runtime, and the client never sees the placeholders.

## Quick start

```sh
cp .env.example .env        # add your OpenAI API key
make setup                  # installs ap CLI + distribution, builds the custom gateway image, starts the stack, deploys the provider
cd test && go run .         # send a PII-laden prompt through, print the restored reply + timing
make logs                   # redacted payloads + redact/restore timings in the gateway runtime
```

The policy warms the model up by itself: the gateway imports the policy module at startup, which kicks off a background model load — no external trigger needed. The download is cached in the `hf-cache` volume so restarts don't re-fetch it. The policy pins CPU-only torch wheels to keep the custom image small.

> On rootful Docker (e.g. snap), the gateway image build step needs root: run `sudo -E ./scripts/setup.sh` once. Re-runs skip the build (`REBUILD=1` to force).

## How it works

1. `gateway/policies/pii-masking-openmed/` is a custom **Python gateway policy** (`policy.py` + `policy-definition.yaml` + `requirements.txt`) hooking **both flows** (request and response bodies buffered):
   - request: recursively redacts every free-text string with `OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1` via openmed's `privacy_gateway.redact_text` (structural keys like `model` and `role` are left alone) and keeps the `{placeholder: original}` mapping in memory. Non-JSON bodies get a 400; a redaction failure returns a 502 instead of leaking the raw payload.
   - response: `privacy_gateway.reidentify_placeholders` validates before substituting — a hallucinated or mangled placeholder rejects the restore and the still-redacted response is passed through instead. Redact/restore timings are logged per request.
2. `gateway/build.yaml` is the distribution's policy manifest plus our policy; `ap gateway image build` bakes the policy and its dependencies (torch + openmed) into custom `pii-gateway-*` images.
3. `gateway/manifests/llm-provider.yaml` is the declarative `LlmProvider` for OpenAI (`template: openai`, backend key injected from the root `.env`), with the policy attached to `POST /chat/completions`.
4. The root `docker-compose.yaml` overlay swaps in the custom images, raises the runtime's resource limits (the distribution's 180 MB default cannot hold a torch model), and mounts the `hf-cache` volume for the model.
5. `scripts/setup.sh` automates all of it: downloads the `ap` CLI and the gateway distribution (into `gateway/dist/`, gitignored), builds the image, starts docker compose, waits for health, and deploys the provider via the management REST API (`:9090/api/management/v1`, admin/admin).

Requests then flow: client → `https://localhost:8443/openai/latest/chat/completions` → policy (redact, in-process model) → placeholders → OpenAI → policy (validating restore) → client. Responses are buffered, so `stream: true` isn't supported yet.

## Using the policy in your own gateway

The policy is a local Python gateway policy. Reference it with `filePath` in the gateway project's `build.yaml`, alongside the standard hub policies:

```yaml
version: v1
gateway:
  version: 1.2.1
policies:
  - name: advanced-ratelimit
    gomodule: github.com/wso2/gateway-controllers/policies/advanced-ratelimit@v1
  - name: llm-cost
    gomodule: github.com/wso2/gateway-controllers/policies/llm-cost@v1
  - name: set-headers
    gomodule: github.com/wso2/gateway-controllers/policies/set-headers@v1
  - name: pii-masking-openmed
    filePath: policies/pii-masking-openmed
```

- `gomodule` / `pipPackage` entries are pulled from the policy hub; `filePath` marks a **local policy**.
- `filePath` is relative to `build.yaml` and must point at a directory containing `policy-definition.yaml`, `policy.py`, and `requirements.txt` (copy `gateway/policies/pii-masking-openmed/` into your gateway project).

Build the gateway image to bake in the policy and its dependencies (torch + openmed):

```sh
ap gateway image build --name <gateway-name> --path <gateway-project-dir>
```

See [Customizing the Gateway by Adding and Removing Policies](https://github.com/wso2/api-platform/blob/main/docs/cli/customizing-gateway-policies.md) in the API Platform docs for the full `build.yaml` reference.

## AI Workspace UI

`make setup` also brings up the [AI Workspace](https://github.com/wso2/api-platform/blob/main/docs/ai-workspace/overview.md) control-plane UI: the Platform API on `:9243` and the web UI at **https://localhost:5380** (admin / admin, self-signed cert). Both run in the same compose project as the gateway, and setup connects them automatically — it registers `pii-gateway` via the Platform API, writes a registration token into `gateway/dist/.env`, and restarts the gateway controller, which then shows up **Active** under AI Gateways in the UI. `make down` stops everything.

## Layout

- `gateway/` — everything gateway-side: the custom policy (model included), `build.yaml`, the provider manifest (the root `docker-compose.yaml` layers the custom images and resource overrides on top of the distribution compose). `gateway/dist/` holds the downloaded distribution.
- `scripts/` — provisioning scripts (see above).
- `test/` — Go client that calls the gateway with the OpenAI SDK (see its README). No gateway API key is needed in the current setup.

## Make targets

| target  | what it does                                    |
|---------|--------------------------------------------------|
| `setup` | install/build/start/deploy everything            |
| `up`    | start the stack (requires a prior setup)         |
| `down`  | stop the stack                                   |
| `logs`  | follow the gateway runtime (policy IN/OUT) logs  |
| `gateway-logs` | follow gateway controller logs            |
| `lint` / `fmt` | ruff check / format                       |
