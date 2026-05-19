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

import org.apache.axiom.om.OMElement;
import org.apache.axiom.om.util.AXIOMUtil;
import org.apache.axis2.AxisFault;
import org.apache.axis2.Constants;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.synapse.MessageContext;
import org.apache.synapse.commons.json.JsonUtil;
import org.apache.synapse.core.axis2.Axis2MessageContext;
import org.apache.synapse.mediators.AbstractMediator;
import org.hl7.fhir.r4.model.CapabilityStatement;
import org.hl7.fhir.r4.model.Enumerations;
import org.hl7.fhir.r4.model.Extension;
import org.wso2.carbon.apimgt.api.APIConsumer;
import org.wso2.carbon.apimgt.api.APIManagementException;
import org.wso2.carbon.apimgt.api.APIProvider;
import org.wso2.carbon.apimgt.api.model.API;
import org.wso2.carbon.apimgt.api.model.URITemplate;
import org.wso2.carbon.apimgt.impl.APIConstants;
import org.wso2.carbon.apimgt.impl.APIManagerFactory;
import org.wso2.carbon.governance.api.util.GovernanceArtifactConfiguration;
import org.wso2.carbon.governance.api.util.GovernanceUtils;
import org.wso2.carbon.registry.core.Registry;
import org.wso2.carbon.registry.core.exceptions.RegistryException;
import org.wso2.carbon.registry.core.session.UserRegistry;
import org.wso2.carbon.user.api.UserStoreException;
import org.wso2.healthcare.apim.core.OpenHealthcareException;
import org.wso2.healthcare.apim.core.api.server.FHIRServerConfigAPI;

import javax.xml.stream.XMLStreamException;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.wso2.healthcare.apim.conformance.Constants.*;

/**
 * This class will be referred by the synapse API for the /metadata endpoint.
 */
public class ConformanceMediator extends AbstractMediator {

    private static final Log LOG = LogFactory.getLog(ConformanceMediator.class);

    public ConformanceMediator() {

    }

    /**
     * standard way of mediating the message context in a class mediator.
     *
     * @param mc - message context
     * @return
     */
    public boolean mediate(MessageContext mc) {
        //endpoint https://localhost:8243/r4/metadata
        if (LOG.isDebugEnabled()) {
            LOG.debug("ConformanceMediator Started");
        }
        String tenant = mc.getProperty(TENANT_INFO_DOMAIN).toString();
        CapabilityStatement resource = createCapabilityStatement(tenant, mc);
        if (mc instanceof Axis2MessageContext) {
            org.apache.axis2.context.MessageContext axisMsgCtx =
                    ((Axis2MessageContext) mc).getAxis2MessageContext();
            Object headers = axisMsgCtx.getProperty(org.apache.axis2.context.MessageContext.TRANSPORT_HEADERS);
            String targetContentType = JSON_CONTENT_TYPE;
            if (headers instanceof Map) {
                Map headersMap = (Map) headers;
                if (headersMap.get(HTTP_HEADER_ACCEPT) != null) {
                    targetContentType = (String) headersMap.get(HTTP_HEADER_ACCEPT);
                }
            } else {
                if (LOG.isDebugEnabled()) {
                    LOG.debug("No HTTP Accept header found");
                }
            }
            if (XML_CONTENT_TYPE.equalsIgnoreCase(targetContentType) ||
                    TEXT_XML_CONTENT_TYPE.equalsIgnoreCase(targetContentType)) {
                try {
                    JsonUtil.removeJsonPayload(axisMsgCtx);
                    String payload;
                    payload = Util.serializeToXML(resource);
                    OMElement omXML = AXIOMUtil.stringToOM(payload);
                    axisMsgCtx.getEnvelope().getBody().addChild(omXML);
                    axisMsgCtx.setProperty(Constants.Configuration.MESSAGE_TYPE, FHIR_XML_CONTENT_TYPE);
                    axisMsgCtx.setProperty(Constants.Configuration.CONTENT_TYPE, FHIR_XML_CONTENT_TYPE);
                } catch (XMLStreamException e) {
                    LOG.error("Error occurred while populating XML payload in the message context", e);
                    throw new ConformanceMediatorException(
                            "Error occurred while populating XML payload in the message context", e);
                }
            } else {
                String payload;
                payload = Util.serializeToJSON(resource);
                try {
                    JsonUtil.getNewJsonPayload(axisMsgCtx, payload, true, true);
                    axisMsgCtx.setProperty(Constants.Configuration.MESSAGE_TYPE, FHIR_JSON_CONTENT_TYPE);
                    axisMsgCtx.setProperty(Constants.Configuration.CONTENT_TYPE, FHIR_JSON_CONTENT_TYPE);
                } catch (AxisFault axisFault) {
                    LOG.error("Error occurred while populating JSON payload in message context", axisFault);
                    throw new ConformanceMediatorException(
                            "Error occurred while populating JSON payload in message context",
                            axisFault);
                }
            }
            axisMsgCtx.removeProperty("NO_ENTITY_BODY");
        }
        return true;
    }

    public String getType() {

        return null;
    }

    /**
     * Create Capability Statement according to available resources in the tenant.
     *
     * @param tenant name of the tenant that requires capability statement for
     * @return capabilityStatement - A HAPI FHIR Capability Statement containing information about the available APIs
     * and endpoints of the tenant(FHIR Server)
     * @throws APIManagementException
     */

    public CapabilityStatement createCapabilityStatement(String tenant, MessageContext mc)
            throws ConformanceMediatorException {

        CapabilityStatement capabilityStatement = new CapabilityStatement();

        String serverName;
        String serverVersion;
        Registry registry;
        try {
            serverName = FHIRServerConfigAPI.getFHIRServerName();
            serverVersion = FHIRServerConfigAPI.getFHIRServerVersion();
            capabilityStatement.setDate(new Date(FHIRServerConfigAPI.getCapabilityStatementPublishedTime()));
            registry = Util.getUserRegistry(tenant);
        } catch (RegistryException | UserStoreException e) {
            LOG.error("Error occurred while retrieving User Registry for tenant", e);
            throw new ConformanceMediatorException("Error occurred while retrieving User Registry for tenant", e);
        } catch (OpenHealthcareException e) {
            LOG.error("Error occurred while retrieving FHIR server configs", e);
            throw new ConformanceMediatorException("Error occurred while retrieving FHIR server configs", e);
        }

        GovernanceArtifactConfiguration govConfig;
        try {
            GovernanceUtils.loadGovernanceArtifacts((UserRegistry) registry);
            govConfig = GovernanceUtils.findGovernanceArtifactConfiguration(APIConstants.API_KEY, registry);
        } catch (RegistryException e) {
            LOG.error("Error occurred while retrieving GovernanceArtifactConfiguration", e);
            throw new ConformanceMediatorException(
                    "Error occurred while retrieving GovernanceArtifactConfiguration", e);
        }

        List<API> allMatchedApis = new ArrayList<>();
        if (govConfig != null) {
            Set<API> tenantAPIs;
            try {
                tenantAPIs = getAllPublishedAPIs(tenant);
            } catch (APIManagementException e) {
                LOG.error("Error occurred while retrieving published APIs", e);
                throw new ConformanceMediatorException("Error occurred while retrieving published APIs", e);
            }
            allMatchedApis.addAll(tenantAPIs);
        }
        String gatewayBaseURL = Util.getGatewayEnvURL();

        capabilityStatement.setKind(CapabilityStatement.CapabilityStatementKind.INSTANCE);
        capabilityStatement.setName(serverName);
        capabilityStatement.setFhirVersion(Enumerations.FHIRVersion._4_0_1);
        capabilityStatement.setVersion(serverVersion);
        capabilityStatement.setStatus(Enumerations.PublicationStatus.ACTIVE);
        capabilityStatement.addFormat(SERVER_FORMAT_JSON);
        capabilityStatement.addFormat(SERVER_FORMAT_XML);
        capabilityStatement.addPatchFormat(SERVER_PATCH_FORMAT);
        CapabilityStatement.CapabilityStatementImplementationComponent implementationComponent =
                new CapabilityStatement.CapabilityStatementImplementationComponent();
        implementationComponent.setDescription(serverName);
        if (APIConstants.SUPER_TENANT_DOMAIN.equals(tenant)) {
            implementationComponent.setUrl(gatewayBaseURL);
        } else {
            implementationComponent.setUrl(Util.getTenantURL(gatewayBaseURL, tenant));
        }
        CapabilityStatement.CapabilityStatementRestComponent restComponent =
                new CapabilityStatement.CapabilityStatementRestComponent();
        restComponent.setMode(CapabilityStatement.RestfulCapabilityMode.SERVER);

        //security
        CapabilityStatement.CapabilityStatementRestSecurityComponent security =
                new CapabilityStatement.CapabilityStatementRestSecurityComponent();
        security.addService().addCoding().setCode(SERVER_REST_SECURITY_CODING_CODE).setDisplay(
                SERVER_REST_SECURITY_CODING_CODE).setSystem(SERVER_REST_SECURITY_CODING_SYSTEM);
        Extension oauthExtension = Util.createExtension("http://fhir-registry.smarthealthit" +
                ".org/StructureDefinition/oauth-uris", "", EXTENSION_VALUETYPE_SECURITY);
        oauthExtension.addExtension(
                Util.createExtension("token", Util.getKeyManagerProperty(tenant, 0, "token_endpoint"),
                        EXTENSION_VALUETYPE_SECURITY));
        oauthExtension.addExtension(
                Util.createExtension("revoke", Util.getKeyManagerProperty(tenant, 0, "revoke_endpoint"),
                        EXTENSION_VALUETYPE_SECURITY));
        oauthExtension.addExtension(
                Util.createExtension("authorize", Util.getKeyManagerProperty(tenant, 0, "authorize_endpoint"),
                        EXTENSION_VALUETYPE_SECURITY));
        //If willing to expose DCR endpoint, add DCR endpoint url as 'register' extension
        security.addExtension(oauthExtension);
        restComponent.setSecurity(security);

        //system level interactions
        restComponent.addInteraction(new CapabilityStatement.SystemInteractionComponent()
                .setCode(CapabilityStatement.SystemRestfulInteraction.SEARCHSYSTEM));

        //iterate for all APIs
        for (API api : allMatchedApis) {
            String apiDefinitionContent;
            OASHandler handler = null;
            apiDefinitionContent = api.getSwaggerDefinition();
            Util.SwaggerVersion swaggerVersion = Util.getSwaggerVersion(apiDefinitionContent);
            if (Util.SwaggerVersion.SWAGGER.equals(swaggerVersion)) {
                handler = new OAS2Handler(apiDefinitionContent);
            } else if (Util.SwaggerVersion.OPEN_API.equals(swaggerVersion)) {
                handler = new OAS3Handler(apiDefinitionContent);
            }

            if (handler != null) {
                Map<String, Object> extensions = handler.getVendorExtentions();
                if (extensions == null) {
                    continue;
                }
                if (extensions.get(SWAGGER_EXTENSION_RESOURCE_TYPE) != null) {
                    //FHIR API will be identified by the existence of x-wso2-oh-fhir-resourceType extension
                    CapabilityStatement.CapabilityStatementRestResourceComponent restResource =
                            new CapabilityStatement.CapabilityStatementRestResourceComponent();

                    restResource.setType(extensions.get(SWAGGER_EXTENSION_RESOURCE_TYPE).toString());
                    restResource.setConditionalCreate(false);
                    restResource.setConditionalDelete(
                            CapabilityStatement.ConditionalDeleteStatus.NOTSUPPORTED);
                    restResource
                            .setConditionalRead(CapabilityStatement.ConditionalReadStatus.NOTSUPPORTED);
                    restResource.setConditionalUpdate(false);

                    //supported profile will be added only for profiled resources
                    if (extensions.get(SWAGGER_EXTENSION_PROFILE) != null) {
                        List<String> supportedProfiles = (ArrayList<String>) extensions.get(SWAGGER_EXTENSION_PROFILE);
                        for (String profile : supportedProfiles) {
                            restResource.addSupportedProfile(profile);
                        }
                    }

                    restResource.setVersioning(CapabilityStatement.ResourceVersionPolicy.VERSIONED);
                    Set<URITemplate> uriTemplates = api.getUriTemplates();
                    for (URITemplate uriTemp : uriTemplates) {
                        CapabilityStatement.ResourceInteractionComponent interactionComponent =
                                new CapabilityStatement.ResourceInteractionComponent();
                        if (uriTemp.getUriTemplate().equals("/") && uriTemp.getHTTPVerb().equalsIgnoreCase("POST")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.CREATE);
                        }
                        if (uriTemp.getUriTemplate().equals("/") && uriTemp.getHTTPVerb().equalsIgnoreCase("GET")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.SEARCHTYPE);
                        }
                        if (uriTemp.getUriTemplate().equals("/{id}") && uriTemp.getHTTPVerb().equalsIgnoreCase(
                                "GET")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.READ);
                        }
                        if (uriTemp.getUriTemplate().equals("/{id}/_history/{vid}") &&
                                uriTemp.getHTTPVerb().equalsIgnoreCase("GET")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.VREAD);
                        }
                        if (uriTemp.getUriTemplate().equals("/{id}") && uriTemp.getHTTPVerb().equalsIgnoreCase(
                                "PUT")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.UPDATE);
                        }
                        if (uriTemp.getUriTemplate().equals("/{id}") && uriTemp.getHTTPVerb().equalsIgnoreCase(
                                "DELETE")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.DELETE);
                        }
                        if (uriTemp.getUriTemplate().equals("/_history") &&
                                uriTemp.getHTTPVerb().equalsIgnoreCase("POST")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.HISTORYINSTANCE);
                        }
                        if (uriTemp.getUriTemplate().equals("/{id}/_history") &&
                                uriTemp.getHTTPVerb().equalsIgnoreCase("GET")) {
                            interactionComponent.setCode(CapabilityStatement.TypeRestfulInteraction.HISTORYTYPE);
                        }

                        if (interactionComponent.getCode() != null) {
                            restResource.addInteraction(interactionComponent);
                        }
                    }
                    for (String searchParam : handler.getSearchParameters()) {
                        restResource.addSearchParam(
                                new CapabilityStatement.CapabilityStatementRestResourceSearchParamComponent().
                                        setName(searchParam).setType(Enumerations.SearchParamType.STRING));
                    }
                    restResource.addSearchRevInclude("null");
                    restResource.addReferencePolicy(CapabilityStatement.ReferenceHandlingPolicy.RESOLVES);
                    restComponent.addResource(restResource);
                }
            } else {
                String errorMsg = "Unable to set OAS handler for given API definition file. Unknown OAS version.";
                LOG.error(errorMsg);
            }
        }
        capabilityStatement.addRest(restComponent);
        capabilityStatement.setImplementation(implementationComponent);
        allMatchedApis.clear();
        return capabilityStatement;
    }

    public Set<API> getAllPublishedAPIs(String tenant) throws APIManagementException {
        APIProvider apiProvider = APIManagerFactory.getInstance().getAPIProvider(APIConstants.WSO2_ANONYMOUS_USER);

        List<API> apiList = apiProvider.getAllAPIs();

        Set<API> publishedApis = new HashSet<>();
        for (API api : apiList) {
            if (api.getStatus().equals(APIConstants.PUBLISHED)) {
                LOG.debug("Processing published API: " + api.getId().getApiName() + " version: " + api.getId().getVersion());
                try {
                    api.setSwaggerDefinition(getSwagger(api.getUuid(), tenant));
                    publishedApis.add(api);
                } catch (APIManagementException e) {
                    // This can occur due to apiId and tenant mismatch.
                    LOG.error("Error occurred while retrieving OpenAPI definition for API: " + api.getId(), e);
                    LOG.error("Failed to retrieve OpenAPI definition for API: " + api.getId().getApiName() + ", error: " + e.getMessage());
                }
            }
        }
        return publishedApis;
    }

    public String getSwagger(String apiId, String tenant) throws APIManagementException {
        APIConsumer apiConsumer = APIManagerFactory.getInstance().getAPIConsumer(APIConstants.WSO2_ANONYMOUS_USER);
        return apiConsumer.getOpenAPIDefinition(apiId, tenant);
    }
}
