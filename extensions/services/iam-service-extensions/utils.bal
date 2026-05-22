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

import ballerina/url;

isolated function getEncodedUri(anydata value) returns string {
    string|error encoded = url:encode(value.toString(), "UTF8");
    return encoded is string ? encoded : value.toString();
}

isolated function getAdditionalParam(RequestParams[]? params, string name) returns string? {
    if params is RequestParams[] {
        foreach RequestParams param in params {
            if param.name == name && param.value.length() > 0 {
                return param.value[0];
            }
        }
    }
    return ();
}

isolated function extractSessionDataKeyConsent(Event event) returns string? {
    // The session object is a dynamic field not declared in the Event record.
    // Access it through the open record map.
    json session = event["session"].toJson();
    if session is map<json> && session.hasKey("sessionDataKeyConsent") {
        return session["sessionDataKeyConsent"].toString();
    }
    return ();
}

isolated function isAlwaysAllowedScope(string scope) returns boolean {
    foreach string allowed in alwaysAllowedScopes {
        if allowed == scope {
            return true;
        }
    }
    return false;
}

isolated function isScopeApproved(string scope, string[] approvedScopes) returns boolean {
    foreach string approved in approvedScopes {
        if approved == scope {
            return true;
        }
    }
    return false;
}

// system/* only allowed for client_credentials; patient/* and user/* blocked for client_credentials
isolated function isPermittedScope(string scope, string grantType) returns boolean {
    if scope.matches(re `^system/.*`) {
        return grantType == "client_credentials";
    }
    if grantType == "client_credentials" && scope.matches(re `^(patient|user)/.*`) {
        return false;
    }
    return true;
}

isolated function getLaunchIdFromScope(string scope) returns string? {
    if scope.startsWith("OH_launch/") && scope.length() > 10 {
        return scope.substring(10);
    }
    return ();
}

isolated function getPatientIdFromScope(string scope) returns string? {
    if scope.startsWith("OH_patient/") && scope.length() > 11 {
        return scope.substring(11);
    }
    return ();
}

