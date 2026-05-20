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

// ─── Token action request ─────────────────────────────────────────────────────

type RequestParams record {
    string name;
    string[] value;
};

type RequestHeaders record {
    string name;
    string[] value;
};

type Request record {
    string grantType;
    string clientId;
    string[] scopes?;
    RequestHeaders[] additionalHeaders?;
    RequestParams[] additionalParams?;
};

type AccessTokenClaims record {
    string name?;
    string|int|boolean|string[] value?;
};

type AccessToken record {
    "JWT" tokenType;
    AccessTokenClaims[] claims;
    string[] scopes?;
};

type RefreshTokenClaims record {
    string name?;
    int value?;
};

type RefreshToken record {
    RefreshTokenClaims[] claims;
};

type Tenant record {
    string id;
    string name;
};

type Organization record {
    string id;
    string name;
    string orgHandle;
    int depth;
};

type UserStore record {
    string id;
    string name;
};

type User record {
    string id;
    Organization organization?;
    string userType?;
    # The name of the federated identity provider used to authenticate the user. This is only applicable for `FEDERATED` users.
    string federatedIdP?;
    # Refers to the organization that the user is accessing. Applies only to the `organization_switch` grant type.
    Organization accessingOrganization?;
};

// Open record — session and other dynamic fields live alongside defined ones
type Event record {
    Request request;
    Tenant tenant;
    Organization organization?;
    User user?;
    UserStore userStore?;
    AccessToken accessToken;
};

type RequestBody record {
    string flowId?;
    string requestId?;
    "PRE_ISSUE_ACCESS_TOKEN" actionType;
    Event event;
};

// ─── Token action response ────────────────────────────────────────────────────

type CustomValue record {
    string name;
    string|int|boolean|string[] value;
};

type addOperationResponse record {
    "add" op;
    string path;
    string|CustomValue value;
};

type removeOperationResponse record {
    "remove" op;
    string path;
};

type replaceOperationResponse record {
    "replace" op;
    string path;
    string value;
};

type SuccessResponse record {
    "SUCCESS" actionStatus;
    (addOperationResponse|replaceOperationResponse|removeOperationResponse)[] operations?;
};

type ErrorResponse record {
    "ERROR" actionStatus;
    string errorMessage;
    string errorDescription;
};

type InlineResponse200Ok record {|
    *http:Ok;
    SuccessResponse body;
|};

type ErrorResponseBadRequest record {|
    *http:BadRequest;
    ErrorResponse body;
|};

type ErrorResponseInternalServerError record {|
    *http:InternalServerError;
    ErrorResponse body;
|};

// ─── EHR launch context ───────────────────────────────────────────────────────

type EhrLaunchContext record {|
    string patientId?;
    string encounterId?;
    string launchId;
    string aud;
    string expiry;
|};

# Provides a set of configurations for controlling the behaviours when communicating with a remote HTTP endpoint.
@display {label: "Connection Config"}
public type ConnectionConfig record {|
    # Provides Auth configurations needed when communicating with a remote HTTP endpoint.
    http:BearerTokenConfig|http:CredentialsConfig|ApiKeysConfig auth;
    # The HTTP version understood by the client
    http:HttpVersion httpVersion = http:HTTP_2_0;
    # Configurations related to HTTP/1.x protocol
    http:ClientHttp1Settings http1Settings = {};
    # Configurations related to HTTP/2 protocol
    http:ClientHttp2Settings http2Settings = {};
    # The maximum time to wait (in seconds) for a response before closing the connection
    decimal timeout = 30;
    # The choice of setting `forwarded`/`x-forwarded` header
    string forwarded = "disable";
    # Configurations associated with Redirection
    http:FollowRedirects followRedirects?;
    # Configurations associated with request pooling
    http:PoolConfiguration poolConfig?;
    # HTTP caching related configurations
    http:CacheConfig cache = {};
    # Specifies the way of handling compression (`accept-encoding`) header
    http:Compression compression = http:COMPRESSION_AUTO;
    # Configurations associated with the behaviour of the Circuit Breaker
    http:CircuitBreakerConfig circuitBreaker?;
    # Configurations associated with retrying
    http:RetryConfig retryConfig?;
    # Configurations associated with cookies
    http:CookieConfig cookieConfig?;
    # Configurations associated with inbound response size limits
    http:ResponseLimitConfigs responseLimits = {};
    # SSL/TLS-related options
    http:ClientSecureSocket secureSocket?;
    # Proxy server related options
    http:ProxyConfig proxy?;
    # Provides settings related to client socket configuration
    http:ClientSocketConfig socketConfig = {};
    # Enables the inbound payload validation functionality which provided by the constraint package. Enabled by default
    boolean validation = true;
    # Enables relaxed data binding on the client side. When enabled, `nil` values are treated as optional, 
    # and absent fields are handled as `nilable` types. Enabled by default.
    boolean laxDataBinding = true;
|};

type IdTokenRequestBody record {
    # A unique identifier that associates with the token issuing flow in WSO2 Identity Server
    string flowId?;
    # A unique correlation identifier that associates with the token request received by WSO2 Identity Server
    string requestId?;
    # Specifies the action being triggered, which in this case is PRE_ISSUE_ID_TOKEN.
    "PRE_ISSUE_ID_TOKEN" actionType;
    # Defines the context data related to the pre issue ID token event that needs to be shared with the custom service to process and execute.
    IdTokenEvent event;
    # Defines the set of operations that your external service is permitted to perform on the ID token's claims.
    AllowedOperations allowedOperations;
};

public type replaceOperation record {
    "replace" op;
    string[] paths;
};

public type AllowedOperations (addOperation|replaceOperation|removeOperation)[];

public type IdToken record {
    # An array that contains both standard ID token claims and any OpenID Connect (OIDC) claims configured to be included in the ID token.
    # 
    # Standard claims:
    # 
    # - **iss**: The issuer of the token.
    # - **at_hash**: The hash of the access token value.
    # - **c_hash**: The hash of the authorization code value.
    # - **s_hash**: The hash of the state value.
    # - **sid**: The session ID claim.
    # - **expires_in**: The duration (in seconds) for which the token is valid.
    # - **realm**: The realm (tenant or organization context).
    # - **tenant**: The tenant identifier.
    # - **userstore**: The user store identifier.
    # - **isk**: The identity provider session key.
    # - **sub**: The subject identifier for the token.
    # - **aud**: The audience for the token.
    # - **exp**: The expiration time (Unix timestamp).
    # - **iat**: The time at which the token was issued (Unix timestamp).
    # - **auth_time**: The time at which the user authenticated (Unix timestamp).
    # - **nonce**: The nonce value.
    # - **acr**: The authentication context class reference.
    # - **amr**: The authentication methods references.
    # - **azp**: The authorized party for the token.
    # 
    # OIDC claims are any additional claims configured in the application to be included in the ID token. These claims are based on the OIDC standard and may include user profile information such as email, given_name, or custom claims specific to the application.
    IdTokenClaims[] claims;
};

public type IdTokenClaims record {
    string name;
    string|int|boolean|string[]|record {} value?;
};

# Defines the context data related to the pre issue ID token event that needs to be shared with the custom service to process and execute.
type IdTokenEvent record {
    # Any additional parameters included in the ID token request. These may be custom parameters defined by the client or necessary for specific flows.
    Request request;
    # This property represents the tenant under which the token request is being processed.
    Tenant tenant;
    # Contains information about the authenticated user associated with the token request.
    User user?;
    # This property represents the organization context.
    Organization organization?;
    # Indicates the user store in which the user's data is being managed.
    UserStore userStore?;
    # Represents the ID token that is about to be issued. It contains claims of the ID token which can then be modified by your external service based on the logic implemented in the pre-issue ID token action.
    IdToken idToken;
};

public type ApiKeysConfig record {|
    string X\-API\-Key;
|};

# Defines the add operation.
# 
# + op - The type of operation to be performed, which is "add" in this case.
# + paths - An array of JSON paths indicating where the new claims should be added in the
public type addOperation record {
    "add" op;
    string[] paths;
};

# Defines the remove operation.
# # 
# + op - The type of operation to be performed, which is "add" in this case.
# + paths - An array of JSON paths indicating where the new claims should be added in the
public type removeOperation record {
    "remove" op;
    string[] paths;
};
