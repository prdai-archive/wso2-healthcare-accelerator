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

window.config = {
    // Base URL of the BFF service (leave empty to use the relative path)
    CONSENT_BFF_URL: "http://localhost:9092",
    // IDP authorize URL — used for the final form POST after consent is stored
    IDP_AUTHORIZE_URL: "https://localhost:9453/oauth2/authorize",
};
