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
import ballerina/oauth2;
import ballerina/time;

final http:Client openfgcClient = check new (openfgcBaseUrl);

// Cached SCIM bearer token — avoids a token endpoint call on every request.
isolated record {|string token; int expiresAt;|}? _scimTokenCache = ();

// Lazy-init EHR client — created on first use, reused across requests.
isolated http:Client? _ehrClient = ();

isolated function getOrCreateEhrClient() returns http:Client|error {
    lock {
        http:Client? existing = _ehrClient;
        if existing is http:Client {
            return existing;
        }
        http:ClientConfiguration ehrClientConfig = {secureSocket: buildHttpSecureSocket()};
        http:Client c = check new (ehrContextResolveUrl, ehrClientConfig);
        _ehrClient = c;
        return c;
    }
}

// Looks up consentId for the given sessionDataKeyConsent from OpenFGC attributes endpoint.
// Returns () if no consent found (caller should treat as SUCCESS with no operations).
isolated function getConsentIdBySessionKey(string sessionDataKeyConsent) returns string?|error {
    string path = string `/consents/attributes?key=sessionDataKeyConsent&value=${getEncodedUri(sessionDataKeyConsent)}`;
    log:printDebug("[OpenFGC] GET consent by session key", path = path);
    http:Response response = check openfgcClient->get(path, {
        "org-id": orgId,
        "TPP-client-id": tppClientId
    });
    log:printDebug("[OpenFGC] GET consent by session key response", statusCode = response.statusCode);

    if response.statusCode < 200 || response.statusCode >= 300 {
        string|error bodyResult = response.getTextPayload();
        string body = bodyResult is string ? bodyResult : "";
        log:printError("[OpenFGC] GET consent by session key failed", statusCode = response.statusCode, body = body);
        return error(string `OpenFGC attributes lookup returned ${response.statusCode}: ${body}`);
    }

    json payload = check response.getJsonPayload();
    log:printDebug("[OpenFGC] GET consent by session key body", body = payload.toJsonString());
    if payload is map<json> {
        json consentIds = payload["consentIds"] ?: [];
        if consentIds is json[] && consentIds.length() > 0 {
            json first = consentIds[0];
            if first is string && first != "" {
                log:printDebug("[OpenFGC] Resolved consentId", consentId = first);
                return first;
            }
        }
    }
    log:printDebug("[OpenFGC] No consent found for session key", sessionDataKeyConsent = sessionDataKeyConsent);
    return ();
}

// Fetches approved scopes from the OpenFGC consent record.
// Looks in authorizations[].resources.scopes for scope-authorization entries.
isolated function getApprovedScopesByConsentId(string consentId) returns string[]|error {
    string path = string `/consents/${getEncodedUri(consentId)}`;
    log:printDebug("[OpenFGC] GET consent by ID", path = path);
    http:Response response = check openfgcClient->get(path, {
        "org-id": orgId,
        "TPP-client-id": tppClientId
    });
    log:printDebug("[OpenFGC] GET consent by ID response", statusCode = response.statusCode);

    if response.statusCode < 200 || response.statusCode >= 300 {
        string|error bodyResult = response.getTextPayload();
        string body = bodyResult is string ? bodyResult : "";
        log:printError("[OpenFGC] GET consent by ID failed", statusCode = response.statusCode, body = body);
        return error(string `OpenFGC consent lookup returned ${response.statusCode}: ${body}`);
    }

    json payload = check response.getJsonPayload();
    log:printDebug("[OpenFGC] GET consent by ID body", body = payload.toJsonString());
    if !(payload is map<json>) {
        return [];
    }

    json authorizations = payload["authorizations"] ?: [];
    if !(authorizations is json[]) {
        return [];
    }

    string[] scopes = [];
    foreach json auth in authorizations {
        if auth is map<json> {
            json resources = auth["resources"] ?: {};
            if resources is map<json> {
                json rawScopes = resources["scopes"] ?: [];
                if rawScopes is json[] {
                    foreach json s in rawScopes {
                        if s is string {
                            scopes.push(s);
                        }
                    }
                }
            }
        }
    }
    log:printDebug("[OpenFGC] Approved scopes extracted", scopes = scopes.toString());
    return scopes;
}

isolated function buildHttpSecureSocket() returns http:ClientSecureSocket? {
    if trustStorePath != "" && trustStorePassword != "" {
        return {cert: {path: trustStorePath, password: trustStorePassword}};
    }
    return ();
}

isolated function buildOAuth2SecureSocket() returns oauth2:SecureSocket? {
    if trustStorePath != "" && trustStorePassword != "" {
        return {cert: {path: trustStorePath, password: trustStorePassword}};
    }
    return ();
}

// Returns a bearer token for SCIM.
// Returns the cached token if still valid; otherwise fetches a new one and caches it for 50 min.
isolated function getScimToken() returns string|error {
    int nowEpoch = time:utcNow()[0];
    lock {
        var cached = _scimTokenCache;
        if cached is record {|string token; int expiresAt;|} && cached.expiresAt > nowEpoch + 60 {
            log:printDebug("[SCIM] Using cached bearer token");
            return cached.token;
        }
    }
    string tokenUrl = scimTokenEndpoint == "" ? string `${isBaseUrl}/oauth2/token` : scimTokenEndpoint;
    oauth2:ClientCredentialsGrantConfig grantConfig = {
        tokenUrl: tokenUrl,
        clientId: scimClientId,
        clientSecret: scimClientSecret,
        scopes: ["internal_user_mgt_view"]
    };
    oauth2:SecureSocket? secureSocket = buildOAuth2SecureSocket();
    if secureSocket != () {
        grantConfig.clientConfig = {secureSocket};
    }
    oauth2:ClientOAuth2Provider provider = new (grantConfig);
    string token = check provider.generateToken();
    lock {
        _scimTokenCache = {token: token, expiresAt: nowEpoch + 3000};
    }
    return token;
}

// Fetches SCIM user by ID for patient ID resolution.
// Returns () if SCIM not configured.
isolated function fetchScimUser(string userId) returns json|error {
    if isBaseUrl == "" || scimClientId == "" || scimClientSecret == "" {
        log:printDebug("[SCIM] Skipped — not configured");
        return ();
    }

    log:printDebug("[SCIM] Fetching token via client credentials");
    string token = check getScimToken();
    http:Client scimClient = check getOrCreateIsClient();
    string path = scimApiPath + "/" + getEncodedUri(userId);
    log:printDebug("[SCIM] GET user request", path = path);
    http:Response response = check scimClient->get(path, {
        "Authorization": string `Bearer ${token}`,
        "Accept": "application/scim+json"
    });
    log:printDebug("[SCIM] GET user response", statusCode = response.statusCode);

    if response.statusCode < 200 || response.statusCode >= 300 {
        string|error bodyResult = response.getTextPayload();
        string body = bodyResult is string ? bodyResult : "";
        log:printError("[SCIM] GET user failed", statusCode = response.statusCode, body = body);
        return error(string `SCIM returned ${response.statusCode}: ${body}`);
    }
    json result = check response.getJsonPayload();
    log:printDebug("[SCIM] GET user body", body = result.toJsonString());
    return result;
}

// Lazy-init IS client — used for token introspection.
isolated http:Client? _isClient = ();

isolated function getOrCreateIsClient() returns http:Client|error {
    lock {
        http:Client? existing = _isClient;
        if existing is http:Client {
            return existing;
        }
        http:ClientConfiguration isClientConfig = {secureSocket: buildHttpSecureSocket()};
        http:Client c = check new (isBaseUrl, isClientConfig);
        _isClient = c;
        return c;
    }
}

// Calls the IS /oauth2/introspect endpoint, forwarding the caller's Authorization header.
isolated function callIsIntrospect(string token, string authHeader) returns http:Response|error {
    if isBaseUrl == "" {
        return error("isBaseUrl not configured");
    }
    http:Client isClient = check getOrCreateIsClient();
    http:Request isReq = new;
    isReq.setHeader("Authorization", authHeader);
    isReq.setHeader("Content-Type", "application/x-www-form-urlencoded");
    isReq.setTextPayload(string `token=${getEncodedUri(token)}`);
    log:printDebug("[Introspect] POST /oauth2/introspect");
    http:Response response = check isClient->post("/oauth2/introspect", isReq);
    log:printDebug("[Introspect] IS introspect response", statusCode = response.statusCode);
    return response;
}

// Resolves EHR launch context from the configured URL.
isolated function resolveLaunchContext(string launchId) returns EhrLaunchContext?|error {
    if ehrContextResolveUrl == "" {
        log:printDebug("[EHR] Skipped — ehrContextResolveUrl not configured");
        return ();
    }
    http:Client ehrClient = check getOrCreateEhrClient();
    string path = string `/launch=${getEncodedUri(launchId)}`;
    log:printDebug("[EHR] GET launch context request", launchId = launchId, path = path);
    http:Response response = check ehrClient->get(path);
    log:printDebug("[EHR] GET launch context response", statusCode = response.statusCode);
    json payload = check response.getJsonPayload();
    log:printDebug("[EHR] GET launch context body", body = payload.toJsonString());
    EhrLaunchContext|error ctx = payload.cloneWithType();
    if ctx is EhrLaunchContext {
        return ctx;
    }
    log:printWarn(string `Failed to parse EHR launch context: ${ctx.message()}`);
    return ();
}
