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

// ─── Config types ────────────────────────────────────────────────────────────

type ScopeConsentConfig record {|
    string purposeName = "SMART Scope Authorization";
|};

// Only the purpose name is configured here — description, mandatory flag, and
// elements are fetched from OpenFGC at startup via /consent-purposes.
type PurposeConsentConfig record {|
    string purposeName;
|};

// ─── OpenFGC /consent-purposes response types ─────────────────────────────────

type OpenFGCPurposeElement record {
    string name;
    boolean isMandatory;
};

type OpenFGCConsentPurpose record {
    string id?;
    string name;
    string description?;
    OpenFGCPurposeElement[] elements;
};

type OpenFGCConsentPurposesResponse record {
    OpenFGCConsentPurpose[] data;
};

// In-memory representation of a purpose fetched from OpenFGC at startup.
// readonly so it can be transferred into/out of isolated lock blocks without cloning.
type CachedPurpose readonly & record {|
    string name;
    string description?;
    string[] elementNames;
    boolean anyMandatory;
|};

// ─── Shared response types ────────────────────────────────────────────────────

type ConsentUser record {|
    string id;
    string displayName;
    string email;
|};

type ConsentPatient record {|
    string id;
    string name;
    string fhirUser;
    string mrn?;
|};

type ConsentPurpose record {|
    string purposeName;
    boolean mandatory;
    string purposeDescription?;
    string[] elements;
|};

// ─── get-consent-data response shapes ────────────────────────────────────────

type RedirectConsentData record {|
    string flow = "redirect";
    string redirectUrl;
|};

type ScopeConsentData record {|
    string flow = "scope";
    string sessionDataKeyConsent;
    string spId;
    ConsentUser user;
    boolean isPractitioner;
    ConsentPatient[] patients?;
    string[] scopes;
    string[] hiddenScopes;
    string mandatoryClaims;
    string existingConsentId?;
    string[] previouslyApprovedScopes?;
    string consentToken;
|};

type PurposeConsentData record {|
    string flow = "purpose";
    string sessionDataKeyConsent;
    string spId;
    string appName;
    ConsentUser user;
    ConsentPurpose[] purposes;
    string[] scopes;
    string mandatoryClaims;
    string existingConsentId?;
    string[] previouslyConsentedPurposeNames?;
    map<string[]> previouslyConsentedElements?;
    string consentToken;
|};

// ─── submit-consent request/response ─────────────────────────────────────────

type ConsentedPurpose record {|
    string purposeName;
    string[] consentedElements;
|};

type SubmitConsentRequest record {|
    string consentToken;
    string sessionDataKeyConsent;
    string spId;
    boolean approved;
    string[] approvedScopes?;
    string[] hiddenScopes?;
    ConsentedPurpose[] consentedPurposes?;
    string existingConsentId?;
    string consentExpiryOption?;
|};

type SubmitConsentResponse record {|
    string status;
    string message;
|};

// ─── EHR launch context ───────────────────────────────────────────────────────

type EhrLaunchContext record {|
    string launchId;
    string patientId?;
    string encounterId?;
    string aud;
    string expiry;
|};

// ─── IDP / OauthConsentKey response ──────────────────────────────────────────

// Open record — IDP may return additional fields (mandatoryClaims, etc.)
type IdpConsentKeyResponse record {
    string application;
    string scope;
    string loggedInUser;
    string mandatoryClaims?;
    string spQueryParams?;
};

// Internal type returned by getScimUser — includes fhirUser for isPractitioner check.
type ScimUserInfo record {|
    string id;
    string displayName;
    string email;
    string fhirUser;
|};

// ─── Internal type for existing consent lookup ────────────────────────────────

type ExistingConsentData record {|
    string consentId;
    int validityTime?;
    string[] approvedScopes;           // scope flow
    string[] consentedPurposeNames;    // purpose flow
    map<string[]> consentedElements;   // purpose flow
|};

// ─── OpenFGC payload types ────────────────────────────────────────────────────

type OpenFGCConsentElementApproval record {|
    string name;
    boolean isUserApproved;
|};

type OpenFGCConsentPurposeItem record {|
    string name;
    OpenFGCConsentElementApproval[] elements;
|};

type OpenFGCAuthorizationResources record {
    string spId;
    string application;
    string[] scopes?;
};

type OpenFGCAuthorization record {|
    string userId;
    string 'type;
    string status;
    OpenFGCAuthorizationResources resources;
|};

type OpenFGCConsentCreatePayload record {|
    string 'type;
    OpenFGCConsentPurposeItem[] purposes;
    OpenFGCAuthorization[] authorizations;
    int validityTime?;
    map<string> attributes?;
|};

type OpenFGCConsentCreatedResponse record {
    string id?;
    string status?;
};

// ─── OpenFGC search response types ───────────────────────────────────────────

// Open records: extra fields from OpenFGC are silently ignored.

type OpenFGCSearchElement record {
    string name;
    boolean isUserApproved;
};

type OpenFGCSearchPurpose record {
    string name;
    OpenFGCSearchElement[] elements;
};

type OpenFGCSearchResources record {
    string spId?;
    string application?;
    json scopes?;
};

type OpenFGCSearchAuthorization record {
    string userId?;
    string 'type?;
    string status?;
    OpenFGCSearchResources resources?;
};

type OpenFGCSearchRecord record {
    string id;
    int validityTime?;
    OpenFGCSearchPurpose[] purposes?;
    OpenFGCSearchAuthorization[] authorizations?;
};

type OpenFGCSearchResponse record {
    OpenFGCSearchRecord[] data;
};

type OpenFGCConsentAttributeSearchResponse record {|
    string[] consentIds;
    int count;
|};
