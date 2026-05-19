// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/http;
import ballerina/log;

listener http:Listener httpListener = new (port, config = {host: hostname});

final string:RegExp scopeRegex = re `^(patient|user|system)/(\*|[A-Za-z]*)\.(cruds|c?r?u?d?s?)$`;

service / on httpListener {

    # + return - InlineResponse200Ok|ErrorResponseBadRequest|ErrorResponseInternalServerError|error
    isolated resource function post pre\-issue\-access\-token(@http:Payload json payload)
            returns InlineResponse200Ok|ErrorResponseBadRequest|ErrorResponseInternalServerError|error {

        RequestBody reqBody = check payload.cloneWithType();
        string flowId = reqBody.flowId ?: "";
        log:printDebug(string `[${flowId}] pre-issue-access-token received`, grantType = reqBody.event.request.grantType, payload = payload.toJsonString());

        string grantType = reqBody.event.request.grantType;
        string[]? tokenScopes = reqBody.event.accessToken.scopes;
        string? sessionDataKeyConsent = extractSessionDataKeyConsent(reqBody.event);
        log:printDebug(string `[${flowId}] extracted values`, grantType = grantType, tokenScopes = (tokenScopes ?: []).toString(), sessionDataKeyConsent = sessionDataKeyConsent ?: "(none)");

        // ── 0. Drop scopes not permitted for the current grant type ───────────
        log:printInfo(string `[${flowId}] Filtering scopes for grant type '${grantType}'`);
        string[] permittedTokenScopes = [];
            foreach string s in tokenScopes {
                if s.matches(scopeRegex) && !isPermittedScope(s, grantType) {
                    log:printWarn(string `[${flowId}]: Scope '${s}' not permitted for grant '${grantType}' — dropped early`);
                    continue;
                }
                permittedTokenScopes.push(s);
            }
        }
        string[]? filteredTokenScopes = permittedTokenScopes.length() > 0 ? permittedTokenScopes : ();

        // ── 1. Load approved scopes from OpenFGC ─────────────────────────────
        string[] approvedScopes = [];
        string? resolvedConsentId = ();
        if sessionDataKeyConsent is string && sessionDataKeyConsent != "" {
            string?|error consentIdResult = getConsentIdBySessionKey(sessionDataKeyConsent);
            if consentIdResult is error {
                log:printError(string `[${flowId}]: OpenFGC attribute lookup failed: ${consentIdResult.message()}`);
                return <ErrorResponseInternalServerError>{
                    body: {
                        actionStatus: "ERROR",
                        errorMessage: "Consent lookup failed",
                        errorDescription: "Failed to retrieve consent from store."
                    }
                };
            }
            if !(consentIdResult is string) {
                // No consent found — return SUCCESS with no operations
                log:printDebug(string `[${flowId}]: No consent found for sessionDataKeyConsent — passing through`);
                return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: []}};
            }

            resolvedConsentId = consentIdResult;
            string[]|error scopesResult = getApprovedScopesByConsentId(consentIdResult);
            if scopesResult is error {
                log:printError(string `[${flowId}]: OpenFGC consent fetch failed: ${scopesResult.message()}`);
                return <ErrorResponseInternalServerError>{
                    body: {
                        actionStatus: "ERROR",
                        errorMessage: "Consent fetch failed",
                        errorDescription: "Failed to retrieve consent details from store."
                    }
                };
            }
            approvedScopes = scopesResult;
        }

        log:printDebug(string `[${flowId}] approved scopes from OpenFGC`, scopes = approvedScopes.toString());

        // ── 2. Extract OH_* internal scopes; accumulate validated public scopes
        string[] modifiedScopes = [];
        string? patientIdFromScope = ();
        string? launchId = ();

        foreach string approvedScope in approvedScopes {
            string? pid = getPatientIdFromScope(approvedScope);
            if pid is string {
                patientIdFromScope = pid;
                continue;
            }
            string? lid = getLaunchIdFromScope(approvedScope);
            if lid is string {
                launchId = lid;
                continue;
            }
        }

        // ── 3. Validate and expand requested token scopes ─────────────────────
        // Consent approval check only applies when a consent record was resolved.
        // For client_credentials (no sessionDataKeyConsent) scope filtering is
        // handled entirely by the grant-type check in step 0.
        boolean hasConsent = sessionDataKeyConsent is string && sessionDataKeyConsent != "" && resolvedConsentId is string;
        log:printInfo(string `[${flowId}] Processing scopes with consent check: ${hasConsent}`);
        if filteredTokenScopes is string[] {
            foreach string scope in filteredTokenScopes {
                if scope.matches(scopeRegex) {
                    // Expand multi-character operations first, then check each expanded scope
                    string[] parts = re `\.`.split(scope);
                    if parts.length() == 2 {
                        string resourceStr = parts[0];
                        string opsStr = parts[1];
                        if opsStr.length() > 1 {
                            foreach int i in 0 ..< opsStr.length() {
                                string expanded = resourceStr + "." + opsStr.substring(i, i + 1);
                                if hasConsent && !isAlwaysAllowedScope(expanded) && !isScopeApproved(expanded, approvedScopes) {
                                    log:printWarn(string `[${flowId}]: Expanded scope '${expanded}' not in approved set — skipped`);
                                    continue;
                                }
                                modifiedScopes.push(expanded);
                            }
                        } else {
                            if hasConsent && !isAlwaysAllowedScope(scope) && !isScopeApproved(scope, approvedScopes) {
                                log:printWarn(string `[${flowId}]: Scope '${scope}' not in approved set — skipped`);
                                continue;
                            }
                            modifiedScopes.push(scope);
                        }
                    }
                } else if !scope.matches(re `^(patient|user|system)/.*`) {
                    if hasConsent && !isAlwaysAllowedScope(scope) && !isScopeApproved(scope, approvedScopes) {
                        log:printWarn(string `[${flowId}]: Scope '${scope}' not in approved set — skipped`);
                        continue;
                    }
                    modifiedScopes.push(scope);
                } else {
                    log:printWarn(string `[${flowId}]: Scope '${scope}' has invalid SMART format — skipped`);
                }
            }
        }

        log:printDebug(string `[${flowId}] validated scopes for token`, modifiedScopes = modifiedScopes.toString(), patientIdFromScope = patientIdFromScope ?: "(none)", launchId = launchId ?: "(none)");

        // ── 4. Build patch operations ─────────────────────────────────────────
        (addOperationResponse|replaceOperationResponse|removeOperationResponse)[] ops = [];

        // Remove existing scopes from token (reverse-index order, using original list)
        if tokenScopes is string[] && tokenScopes.length() > 0 {
            foreach int i in 0 ..< tokenScopes.length() {
                int idx = (tokenScopes.length() - 1) - i;
                ops.push({op: "remove", path: "/accessToken/scopes/" + idx.toString()});
            }
        }
        // Add validated scopes
        foreach string scope in modifiedScopes {
            ops.push({op: "add", path: "/accessToken/scopes/-", value: scope});
        }

        // ── 5. EHR launch context resolution ─────────────────────────────────
        string? resolvedPatientId = patientIdFromScope;
        string? resolvedEncounterId = ();

        if launchId is string {
            EhrLaunchContext?|error ctxResult = resolveLaunchContext(launchId);
            if ctxResult is error {
                log:printError(string `[${flowId}]: EHR context resolution failed: ${ctxResult.message()}`);
                return <ErrorResponseInternalServerError>{
                    body: {
                        actionStatus: "ERROR",
                        errorMessage: "Launch context resolution failed",
                        errorDescription: "Error resolving EHR launch context."
                    }
                };
            }
            if ctxResult is EhrLaunchContext {
                if !(resolvedPatientId is string) && ctxResult.patientId is string {
                    resolvedPatientId = ctxResult.patientId;
                }
                if ctxResult.encounterId is string {
                    resolvedEncounterId = ctxResult.encounterId;
                }
            }
        }

        // ── 6. SCIM patient ID fallback (if user is a patient) ───────────────
        if !(resolvedPatientId is string) {
            string? userId = reqBody.event.user?.id;
            if userId is string && userId != "" {
                json|error scimUser = fetchScimUser(userId);
                if scimUser is map<json> {
                    if isPatientGroupMember(scimUser) {
                        string? fhirUser = getFhirUserFromScim(scimUser);
                        if fhirUser is string {
                            resolvedPatientId = getPatientIdFromFhirUser(fhirUser);
                        }
                    }
                } else if scimUser is error {
                    log:printWarn(string `[${flowId}]: SCIM user lookup failed: ${scimUser.message()}`);
                }
            }
        }

        // ── 7. Add consent_id, patient and encounter claims ───────────────────
        if resolvedConsentId is string && resolvedConsentId != "" {
            ops.push({op: "add", path: "/accessToken/claims/-", value: {name: "consent_id", value: resolvedConsentId}});
        }
        if resolvedPatientId is string && resolvedPatientId != "" {
            ops.push({op: "add", path: "/accessToken/claims/-", value: {name: "patient", value: resolvedPatientId}});
        }
        if resolvedEncounterId is string && resolvedEncounterId != "" {
            ops.push({op: "add", path: "/accessToken/claims/-", value: {name: "encounter", value: resolvedEncounterId}});
        }

        log:printDebug(string `[${flowId}] final claims`, resolvedConsentId = resolvedConsentId ?: "(none)", resolvedPatientId = resolvedPatientId ?: "(none)", resolvedEncounterId = resolvedEncounterId ?: "(none)");
        log:printDebug(string `[${flowId}] returning SUCCESS`, operationCount = ops.length());
        return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: ops}};
    }

    # Adds fhirUser as an ID token claim when the fhirUser scope is requested.
    # + return - InlineResponse200Ok|ErrorResponseBadRequest|ErrorResponseInternalServerError
    isolated resource function post pre\-issue\-id\-token(@http:Payload json payload)
            returns InlineResponse200Ok|ErrorResponseBadRequest|ErrorResponseInternalServerError {

        IdTokenRequestBody|error reqBodyResult = payload.cloneWithType();
        if reqBodyResult is error {
            return <ErrorResponseBadRequest>{
                body: {actionStatus: "ERROR", errorMessage: "Invalid payload", errorDescription: reqBodyResult.message()}
            };
        }
        IdTokenRequestBody reqBody = reqBodyResult;
        string flowId = reqBody.flowId ?: "";
        log:printDebug(string `[${flowId}] pre-issue-id-token received`, payload = payload.toJsonString());

        string[]? tokenScopes = reqBody.event.request.scopes;
        boolean fhirUserScopeRequested = false;
        if tokenScopes is string[] {
            fhirUserScopeRequested = tokenScopes.indexOf("fhirUser") != ();
        }

        if !fhirUserScopeRequested {
            log:printDebug(string `[${flowId}] fhirUser scope not requested — no ID token claims added`);
            return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: []}};
        }

        string? userId = reqBody.event.user?.id;
        if !(userId is string) || userId == "" {
            log:printDebug(string `[${flowId}] no user ID in payload — skipping fhirUser claim`);
            return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: []}};
        }

        json|error scimUser = fetchScimUser(userId);
        if scimUser is error {
            log:printWarn(string `[${flowId}]: SCIM user lookup failed: ${scimUser.message()}`);
            return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: []}};
        }

        string? fhirUser = scimUser is map<json> ? getFhirUserFromScim(scimUser) : ();
        if !(fhirUser is string) || fhirUser == "" {
            log:printDebug(string `[${flowId}] no fhirUser attribute on SCIM user — skipping claim`);
            return <InlineResponse200Ok>{body: {actionStatus: "SUCCESS", operations: []}};
        }

        log:printDebug(string `[${flowId}] adding fhirUser ID token claim`, fhirUser = fhirUser);
        return <InlineResponse200Ok>{
            body: {
                actionStatus: "SUCCESS",
                operations: [{op: "add", path: "/idToken/claims/-", value: {name: "fhirUser", value: fhirUser}}]
            }
        };
    }
}

// ─── SCIM helpers (used only in SCIM fallback path) ──────────────────────────

isolated function isPatientGroupMember(map<json> scimUser) returns boolean {
    json groups = scimUser["groups"] ?: [];
    if groups is json[] {
        foreach json groupEntry in groups {
            if groupEntry is map<json> {
                json display = groupEntry["display"] ?: "";
                if display is string && display.toLowerAscii() == scimPatientGroupName.toLowerAscii() {
                    return true;
                }
            }
        }
    }
    return false;
}

isolated function getFhirUserFromScim(map<json> scimUser) returns string? {
    json customSchema = scimUser["urn:scim:schemas:extension:custom:User"] ?: {};
    if customSchema is map<json> {
        json fhirUser = customSchema[fhirUserAttributeName] ?: "";
        if fhirUser is string && fhirUser != "" {
            return fhirUser;
        }
    }
    json wso2Schema = scimUser["urn:scim:wso2:schema"] ?: {};
    if wso2Schema is map<json> {
        json fhirUser = wso2Schema[fhirUserAttributeName] ?: "";
        if fhirUser is string && fhirUser != "" {
            return fhirUser;
        }
    }
    return ();
}
