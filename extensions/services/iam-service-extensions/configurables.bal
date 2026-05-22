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

configurable string hostname = "localhost";
configurable int port = 9093;

// OpenFGC — consent store
configurable string openfgcBaseUrl = "http://localhost:8080";
configurable string orgId = "";
configurable string tppClientId = "";

// EHR context resolution (optional — leave blank to skip)
configurable string ehrContextResolveUrl = "";

// IS base URL for SCIM and introspect endpoint (e.g. https://host:9443)
configurable string isBaseUrl = "";
// SCIM user lookup (optional — used to resolve patient ID from logged-in user)
configurable string scimApiPath = "/scim2/Users";
configurable string scimClientId = "";
configurable string scimClientSecret = "";
// Leave empty to default to {isBaseUrl}/oauth2/token
configurable string scimTokenEndpoint = "";
configurable string scimPatientGroupName = "patient";
configurable string fhirUserAttributeName = "fhirUser";
configurable string patientAttributeName = "patient";

// Key store for the HTTPS listener (leave blank to run as HTTP)
configurable string keystorePath = "";
configurable string keystorePassword = "";

// Trust store for HTTPS connections to the IDP/SCIM/EHR endpoints
configurable string trustStorePath = "";
configurable string trustStorePassword = "";

// Scopes that bypass consent checks (always included in token)
configurable string[] alwaysAllowedScopes = ["openid"];
