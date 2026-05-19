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

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.apache.commons.lang.StringUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.synapse.MessageContext;
import org.hl7.fhir.r4.model.CapabilityStatement;
import org.hl7.fhir.r4.model.Extension;
import org.hl7.fhir.r4.model.OperationOutcome;
import org.hl7.fhir.r4.model.UriType;
import org.wso2.carbon.CarbonConstants;
import org.wso2.carbon.apimgt.api.APIAdmin;
import org.wso2.carbon.apimgt.api.APIManagementException;
import org.wso2.carbon.apimgt.api.dto.KeyManagerConfigurationDTO;
import org.wso2.carbon.apimgt.api.model.Environment;
import org.wso2.carbon.apimgt.impl.APIAdminImpl;
import org.wso2.carbon.apimgt.impl.APIManagerConfiguration;
import org.wso2.carbon.apimgt.impl.internal.ServiceReferenceHolder;
import org.wso2.carbon.registry.core.Registry;
import org.wso2.carbon.registry.core.exceptions.RegistryException;
import org.wso2.carbon.user.api.UserStoreException;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;

/**
 * This class contains all the utility functions that are used in Conformance Mediator
 */
public class Util {

    private static final Log LOG = LogFactory.getLog(Util.class);

    /**
     * Creates an Extension objects for different fields
     *
     * @param url       required. URL of the extension
     * @param value     if available
     * @param valueType if available
     * @return Extension object
     */
    public static Extension createExtension(String url, String value, String valueType) {
        //todo: add other types of extensions
        if (valueType.equals("security")) {
            if (!StringUtils.isEmpty(value)) {
                return new Extension(url, new UriType(value));
            }
            return new Extension(url);
        } else if (valueType.equals("resource")) {
            return new Extension(url);
        }
        return new Extension(url);
    }

    /**
     * @param capabilityStatement complete capability statement
     * @return String containing serialized capability statement
     */
    public static String serializeToJSON(CapabilityStatement capabilityStatement) {
        // Create a FHIR context
        FhirContext ctx = FhirContext.forR4();
        // Create a parser
        IParser parser = ctx.newJsonParser();
        // Indent the output
        parser.setPrettyPrint(true);
        // Serialize it
        return parser.encodeResourceToString(capabilityStatement);
    }

    /**
     * @param capabilityStatement complete capability statement
     * @return String containing serialized capability statement
     */
    public static String serializeToXML(CapabilityStatement capabilityStatement) {
        // Create a FHIR context
        FhirContext ctx = FhirContext.forR4();
        // Create a parser
        IParser parser = ctx.newXmlParser();
        return parser.encodeResourceToString(capabilityStatement);
    }

    public static String serializeToXML(OperationOutcome operationOutcome) {
        // Create a FHIR context
        FhirContext ctx = FhirContext.forR4();
        // Create a parser
        IParser parser = ctx.newXmlParser();
        return parser.encodeResourceToString(operationOutcome);
    }

    public static Registry getUserRegistry(String tenant) throws RegistryException, UserStoreException {

        return ServiceReferenceHolder.getInstance().getRegistryService().
                getGovernanceUserRegistry(CarbonConstants.REGISTRY_ANONNYMOUS_USERNAME, getTenantId(tenant));
    }

    public static int getTenantId(String requestedTenantDomain) throws UserStoreException {

        return ServiceReferenceHolder.getInstance().getRealmService().getTenantManager()
                .getTenantId(requestedTenantDomain);
    }

    public static String getGatewayEnvURL() {

        APIManagerConfiguration apimConfig =
                ServiceReferenceHolder.getInstance().getAPIManagerConfigurationService().getAPIManagerConfiguration();

        Map.Entry<String, Environment> gwEnvEntry = apimConfig.getApiGatewayEnvironments().entrySet().stream()
                .filter(entry -> "hybrid".equals(entry.getValue().getType()) ||
                        "production".equals(entry.getValue().getType()))
                .findAny()
                .orElse(null);
        if (gwEnvEntry == null) {
            String errMsg = "Unable to find the production gateway environment";
            LOG.error(errMsg);
            throw new ConformanceMediatorException(errMsg);
        }
        String[] gwEPs = gwEnvEntry.getValue().getApiGatewayEndpoint().split(",");
        String baseUrl = null;
        for (String endpoint : gwEPs) {
            try {
                URL epUrl = new URL(endpoint.trim());
                if ("https".equals(epUrl.getProtocol())) {
                    baseUrl = epUrl.toString();
                    break;
                }
            } catch (MalformedURLException e) {
                throw new ConformanceMediatorException("Error occurred while parsing the gateway endpoint", e);
            }
        }
        if (baseUrl == null) return null;
        return (baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl);
    }

    public static String getTenantURL(String base, String tenantDomain) {

        return base + "/t/" + tenantDomain;
    }

    /**
     * Get configured Key Manager configs
     *
     * @param tenantDomain tenant domain in which Key Managers should retrieve
     * @return List of KeyManagers configured in APIM component.
     */
    public static List<KeyManagerConfigurationDTO> getKeyManagerConfigs(String tenantDomain) {
        APIAdmin apiAdmin = new APIAdminImpl();
        try {
            // Passing new boolean flag for 'checkUsages' as false with 4.3.0 onwards
            return apiAdmin.getKeyManagerConfigurationsByOrganization(tenantDomain, false);
        } catch (APIManagementException e) {
            throw new ConformanceMediatorException(e.getMessage());
        }

    }

    /**
     * Get supported grant types of All configured key managers. Admin portal API implementation is used here.
     *
     * @param tenantDomain tenant domain in which Key Managers should retrieve.
     * @return List of grant types supported
     */
    public static List<String> getSupportedGrantTypes(String tenantDomain) {

        List<String> supportedGrantTypes = new ArrayList<>();
        List<KeyManagerConfigurationDTO> keyManagerConfigurationsByTenant = getKeyManagerConfigs(tenantDomain);
        for (KeyManagerConfigurationDTO keyMangerConfig : keyManagerConfigurationsByTenant) {
            supportedGrantTypes.addAll((ArrayList<String>) keyMangerConfig.getAdditionalProperties().
                    get("grant_types"));
        }
        return supportedGrantTypes;
    }

    /**
     * Get specified property from a Key Manager.
     * todo: handle multiple key managers
     *
     * @param tenantDomain    tenant domain in which Key Managers should retrieve.
     * @param keyManagerIndex Index of the key manager to be considered.
     * @param propertyName    Name of the expected property.
     * @return requested Key Manager Property.
     */
    public static String getKeyManagerProperty(String tenantDomain, int keyManagerIndex, String propertyName) {
        return (String) getKeyManagerConfigs(tenantDomain).get(keyManagerIndex).getAdditionalProperties().get(
                propertyName);
    }

    /**
     * Get JWT signature algorithm
     *
     * @return Signing algorithm of default JWT generator.
     */
    public static String getSignatureAlgorithm() {
        APIManagerConfiguration config =
                ServiceReferenceHolder.getInstance().getAPIManagerConfigurationService().getAPIManagerConfiguration();
        return config.getJwtConfigurationDto().getSignatureAlgorithm();
    }

    public static JsonObject getWellKnownResponse(MessageContext mc) {

        String keyMgrHost = (String) mc.getProperty("keyManager.hostname");
        String keyMgrPort = (String) mc.getProperty("keyManager.port");
        JsonObject wellKnownResponse;
        try {
            if (keyMgrHost == null || keyMgrPort == null) {
                LOG.error("Key manager host and port are not set");
                throw new ConformanceMediatorException("Key manager host and port are not set");
            }
            // Specify the URL of the key manager's well-known endpoint
            URL url = new URL("https://" + keyMgrHost + ":" + keyMgrPort
                    + "/oauth2/token/.well-known/openid-configuration");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");

            // Get the response code
            int responseCode = conn.getResponseCode();

            if (responseCode == HttpURLConnection.HTTP_OK) {
                BufferedReader in = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                String inputLine;
                StringBuilder response = new StringBuilder();

                while ((inputLine = in.readLine()) != null) {
                    response.append(inputLine);
                }
                in.close();
                JsonParser parser = new JsonParser();
                wellKnownResponse = parser.parse(response.toString()).getAsJsonObject();
            } else {
                LOG.error("Error occurred while calling key manager well-known endpoint");
                throw new ConformanceMediatorException("Error occurred while calling key manager well-known endpoint");
            }
        } catch (Exception e) {
            LOG.error("Error occurred while calling key manager well-known endpoint", e);
            throw new ConformanceMediatorException("Error occurred while calling key manager well-known endpoint", e);
        }
        return wellKnownResponse;
    }

    /**
     * Swagger/OpenAPI spec version, used to select the appropriate OAS handler.
     */
    public enum SwaggerVersion {
        SWAGGER,   // OAS 2 — top-level "swagger" key
        OPEN_API,  // OAS 3 — top-level "openapi" key
        UNKNOWN
    }

    /**
     * Determine the OAS version of an API definition string without relying on
     * the deprecated {@code OASParserUtil.getSwaggerVersion()} from apimgt.
     *
     * <p>Detection rules:
     * <ul>
     *   <li>Presence of a top-level {@code "swagger"} key → {@link SwaggerVersion#SWAGGER} (OAS 2)</li>
     *   <li>Presence of a top-level {@code "openapi"} key → {@link SwaggerVersion#OPEN_API} (OAS 3)</li>
     *   <li>Anything else or a parse error → {@link SwaggerVersion#UNKNOWN}</li>
     * </ul>
     *
     * @param apiDefinition raw JSON string of the API definition
     * @return detected {@link SwaggerVersion}
     */
    public static SwaggerVersion getSwaggerVersion(String apiDefinition) {
        if (apiDefinition == null || apiDefinition.isEmpty()) {
            return SwaggerVersion.UNKNOWN;
        }
        try {
            JsonElement root = JsonParser.parseString(apiDefinition);
            if (!root.isJsonObject()) {
                return SwaggerVersion.UNKNOWN;
            }
            JsonObject obj = root.getAsJsonObject();
            if (obj.has("swagger")) {
                return SwaggerVersion.SWAGGER;
            }
            if (obj.has("openapi")) {
                return SwaggerVersion.OPEN_API;
            }
        } catch (Exception e) {
            LOG.warn("Failed to parse API definition to determine OAS version", e);
        }
        return SwaggerVersion.UNKNOWN;
    }

    /**
     * Get the current time in UTC format.
     *
     * @return current time in UTC format
     */
    public static Date getDateFromUTC(String utcTime) {
        try {
            // Create a SimpleDateFormat for parsing UTC string
            SimpleDateFormat utcFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
            utcFormat.setTimeZone(TimeZone.getTimeZone("UTC"));

            // Parse the UTC string into a Date object
            return utcFormat.parse(utcTime);
        } catch (ParseException e) {
            throw new ConformanceMediatorException("Error occurred while parsing UTC time", e);
        }
    }
}
