import ballerina/http;
import ballerina/jwt;
import ballerina/log;
import choreo/mediation;

http:Client? openFgcClient = ();

@mediation:RequestFlow
public function enforceRequestFlowConsent(mediation:Context ctx, http:Request req, string openFgcBaseUrl, string orgId, boolean failOnMissingConsent)
                                returns http:Response|false|error|() {

    log:printInfo("Request Flow Consent Enforcement Policy invoked");
    string resourcePath = ctx.resourcePath().toString();

    string[] headerNames = req.getHeaderNames();
    log:printInfo("Incoming request headers", headers = headerNames.toString(), resourcePath = resourcePath);

    // Bijira (WSO2 APIM) strips Authorization and forwards the decoded JWT via X-JWT-Assertion.
    // Fall back to Authorization header for direct/non-gateway invocations.
    string token = "";
    string|http:HeaderNotFoundError xJwt = req.getHeader("X-JWT-Assertion");
    if xJwt is string {
        token = xJwt;
    } else {
        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError {
            log:printInfo("Authorization header not found", resourcePath = resourcePath);
            return failOnMissingConsent ? forbidden("missing_consent_id", "") : ();
        }
        token = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : authHeader;
    }

    // Decode JWT
    [jwt:Header, jwt:Payload]|jwt:Error decoded = jwt:decode(token);
    if decoded is jwt:Error {
        log:printInfo("Failed to decode JWT", resourcePath = resourcePath);
        return failOnMissingConsent ? forbidden("missing_consent_id", "") : ();
    }
    var [_, payload] = decoded;

    // Extract consent_id
    string consentId = (payload["consent_id"] ?: "").toString();
    if consentId == "" {
        log:printInfo("consent_id not found in JWT", resourcePath = resourcePath);
        return failOnMissingConsent ? forbidden("missing_consent_id", "") : ();
    }
    log:printDebug("Extracted consent_id from JWT", consentId = consentId, resourcePath = resourcePath);

    // Lazy-init HTTP client
    http:Client fgcClient;
    http:Client? existing = openFgcClient;
    if existing is http:Client {
        fgcClient = existing;
    } else {
        http:Client|http:ClientError newClient = new (openFgcBaseUrl);
        if newClient is http:ClientError {
            log:printError("Failed to init openFGC client", 'error = newClient);
            return forbidden("consent_service_error", "");
        }
        openFgcClient = newClient;
        fgcClient = newClient;
        log:printDebug("Initialized openFGC HTTP client", baseUrl = openFgcBaseUrl);
    }

    // Call openFGC POST /consents/validate
    log:printDebug("Calling openFGC validate endpoint", consentId = consentId, baseUrl = openFgcBaseUrl);
    http:Request validateReq = new;
    validateReq.setJsonPayload({"consentId": consentId});
    validateReq.setHeader("org-id", orgId);
    validateReq.setHeader("Accept", "application/json");
    http:Response|http:ClientError consentResp = fgcClient->post("/consents/validate", validateReq);

    if consentResp is http:ClientError {
        log:printError("openFGC call failed", consentId = consentId, 'error = consentResp);
        return forbidden("consent_service_error", "");
    }

    if consentResp.statusCode != 200 {
        log:printInfo("openFGC returned non-200", consentId = consentId, statusCode = consentResp.statusCode);
        return forbidden("consent_not_found", "");
    }

    // Parse response and check isValid
    json|error body = consentResp.getJsonPayload();
    if body is error {
        log:printError("Failed to parse openFGC response", consentId = consentId);
        return forbidden("consent_service_error", "");
    }

    map<json>|error bodyMap = body.ensureType();
    if bodyMap is error {
        log:printError("Unexpected openFGC response format", consentId = consentId);
        return forbidden("consent_service_error", "");
    }
    log:printDebug("openFGC raw response", consentId = consentId, body = body.toString());

    boolean|error isValid = bodyMap["isValid"].ensureType();
    if isValid is error {
        log:printError("Failed to read isValid from openFGC response", consentId = consentId, 'error = isValid);
        return forbidden("consent_service_error", "");
    }
    if !isValid {
        log:printInfo("Consent invalid", consentId = consentId, resourcePath = resourcePath);
        return forbidden("consent_invalid", "");
    }

    // Extract FHIR resource type from first path segment
    string pathStr = resourcePath.startsWith("/") ? resourcePath.substring(1) : resourcePath;
    int? qIdx = pathStr.indexOf("?");
    if qIdx is int {
        pathStr = pathStr.substring(0, qIdx);
    }
    int? slashIdx = pathStr.indexOf("/");
    string fhirResourceType = slashIdx is int ? pathStr.substring(0, slashIdx) : pathStr;
    log:printDebug("Extracted FHIR resource type", resourceType = fhirResourceType, consentId = consentId);

    // Navigate consentInformation.purposes
    map<json>|error consentInfoMap = bodyMap["consentInformation"].ensureType();
    if consentInfoMap is error {
        log:printError("consentInformation missing or wrong format", consentId = consentId);
        return forbidden("consent_service_error", "");
    }

    json[]|error purposesArr = consentInfoMap["purposes"].ensureType();
    if purposesArr is error {
        log:printError("purposes missing or wrong format", consentId = consentId);
        return forbidden("consent_service_error", "");
    }

    // Check resource-level approval across all purposes
    boolean resourceFound = false;
    foreach json purpose in purposesArr {
        map<json>|error purposeMap = purpose.ensureType();
        if purposeMap is error { continue; }

        json[]|error elementsArr = purposeMap["elements"].ensureType();
        if elementsArr is error { continue; }

        foreach json element in elementsArr {
            map<json>|error elemMap = element.ensureType();
            if elemMap is error { continue; }

            map<json>|error propsMap = elemMap["properties"].ensureType();
            if propsMap is error { continue; }

            string rt = (propsMap["resourceType"] ?: "").toString();
            if rt != fhirResourceType { continue; }

            resourceFound = true;
            boolean|error approved = elemMap["isUserApproved"].ensureType();
            if approved is error || !approved {
                log:printInfo("Resource not approved in consent",
                    consentId = consentId, resourceType = fhirResourceType, resourcePath = resourcePath);
                return forbidden("consent_resource_not_approved", fhirResourceType);
            }
        }
    }

    if !resourceFound {
        log:printInfo("Resource type not found in consent",
            consentId = consentId, resourceType = fhirResourceType, resourcePath = resourcePath);
        return forbidden("consent_resource_not_found", fhirResourceType);
    }

    log:printInfo("Consent validated", consentId = consentId, resourceType = fhirResourceType, resourcePath = resourcePath);

    return ();
}

// @mediation:ResponseFlow
// public function enforceResponseFlowConsent(mediation:Context ctx, http:Request req, http:Response res, string openFgcBaseUrl, string orgId, boolean failOnMissingConsent)
//                                 returns http:Response|false|error|() {
//     return ();
// }

// @mediation:FaultFlow
// public function enforceFaultFlowConsent(mediation:Context ctx, http:Request req, http:Response? res, http:Response errFlowRes,
//                                     error e, string openFgcBaseUrl, string orgId, boolean failOnMissingConsent) returns http:Response|false|error|() {
//     return ();
// }

function forbidden(string reason, string consentStatus) returns http:Response {
    http:Response resp = new;
    resp.statusCode = 403;
    resp.setJsonPayload({"error": reason, "status": consentStatus});
    return resp;
}
