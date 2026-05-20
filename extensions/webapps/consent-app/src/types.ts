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

export interface ConsentUser {
  id: string;
  displayName: string;
  email: string;
}

export interface ConsentPatient {
  id: string;
  name: string;
  fhirUser: string;
  mrn?: string;
}

export interface ConsentPurpose {
  purposeName: string;
  mandatory: boolean;
  purposeDescription?: string;
  elements: string[];
}

export interface ScopeConsentData {
  flow: 'scope';
  sessionDataKeyConsent: string;
  spId: string;
  user: ConsentUser;
  isPractitioner: boolean;
  patients?: ConsentPatient[];
  scopes: string[];
  hiddenScopes: string[];
  mandatoryClaims: string;
  existingConsentId?: string;
  previouslyApprovedScopes?: string[];
  consentExpiryTime?: string;
  consentToken: string;
}

export interface PurposeConsentData {
  flow: 'purpose';
  sessionDataKeyConsent: string;
  spId: string;
  appName: string;
  user: ConsentUser;
  purposes: ConsentPurpose[];
  scopes: string[];
  mandatoryClaims: string;
  existingConsentId?: string;
  previouslyConsentedPurposeNames?: string[];
  previouslyConsentedElements?: Record<string, string[]>;
  consentToken: string;
}

export interface RedirectConsentData {
  flow: 'redirect';
  redirectUrl: string;
}

export type ConsentData = ScopeConsentData | PurposeConsentData | RedirectConsentData;

export interface ConsentedPurpose {
  purposeName: string;
  consentedElements: string[];
}

export type ConsentExpiryOption = '24h' | '3months' | 'never';

export interface SubmitScopeConsentPayload {
  consentToken: string;
  sessionDataKeyConsent: string;
  spId: string;
  approved: boolean;
  approvedScopes?: string[];
  hiddenScopes?: string[];
  existingConsentId?: string;
  consentExpiryOption?: ConsentExpiryOption;
}

export interface SubmitPurposeConsentPayload {
  consentToken: string;
  sessionDataKeyConsent: string;
  spId: string;
  approved: boolean;
  consentedPurposes?: ConsentedPurpose[];
  existingConsentId?: string;
}
