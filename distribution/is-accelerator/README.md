# WSO2 Healthcare Identity Server Accelerator

This distribution provides healthcare-specific identity and access management capabilities for WSO2 Identity Server, including SMART on FHIR authorization support.

## Contents

```
wso2-hcis-accelerator-<version>/
├── bin/
│   └── merge.sh                  # Installation script
├── carbon-home/
│   └── repository/components/    # OSGi bundles to deploy
├── conf/
│   └── config.toml               # Accelerator configuration
└── resources/
    └── repository/conf/
        └── deployment.toml       # Reference deployment.toml with healthcare configs
```

### OSGi Components

- **org.wso2.healthcare.is.smart.auth** — SMART on FHIR token response handler
  - Adds launch context (`patient`, `practitioner`, `encounter`) to token responses
  - Supports `launch/patient`, `launch/practitioner`, and `launch/encounter` scopes
  - Resolves context values from user claims

- **org.wso2.healthcare.is.tokenmgt** — Custom OAuth2 grant handler
  - Extends the authorization code grant handler
  - Enforces SMART on FHIR `offline_access` scope for refresh token issuance

## Prerequisites

- WSO2 Identity Server 7.2.0
- Java 11 or later

## Installation

1. Extract the accelerator ZIP.

2. Configure `conf/config.toml`:
   ```toml
   # Enable or disable SMART on FHIR features
   enable_smart_on_fhir = true
   ```

3. Run the merge script against your IS installation:
   ```bash
   cd wso2-hcis-accelerator-<version>
   sh bin/merge.sh <IS_HOME>
   ```
   If `<IS_HOME>` is omitted, the script assumes the IS installation is the parent directory of the accelerator.

   The script will:
   - Copy OSGi bundles to `<IS_HOME>/repository/components/`
   - Append healthcare-specific configurations to `<IS_HOME>/repository/conf/deployment.toml`
   - Back up the original `deployment.toml` to `<IS_HOME>/hc-accelerator/backup/conf/`
   - Log the merge operation to `<IS_HOME>/hc-accelerator/merge_audit.log`

4. Configure user claims in IS for each user:
   - `http://wso2.org/claims/patient` — FHIR Patient resource ID
   - `http://wso2.org/claims/practitioner` — FHIR Practitioner resource ID
   - `http://wso2.org/claims/encounter` — FHIR Encounter resource ID (resolved from user claim)

5. Start WSO2 IS:
   ```bash
   cd <IS_HOME>/bin
   sh wso2server.sh
   ```

## Configuration Applied to deployment.toml

When `enable_smart_on_fhir = true`, the merge script appends the following to `deployment.toml`:

```toml
[oauth]
authorize_all_scopes = true
allowed_scopes = ["^(patient|user|system)/.*", "^OH_.*", "fhirUser", "launch", "launch/patient", "launch/encounter", "offline_access"]

[oauth.endpoints.v2]
oidc_consent_page = "http://localhost:9091/open-healthcare/consent"

[oauth.grant_type.authorization_code]
grant_handler = "org.wso2.healthcare.is.tokenmgt.handlers.HealthcareAuthorizationCodeGrantHandler"

[[resource.access_control]]
context = "(.*)/scim2/Me"
secure = true
http_method = "GET"
cross_tenant = true
permissions = []
scopes = []

[[event_listener]]
id = "token_revocation"
type = "org.wso2.carbon.identity.core.handler.AbstractIdentityHandler"
name = "org.wso2.is.notification.ApimOauthEventInterceptor"
order = 1

[event_listener.properties]
notification_endpoint = "https://localhost:9443/internal/data/v1/notify"
username = "${admin.username}"
password = "${admin.password}"
'header.X-WSO2-KEY-MANAGER' = "WSO2-IS"

[role_mgt]
allow_system_prefix_for_role = true
```

## SMART on FHIR Launch Context

When a token request includes a `launch/*` scope, `HealthcareSmartAuthTokenResponseHandler` resolves the context value from the user's claims and adds it to the token response:

| Scope | Token response parameter | Claim URI |
|---|---|---|
| `launch/patient` | `patient` | `http://wso2.org/claims/patient` |
| `launch/practitioner` | `practitioner` | `http://wso2.org/claims/practitioner` |
| `launch/encounter` | `encounter` | `http://wso2.org/claims/encounter` |

**Example token response with `launch/patient`:**
```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "launch/patient patient/*.read",
  "patient": "patient-123"
}
```

## Refresh Token Behavior

The `HealthcareAuthorizationCodeGrantHandler` removes the refresh token from the response unless `offline_access` is explicitly requested, per the SMART on FHIR specification.

## Troubleshooting

**Token response missing launch context (`patient`, `practitioner`, `encounter`)**
- Verify the JAR is in `<IS_HOME>/repository/components/dropins/`
- Check that the user's claim is populated with a value
- Review IS startup logs for bundle activation errors: `Healthcare SMART Auth service component activated`

**Scope not authorized**
- Ensure `allowed_scopes` in `deployment.toml` includes the requested scope
- Verify `authorize_all_scopes = true` is set

**Check bundle status** (if OSGi console is enabled):
```bash
osgi> lb | grep healthcare
```
Both `org.wso2.healthcare.is.smart.auth` and `org.wso2.healthcare.is.tokenmgt` should show as `ACTIVE`.

## Uninstallation

1. Stop WSO2 IS.
2. Remove the component JARs:
   ```bash
   rm <IS_HOME>/repository/components/dropins/org.wso2.healthcare.is.*.jar
   ```
3. Restore the original `deployment.toml` from the backup:
   ```bash
   cp <IS_HOME>/hc-accelerator/backup/conf/deployment.toml <IS_HOME>/repository/conf/deployment.toml
   ```
4. Start WSO2 IS.

## License

Copyright (c) 2026, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.

Licensed under the Apache License, Version 2.0. See [LICENSE](http://www.apache.org/licenses/LICENSE-2.0).
