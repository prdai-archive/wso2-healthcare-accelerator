# Gateway test client

Small Go client that sends a chat completion full of fake PII (name, DOB, MRN, phone, email) through the APIM gateway using the official OpenAI SDK. The prompt asks the model to repeat the patient's details back, so a working round trip shows delimited placeholders (`<<OPENMED_PHI_NAME_..._000001>>`) going out to OpenAI in the gateway runtime logs (`make logs`) — with per-request redact/restore timings — while the client output printed here has the real values again, restored by the policy's response flow.

## Setup

`make setup` at the repo root writes the `.env` this client needs:

- `OPENAI_API_KEY` — a gateway API key (sent as the `ApiKey` header)
- `OPENAI_BASE_URL` — the gateway route, e.g. `https://localhost:8243/openai/1.0.0`

TLS verification is disabled because the local gateway uses a self-signed cert.

## Run

```sh
go run .
```

Then `make logs` at the repo root to see the redacted payloads and timings in the gateway runtime.
