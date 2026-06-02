/*
 * Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.wso2.healthcare.apim.conformance;

import java.util.Arrays;
import java.util.List;

/**
 * Constants required for conformance mediator.
 */
public class Constants {

    public static final String SERVER_PATCH_FORMAT = "application/json-patch+json";
    public static final String SERVER_FORMAT_JSON = "json";
    public static final String SERVER_FORMAT_XML = "xml";
    public static final String SERVER_URL =
            "http://hl7.org/fhir/us/Davinci-drug-formulary/CapabilityStatement/usdf-server";
    public static final String SERVER_REST_SECURITY_CODING_CODE = "SMART-on-FHIR";
    public static final String SERVER_REST_SECURITY_CODING_SYSTEM =
            "http://terminology.hl7.org/CodeSystem/restful-security-service";
    public static final String APIM_CORS_ENABLED = "CORSConfiguration.Enabled";
    public static final String EXTENSION_VALUETYPE_SECURITY = "security";
    public static final String EXTENSION_VALUETYPE_RESOURCE = "resource";

    public static final String JSON_CONTENT_TYPE = "application/json";
    public static final String XML_CONTENT_TYPE = "application/xml";
    public static final String FHIR_JSON_CONTENT_TYPE = "application/fhir+json";
    public static final String FHIR_XML_CONTENT_TYPE = "application/fhir+xml";
    public static final String TEXT_XML_CONTENT_TYPE = "text/xml";

    public static final String HTTP_HEADER_ACCEPT = "Accept";
    public static final String TENANT_INFO_DOMAIN = "tenant.info.domain";

    public static final String SWAGGER_EXTENSION_RESOURCE_TYPE = "x-wso2-oh-fhir-resourceType";
    public static final String SWAGGER_EXTENSION_PROFILE = "x-wso2-oh-fhir-profile";

    //TODO: populate these values from OH config file
    //Launch mode
    public static final String SMART_LAUNCH_MODE_STANDALONE = "launch-standalone";
    public static final String SMART_LAUNCH_MODE_EHR = "launch-ehr";

    //Client types http://hl7.org/fhir/smart-app-launch/conformance/index.html#client-types
    public static final String SMART_CLIENT_TYPE_CONFIDENTIAL = "client-confidential-symmetric";
    public static final String SMART_CLIENT_TYPE_PUBLIC = "client-public";

    //Single Sign-On
    public static final String SMART_SSO_SUPPORT = "sso-openid-connect";

    //Permissions as in http://hl7.org/fhir/smart-app-launch/conformance/index.html#permissions
    public static final String SMART_PERMISSIONS_PATIENT = "permission-patient";
    public static final String SMART_PERMISSIONS_OFFLINE = "permission-offline";
    public static final String SMART_PERMISSIONS_USER = "permission-user";

    //Launch context http://hl7.org/fhir/smart-app-launch/conformance/index.html#launch-context
    public static final String SMART_LAUNCH_CONTEXT_PATIENT = "context-standalone-patient";
    public static final String SMART_LAUNCH_CONTEXT_ENCOUNTER = "context-standalone-encounter";

    protected static final List<String> SMART_AUTH_METHODS = Arrays.asList("client_secret_basic", "client_secret_post");
    protected static final String SMART_GRANT_TYPES = "grant_types_supported";
    protected static final String SMART_CODE_CHALLENGE_METHODS = "code_challenge_methods_supported";
    protected static final String SMART_OAUTH_ISSUER = "issuer";
    protected static final String SMART_JWKS_URI = "jwks_uri";
    protected static final String GRANT_TYPE_AUTH_CODE = "authorization_code";
    protected static final String GRANT_TYPE_CLIENT_CREDENTIALS = "client_credentials";

    //Scopes supported http://hl7.org/fhir/smart-app-launch/scopes-and-launch-context/index.html
    protected static final List<String> SMART_SCOPES_SUPPORTED =
            Arrays.asList("openid", "launch/patient", "patient/*.cruds",
                    "user/*.cruds");
    protected static final List<String> SMART_RESPONSE_TYPES =
            Arrays.asList("code", "id_token", "token", "device", "id_token token");
    protected static final List<String> SMART_CAPABILITIES =
            Arrays.asList(SMART_LAUNCH_MODE_STANDALONE, SMART_LAUNCH_MODE_EHR, SMART_CLIENT_TYPE_PUBLIC, SMART_CLIENT_TYPE_CONFIDENTIAL,
                    SMART_LAUNCH_CONTEXT_PATIENT, SMART_SSO_SUPPORT, SMART_PERMISSIONS_PATIENT,
                    SMART_PERMISSIONS_OFFLINE);
}
