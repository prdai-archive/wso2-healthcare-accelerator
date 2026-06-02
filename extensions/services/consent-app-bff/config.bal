// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

configurable string hostname = "localhost";
configurable int port = 9092;
configurable string corsAllowedOrigin = ?;

# Base URL of the identity provider (WSO2 IS or Asgardeo)
# e.g. "https://localhost:9443" or "https://api.asgardeo.io/t/mytenant"
configurable string idpBaseUrl = ?;

# OAuth2 token endpoint — defaults to {idpBaseUrl}/oauth2/token if empty
configurable string idpTokenEndpoint = "";

configurable string clientId = ?;

# OAuth2 client secret — also used as HS256 JWT signing secret
configurable string clientSecret = ?;

# Consent flow: "scope" (SMART scopes) or "purpose" (purposes + elements)
configurable string consentFlow = "scope";

configurable string openfgcBaseUrl = ?;
configurable string orgId = ?;
configurable string tppClientId = ?;
configurable string consentType = ?;

# Scope flow: OpenFGC wrapper names
configurable ScopeConsentConfig scopeConsent = {};

# Scopes always approved without user interaction (not shown in UI)
configurable string[] alwaysAllowedScopes = ["openid"];

# spId values that use the scope flow when consentFlow = "auto"
configurable string[] scopeConsentedApps = [];

# spId values that use the purpose flow when consentFlow = "auto"
configurable string[] purposeConsentedApps = [];

# Fallback URL when consentFlow = "auto" and client_id is in neither list.
# sessionDataKeyConsent and spId are appended as query params.
configurable string defaultIdpConsentPage = "";

# When true, look up an existing active consent and update it on re-submit
configurable boolean singleConsentPerUser = false;

# When true, show individual elements per purpose in the consent UI
configurable boolean showConsentElements = true;

configurable PurposeConsentConfig[] purposeConsent = [
    {purposeName: "All Health Data Access"}
];

configurable string consentContextApiTrustStorePath = "";
configurable string consentContextApiTrustStorePassword = "";

configurable string fhirUserAttributeName = "fhirUser";

# EHR launch context resolve endpoint (leave empty to disable)
configurable string ehrContextResolveUrl = "";

# Validity duration for scope consents sent to OpenFGC, in seconds (default: 3 hours)
configurable int scopeConsentValidityTime = 10800;
