# iam-service-extensions

Ballerina pre-issue-access-token action service for the consent system. Runs on port **9093**. Intercepts token issuance, validates requested scopes against the user's OpenFGC consent record, and injects patient/encounter/consent_id claims.

## Architecture

```
IDP (WSO2 IS / Asgardeo)
      │ POST /pre-issue-access-token
      ▼
iam-service-extensions  :9093
      │
      ├── OpenFGC  — consent record lookup (by sessionDataKeyConsent)
      └── SCIM     — patient ID resolution fallback (optional)
      └── EHR      — launch context resolution (optional)
```

### Files

| File | Purpose |
|------|---------|
| `configurables.bal` | All configurables |
| `types.bal` | Request/response record types |
| `client.bal` | OpenFGC + SCIM + EHR HTTP clients, token caching |
| `utils.bal` | Scope helpers, patient ID extraction, URI encoding |
| `service.bal` | POST `/pre-issue-access-token` handler |
| `tests/` | Mock OpenFGC + SCIM, service tests |

## Processing sequence

1. Extract `sessionDataKeyConsent` from `event.session`
2. Look up consent record in OpenFGC via `GET /consents/attributes?key=sessionDataKeyConsent&value=<key>`
   - No consent found → SUCCESS with no operations (pass-through)
3. Fetch consent record → extract `authorizations[].resources.scopes` as approved scopes
4. Extract internal `OH_patient/<id>` and `OH_launch/<id>` scopes (consumed, not forwarded)
5. Validate each requested token scope:
   - Must be in approved scopes or `alwaysAllowedScopes`
   - Must match SMART regex: `^(patient|user|system)/(\*|[A-Za-z]*)\.(cruds|c?r?u?d?s?)$`
   - `system/*` blocked for non-`client_credentials` grants; `patient/`+`user/` blocked for `client_credentials`
   - Multi-char operations expanded (`cruds` → `c`, `r`, `u`, `d`, `s`)
6. Build patch ops: remove existing scopes, add validated scopes
7. Resolve patient ID (priority): `OH_patient/` scope → EHR context (`OH_launch/`) → SCIM `fhirUser` attribute
8. Inject claims: `consent_id`, `patient`, `encounter`

## Setup

```bash
cp Config.toml.example Config.toml
# Edit Config.toml with your values
bal run
```

### Required config

| Key | Description |
|-----|-------------|
| `openfgcBaseUrl` | OpenFGC base URL |
| `orgId` / `tppClientId` | OpenFGC request headers |

### Optional config

| Key | Default | Description |
|-----|---------|-------------|
| `ehrContextResolveUrl` | `""` | EHR launch context endpoint; skipped when blank |
| `isBaseUrl` | `""` | IS base URL used for SCIM lookup and token introspect |
| `scimClientId` / `scimClientSecret` | `""` | OAuth2 credentials for SCIM token |
| `scimTokenEndpoint` | `""` | Defaults to `{isBaseUrl}/oauth2/token` |
| `scimPatientGroupName` | `"patient"` | Group name used to identify patient users |
| `fhirUserAttributeName` | `"fhirUser"` | SCIM custom attribute holding the FHIR user reference |
| `patientAttributeName` | `"patient"` | SCIM custom attribute holding the patient resource reference |
| `keystorePath` | `""` | Path to the keystore file for the HTTPS listener; HTTP used when blank |
| `keystorePassword` | `""` | Password to open the keystore |
| `alwaysAllowedScopes` | `["openid"]` | Scopes that bypass consent checks |

### Example Config.toml

```toml
hostname = "localhost"
port = 9093

openfgcBaseUrl = "http://localhost:8080"
orgId = "<org-id>"
tppClientId = "<tpp-client-id>"

ehrContextResolveUrl = "https://ehr.example.com/launch-context"

isBaseUrl = "https://api.asgardeo.io/t/<tenant>"
scimClientId = "<client-id>"
scimClientSecret = "<client-secret>"

# Optional: HTTPS listener
keystorePath = "/path/to/keystore.p12"
keystorePassword = "<keystore-password>"

alwaysAllowedScopes = ["openid", "fhirUser"]
```

## Tests

```bash
bal test
```

Tests use in-process mock OpenFGC and SCIM listeners defined in `tests/`.
