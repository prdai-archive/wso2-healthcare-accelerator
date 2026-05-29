#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright (c) 2024, WSO2 Inc. (http://www.wso2.com). All Rights Reserved.
#
# This software is the property of WSO2 Inc. and its suppliers, if any.
# Dissemination of any information or reproduction of any material contained
# herein is strictly forbidden, unless permitted by WSO2 in accordance with
# the WSO2 Commercial License available at http://wso2.com/licenses. For specific
# language governing the permissions and limitations under this license,
# please see the license as well as any agreement you’ve entered into with
# WSO2 governing the purchase of this software and any associated services.
#
# ------------------------------------------------------------------------

# merge.sh script copy the WSO2 OH APIM accelerator artifacts on top of WSO2 APIM base product
#
# merge.sh <WSO2_OH_APIM_HOME>
# merge.sh -Dprofile=<gateway-worker or control-plane> <WSO2_OH_APIM_HOME>
# merge.sh <WSO2_OH_APIM_HOME> -Dprofile=<gateway-worker or control-plane>

# Initialize variables
PROFILE=""
WSO2_OH_APIM_HOME=""

# resolve links - $0 may be a softlink
PRG="$0"


# Parse arguments
for arg in "$@"; do
  case $arg in
    -Dprofile=*)
      PROFILE="${arg#*=}"
      if [[ "$PROFILE" != "gateway-worker" && "$PROFILE" != "control-plane" && "$PROFILE" != "traffic-manager" && "$PROFILE" != "api-key-manager-node" ]]; then
        echo -e "[ERROR] Invalid value for -Dprofile. Allowed values are 'gateway-worker', 'control-plane', 'traffic-manager' or 'api-key-manager-node'."
        exit 1
      fi
      ;;
    *)
      if [ -z "$WSO2_OH_APIM_HOME" ]; then
        WSO2_OH_APIM_HOME="$arg"
      else
        echo -e "[ERROR] Unknown argument: $arg"
        exit 1
      fi
      ;;
  esac
done

# Log the selected profile
if [[ -n "$PROFILE" ]]; then
  echo -e "[INFO] Profile selected: $PROFILE"
else
  echo -e "[INFO] No profile selected. Proceeding with default behavior."
fi

while [ -h "$PRG" ]; do
  ls=$(ls -ld "$PRG")
  link=$(expr "$ls" : '.*-> \(.*\)$')
  if expr "$link" : '.*/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=$(dirname "$PRG")/"$link"
  fi
done

# Get standard environment variables
PRGDIR=$(dirname "$PRG")

ACCELERATOR_HOME=$(cd "$PRGDIR/.." || exit ; pwd)

echo "[INFO] Accelerator home is: ${ACCELERATOR_HOME}"

# set product home
if [ "${WSO2_OH_APIM_HOME}" == "" ];
  then
    WSO2_OH_APIM_HOME=${ACCELERATOR_HOME}/..
fi

echo "[INFO] Product home is: ${WSO2_OH_APIM_HOME}"

# validate product home
if [ ! -d "${WSO2_OH_APIM_HOME}/repository/components" ]; then
  echo -e "[ERROR] Specified product path is not a valid carbon product path";
  exit 2;
else
  echo -e "[INFO] Valid carbon product path found";
fi

# Reading the config.toml file
config_toml_file="${ACCELERATOR_HOME}"/conf/config.toml

# Read values from the TOML file]
healthcare_theme_enabled=$(grep -E '^enable_healthcare_theme = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')

metadata_ep_enabled=$(grep -E '^enable_fhir_metadata_endpoint = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')
well_known_ep_enabled=$(grep -E '^enable_well_known_endpoint = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')
smart_on_fhir_enabled=$(grep -E '^enable_smart_on_fhir = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')
developer_workflow_enabled=$(grep -E '^enable_developer_workflow = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')

# create the hc-accelerator folder in product home, if not exist
WSO2_OH_ACCELERATOR_VERSION=$(cat "${ACCELERATOR_HOME}"/version.txt)
WSO2_OH_ACCELERATOR_AUDIT="${WSO2_OH_APIM_HOME}"/hc-accelerator
WSO2_OH_ACCELERATOR_AUDIT_BACKUP="${WSO2_OH_ACCELERATOR_AUDIT}"/backup
if [ ! -d  "${WSO2_OH_ACCELERATOR_AUDIT}" ]; then
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/jaggeryapps
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/webapps
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/conf
   echo -e "[INFO] Accelerator audit folder [""${WSO2_OH_ACCELERATOR_AUDIT}""] is created";
else
   echo -e "[INFO] Accelerator audit folder is present at [""${WSO2_OH_ACCELERATOR_AUDIT}""]";
fi

# backup original product files to the audit folder
echo -e "[INFO] Backup original product files.."
if [ -z "$(find "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}/webapps" -mindepth 1 -print -quit)" ]; then
  cp -R "${WSO2_OH_APIM_HOME}"/repository/deployment/server/webapps/accountrecoveryendpoint/ "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/webapps/accountrecoveryendpoint 2>/dev/null
  cp -R "${WSO2_OH_APIM_HOME}"/repository/deployment/server/webapps/authenticationendpoint/ "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/webapps/authenticationendpoint 2>/dev/null
  cp "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/conf 2>/dev/null
  cp "${WSO2_OH_APIM_HOME}"/repository/conf/claim-config.xml "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/conf 2>/dev/null
else
  echo -e "[INFO] Backup files already exist in the audit folder"
fi


# Reusable functions

configure_message_handlers() {
    local config_file="${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"

    # Configure XML formatter
    MATCH_FOUND=$(sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_formatters\]\](.*)content_type = \"application\/fhir\+xml\"/fhir-xml-formatter-found/g' "$config_file")
    if grep -q "fhir-xml-formatter-found" <<< "$MATCH_FOUND"; then
        sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_formatters\]\](.*)content_type = \"application\/fhir\+xml\"/\[\[custom_message_formatters\]\]\nclass = \"org.apache.axis2.transport.http.ApplicationXMLFormatter\"\ncontent_type = \"application\/fhir\+xml\"/g' "$config_file" > "${config_file}.bak.1"
        sed '1{/^$/d;}' "${config_file}.bak.1" > "${config_file}.bak.2"
        mv "${config_file}.bak.2" "$config_file"
        rm "${config_file}.bak.1"
    else
        echo -e "\n[[custom_message_formatters]]\nclass = \"org.apache.axis2.transport.http.ApplicationXMLFormatter\"\ncontent_type = \"application/fhir+xml\"" | tee -a "$config_file" >/dev/null
    fi

    # Configure XML builder
    MATCH_FOUND=$(sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_builders\]\](.*)content_type = \"application\/fhir\+xml\"/fhir-xml-builder-found/g' "$config_file")
    if grep -q "fhir-xml-builder-found" <<< "$MATCH_FOUND"; then
        sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_builders\]\](.*)content_type = \"application\/fhir\+xml\"/\[\[custom_message_builders\]\]\nclass = \"org.apache.axis2.builder.ApplicationXMLBuilder\"\ncontent_type = \"application\/fhir\+xml\"/g' "$config_file" > "${config_file}.bak.1"
        sed '1{/^$/d;}' "${config_file}.bak.1" > "${config_file}.bak.2"
        mv "${config_file}.bak.2" "$config_file"
        rm "${config_file}.bak.1"
    else
        echo -e "\n[[custom_message_builders]]\nclass = \"org.apache.axis2.builder.ApplicationXMLBuilder\"\ncontent_type = \"application/fhir+xml\"" | tee -a "$config_file" >/dev/null
    fi

    # Configure JSON formatter
    MATCH_FOUND=$(sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_formatters\]\](.*)content_type = \"application\/fhir\+json\"/fhir-json-formatter-found/g' "$config_file")
    if grep -q "fhir-json-formatter-found" <<< "$MATCH_FOUND"; then
        sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_formatters\]\](.*)content_type = \"application\/fhir\+json\"/\[\[custom_message_formatters\]\]\nclass = \"org.apache.synapse.commons.json.JsonStreamFormatter\"\ncontent_type = \"application\/fhir\+json\"/g' "$config_file" > "${config_file}.bak.1"
        sed '1{/^$/d;}' "${config_file}.bak.1" > "${config_file}.bak.2"
        mv "${config_file}.bak.2" "$config_file"
        rm "${config_file}.bak.1"
    else
        echo -e "\n[[custom_message_formatters]]\nclass = \"org.apache.synapse.commons.json.JsonStreamFormatter\"\ncontent_type = \"application/fhir+json\"" | tee -a "$config_file" >/dev/null
    fi

    # Configure JSON builder
    MATCH_FOUND=$(sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_builders\]\](.*)content_type = \"application\/fhir\+json\"/fhir-json-builder-found/g' "$config_file")
    if grep -q "fhir-json-builder-found" <<< "$MATCH_FOUND"; then
        sed -E '/./{H;$!d;} ; x ; s/\[\[custom_message_builders\]\](.*)content_type = \"application\/fhir\+json\"/\[\[custom_message_builders\]\]\nclass = \"org.apache.synapse.commons.json.JsonStreamBuilder\"\ncontent_type = \"application\/fhir\+json\"/g' "$config_file" > "${config_file}.bak.1"
        sed '1{/^$/d;}' "${config_file}.bak.1" > "${config_file}.bak.2"
        mv "${config_file}.bak.2" "$config_file"
        rm "${config_file}.bak.1"
    else
        echo -e "\n[[custom_message_builders]]\nclass = \"org.apache.synapse.commons.json.JsonStreamBuilder\"\ncontent_type = \"application/fhir+json\"" | tee -a "$config_file" >/dev/null
    fi
}

configure_claims_and_scopes() {
    local claim_config="${WSO2_OH_APIM_HOME}/repository/conf/claim-config.xml"
    local oidc_scope_config="${WSO2_OH_APIM_HOME}/repository/conf/identity/oidc-scope-config.xml"

    echo -e "[INFO] Adding configurations to claim-config.xml file"

    # Configure local claim
    local patient_id_claim="\t<Dialect dialectURI=\"http://wso2.org/claims\">\n<Claim>\n<ClaimURI>http://wso2.org/claims/patientId</ClaimURI>\n<DisplayName>Patient ID</DisplayName>\n<AttributeID>patientId</AttributeID>\n<Description>PatientID</Description>\n<DisplayOrder>13</DisplayOrder>\n<SupportedByDefault />\n</Claim>\n"
    if grep -Fq '<ClaimURI>http://wso2.org/claims/patientId</ClaimURI>' "$claim_config"; then
        echo -e "[WARN] PatientId local claim configuration already exist"
    else
        sed -i -e "s|<Dialect dialectURI=\"http://wso2.org/claims\">|${patient_id_claim}|g" "$claim_config"
    fi

    # Configure OIDC claim
    local patient_id_oidc_claim="\t<Dialect dialectURI=\"http://wso2.org/oidc/claim\">\n<Claim>\n<ClaimURI>patientId</ClaimURI>\n<DisplayName>Patient ID</DisplayName>\n<AttributeID>patientId</AttributeID>\n<Description>PatientID</Description>\n<DisplayOrder>13</DisplayOrder>\n<MappedLocalClaim>http://wso2.org/claims/patientId</MappedLocalClaim>\n</Claim>\n"
    if grep -Fq '<MappedLocalClaim>http://wso2.org/claims/patientId</MappedLocalClaim>' "$claim_config"; then
        echo -e "[WARN] PatientId OIDC claim configuration already exist"
    else
        sed -i -e "s|<Dialect dialectURI=\"http://wso2.org/oidc/claim\">|${patient_id_oidc_claim}|g" "$claim_config"
    fi

    echo -e "[INFO] Adding configurations to repository/conf/identity/oidc-scope-config.xml file"

    # Configure OIDC scopes using separate variables instead of an array
    local fhiruser_scope="<Scopes>\n\t<Scope id=\"fhirUser\">\n\t\t<Claim>patientId</Claim>\n\t</Scope>\n"
    local launch_patient_scope="<Scopes>\n\t<Scope id=\"launch\/patient\">\n\t\t<Claim>patientId</Claim>\n\t</Scope>\n"
    local offline_access_scope="<Scopes>\n\t<Scope id=\"offline_access\">\n\t\t<Claim>patientId</Claim>\n\t</Scope>\n"

    # Configure fhirUser scope
    if grep -Fq '<Scope id="fhirUser">' "$oidc_scope_config"; then
        echo -e "[WARN] fhirUser scope configuration already exist"
    else
        sed -i -e "s|<Scopes>|${fhiruser_scope}|g" "$oidc_scope_config"
    fi

    # Configure launch/patient scope
    if grep -Fq '<Scope id="launch/patient">' "$oidc_scope_config"; then
        echo -e "[WARN] launch/patient scope configuration already exist"
    else
        sed -i -e "s|<Scopes>|${launch_patient_scope}|g" "$oidc_scope_config"
    fi

    # Configure offline_access scope
    if grep -Fq '<Scope id="offline_access">' "$oidc_scope_config"; then
        echo -e "[WARN] offline_access scope configuration already exist"
    else
        sed -i -e "s|<Scopes>|${offline_access_scope}|g" "$oidc_scope_config"
    fi
}

echo -e "[INFO] Copying Open Healthcare artifacts.."
# adding the OH artifacts to the product pack
cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/components/* "${WSO2_OH_APIM_HOME}"/repository/components
cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/resources/* "${WSO2_OH_APIM_HOME}"/repository/resources
cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/deployment/server/synapse-configs/* "${WSO2_OH_APIM_HOME}"/repository/deployment/server/synapse-configs
if [ "${healthcare_theme_enabled}" == "true" ]; then
  cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/resources/extensions/* "${WSO2_OH_APIM_HOME}"/repository/resources/extensions/
else
  ## remove extensions related to healthcare theme
  find "${WSO2_OH_APIM_HOME}/repository/resources" -maxdepth 1 -type d -name "extensions*" -exec rm -r {} \;
  find "${WSO2_OH_APIM_HOME}/repository/deployment/server/webapps/accountrecoveryendpoint/extensions" -mindepth 1 -exec rm -r {} \;
  find "${WSO2_OH_APIM_HOME}/repository/deployment/server/webapps/authenticationendpoint/extensions" -mindepth 1 -exec rm -r {} \;
fi

if [ "${metadata_ep_enabled}" == "false" ]; then
  find "${WSO2_OH_APIM_HOME}/repository/components/dropins" -type f -name "*org.wso2.healthcare.apim.conformance*" -exec rm -f {} \;
  find "${WSO2_OH_APIM_HOME}/repository/components/dropins" -type f -name "*org.wso2.healthcare.apim.multitenancy*" -exec rm -f {} \;
fi

if [ "${smart_on_fhir_enabled}" == "false" ]; then
  find "${WSO2_OH_APIM_HOME}/repository/components" -type f -name "*org.wso2.healthcare.apim.scopemgt*" -exec rm -f {} \;
  find "${WSO2_OH_APIM_HOME}/repository/components" -type f -name "*org.wso2.healthcare.apim.tokenmgt*" -exec rm -f {} \;
fi

if [ "${developer_workflow_enabled}" == "false" ]; then
  find "${WSO2_OH_APIM_HOME}/repository/components/lib" -type f -name "*org.wso2.healthcare.apim.workflow.extensions*" -exec rm -f {} \;
fi

# adding configurations to deployment.toml file
echo -e "[INFO] Adding configurations to deployment.toml file"

if grep -Fxq "[healthcare.fhir]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
then
    # code if found
    echo -e "[WARN] healthcare.fhir configuration already exist"
else
    # code if not found
    echo -e "\n[healthcare.fhir]\nserver_name = \"WSO2 Open Healthcare\"\nserver_version = \"1.2.0\"\n## The time when the capability statement was published. It should be given in the format of yyyy-MM-dd'T'HH:mm:ss.SSS'Z. If not provided the server start time is taken by default.\n#server_metadata_published_time = \"2025-01-06T14:45:30.123Z\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
fi

if grep -Fxq "[apim.jwt]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
then
    # code if found
    echo -e "[WARN] apim.jwt configuration already exist"
else
    # code if not found
    echo -e "\n[apim.jwt]\nenable = true\nencoding = \"base64\" # base64,base64url\nclaim_dialect = \"http://wso2.org/claims\"\nconvert_dialect = false\nheader = \"X-JWT-Assertion\"\nsigning_algorithm = \"SHA256withRSA\"\nenable_user_claims = true\nclaims_extractor_impl = \"org.wso2.carbon.apimgt.impl.token.ExtendedDefaultClaimsRetriever\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
fi

if [ "${smart_on_fhir_enabled}" == "true" ]; then
  if grep -Fxq "[apim.oauth_config]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] apim.oauth_config configuration already exist"
  else
      # code if not found
      echo -e "\n[apim.oauth_config]\n#enable_outbound_auth_header = false\n#auth_header = \"Authorization\"\n#revoke_endpoint = \"https://localhost:\${https.nio.port}/revoke\"\n#enable_token_encryption = false\n#enable_token_hashing = false\nallowed_scopes = [\"^device_.*\", \"openid\", \"fhirUser\", \"launch/patient\", \"offline_access\"]"  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "[apim.jwt.gateway_generator]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] apim.jwt.gateway_generator configuration already exist"
  else
      # code if not found
      echo -e "\n[apim.jwt.gateway_generator]\nimpl = \"org.wso2.healthcare.apim.gateway.security.jwt.generator.HealthcareGatewayJWTGenerator\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "[oauth]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
    then
        # code if found
        echo -e "[WARN] oauth configuration already exist"
    else
        # code if not found
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS (BSD sed)
              sed -i '' '/\[oauth\.grant_type\.token_exchange\]/i\
[oauth]\
show_display_name_in_consent_page = true\

  ' "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
        else
            # Linux (GNU sed)
            sed -i '/\[oauth\.grant_type\.token_exchange\]/i [oauth]\nshow_display_name_in_consent_page = true' "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
        fi
        echo -e "[INFO] Added [oauth] configuration above [oauth.grant_type.token_exchange]"
    fi

  if grep -Fxq "[oauth.grant_type.authorization_code]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] oauth.grant_type.authorization_code configuration already exist"
  else
      # code if not found
      echo -e "\n[oauth.grant_type.authorization_code]\ngrant_handler = \"org.wso2.healthcare.apim.tokenmgt.handlers.OpenHealthcareExtendedAuthorizationCodeGrantHandler\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  # custom code response type handler
  if grep -Fxq "[[oauth.custom_response_type]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] oauth.custom_response_type configuration already exist"
  else
      # code if not found
      echo -e "\n[[oauth.custom_response_type]]\nname =\"code\"\nclass = \"org.wso2.healthcare.apim.scopemgt.handlers.OpenHealthcareExtendedCodeResponseTypeHandler\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  # custom key validation handler
  if grep -Fxq "[apim.key_manager]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
    # code if found
    echo -e "[WARN] apim.key_manager active configuration already exist"
  else
    # code if not found
    echo -e "\n[apim.key_manager]\nkey_validation_handler_impl = \"org.wso2.healthcare.apim.scopemgt.handlers.OpenHealthcareExtendedKeyValidationHandler\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  # scopemgt config
  if grep -Fxq "#[healthcare.identity.scopemgt]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.identity.scopemgt]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.identity.scopemgt configuration already exist"
  else
      # code if not found
      echo -e "\n[healthcare.identity.scopemgt]\nroles = [\"patient-read\", \"patient-write\", \"user-read\", \"user-write\"]\nenable_fhir_scope_to_wso2_scope_mapping = false"  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  # shared scopes
  if grep -Fxq "#[[healthcare.identity.scopemgt.shared_scopes]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[[healthcare.identity.scopemgt.shared_scopes]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.identity.scopemgt.shared_scopes configuration already exist"
  else
      # code if not found
     echo -e "\n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"patient/*.c\"\nname = \"patient/*.c\"\nroles = \"patient-write\"\ndescription = \"This scope grants patients access to CREATE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"patient/*.r\"\nname = \"patient/*.r\"\nroles = \"patient-write,patient-read\"\ndescription = \"This scope grants patients access to READ any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"patient/*.u\"\nname = \"patient/*.u\"\nroles = \"patient-write\"\ndescription = \"This scope grants patients access to UPDATE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"patient/*.d\"\nname = \"patient/*.d\"\nroles = \"patient-write\"\ndescription = \"This scope grants patients access to DELETE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"patient/*.s\"\nname = \"patient/*.s\"\nroles = \"patient-write,patient-read\"\ndescription = \"This scope grants patients access to SEARCH any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"user/*.c\"\nname = \"user/*.c\"\nroles = \"user-write\"\ndescription = \"This scope grants other users access to CREATE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"user/*.r\"\nname = \"user/*.r\"\nroles = \"user-write,user-read\"\ndescription = \"This scope grants other users access to READ any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"user/*.u\"\nname = \"user/*.u\"\nroles = \"user-write\"\ndescription = \"This scope grants other users access to UPDATE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"user/*.d\"\nname = \"user/*.d\"\nroles = \"user-write\"\ndescription = \"This scope grants other users access to DELETE any fhir resource.\"
     \n[[healthcare.identity.scopemgt.shared_scopes]]\nkey = \"user/*.s\"\nname = \"user/*.s\"\nroles = \"user-write,user-read\"\ndescription = \"This scope grants other users access to SEARCH any fhir resource.\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "#[healthcare.identity.claims]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.identity.claims]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.identity.claims configuration already exist"
  else
      # code if not found
      echo -e "\n#[healthcare.identity.claims]\n#patient_id_claim_uri = \"http://wso2.org/claims/patientId\"\n#patient_id_key = \"patientId\"\n#fhirUser_resource_url_context = \"/r4/Patient\"\n#fhirUser_resource_id_claim_uri = \"http://wso2.org/claims/patientId\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "#[[healthcare.backend.auth]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[[healthcare.backend.auth]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
    then
        # code if found
        echo -e "[WARN] healthcare.backend.auth configuration already exist"
    else
        # code if not found
        echo -e "\n#[[healthcare.backend.auth]]\n## Name of the authentication method. This name must be matched with the Config Name policy attribute in the -\n##  - Replace Backend Auth Token policy.\n#name = \"epic_pkjwt\"\n## Authentication type. Only pkjwt and client_credentials are supported atm.\n#auth_type = \"pkjwt\"\n## External Auth server's Token endpoint URL.\n#token_endpoint = \"https://localhost:9443/oauth2/token\"\n#client_id = \"client_id\"\n#private_key_alias = \"key_alias\"
     \n#[[healthcare.backend.auth]]\n#name = \"epic_client_credentials\"\n#auth_type = \"client_credentials\"\n#token_endpoint = \"https://localhost:9443/oauth2/token\"\n#client_id = \"client_id\"\n#client_secret = \"client_secret\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
    fi

  if grep -Fxq "#[healthcare.identity.claim.mgt]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.identity.claim.mgt]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.identity.claim.mgt configuration already exist"
  else
      # code if not found
      echo -e "\n#[healthcare.identity.claim.mgt]\n#enable = false"  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi
fi
if [ "${healthcare_theme_enabled}" == "true" ]; then
  if grep -Fxq "#[healthcare.deployment.webapps]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.deployment.webapps]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.deployment.webapps configuration already exist"
  else
      # code if not found
      echo -e "\n#[healthcare.deployment.webapps]\n#name = \"Open Healthcare\"\n#name_container_css = \"\"\n#terms_of_use = \"https://wso2.com/terms-of-use\"\n#privacy_policy = \"https://wso2.com/privacy-policy\"\n#cookie_policy = \"https://wso2.com/cookie-policy\"\n#logo = \"images/wso2-logo.svg\"\n#logoHeight = \"\"\n#logoWidth = \"\"\n#logo_container_css = \"\"\n#title = \"WSO2 Open Healthcare\"\n#favicon = \"libs/theme/assets/images/favicon.ico\"\n#footer = \"WSO2 Open Healthcare\"\n#footer_secondary_html = \"\"\n#main_color = \"#342382\"" | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "#[healthcare.deployment.webapps.authenticationendpoint]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.deployment.webapps.authenticationendpoint]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.deployment.webapps.authenticationendpoint configuration already exist"
  else
      # code if not found
      echo -e "\n#[healthcare.deployment.webapps.authenticationendpoint]\n#enable_selfsignup = true\n#selfsignup_url = \"\"\n# Name of deployment to mentioned in the poicy disclaimer.\n# The result will be : Usage of <signin_disclaimer_portal_name> is subject to the Terms of Use, Privacy Policy, and Cookie Policy.\n#signin_disclaimer_portal_name=\"WSO2 Open Healthcare\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "#[healthcare.deployment.webapps.accountrecovery]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[healthcare.deployment.webapps.accountrecovery]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] healthcare.deployment.webapps.accountrecovery configuration already exist"
  else
      # code if not found
      echo -e "\n#[healthcare.deployment.webapps.accountrecovery]\n#signup_flow.username_info_enable = false\n# Message to display at the end of successful self sign-up\n#signup_flow.success_message=\"User registration completed successfully\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "#[[apim.devportal.application_attributes]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "[[apim.devportal.application_attributes]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] apim.devportal.application_attributes configuration already exist"
  else
      # code if not found
      echo -e "\n#[[apim.devportal.application_attributes]]\n#required=true\n#hidden=false\n#name=\"Terms and Conditions Secure URL\"\n#description=\"Provide a secure URL where users can review your terms and conditions prior to authorizing access to their data.\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
  fi
fi

# Check if the section already exists
if grep -Fxq "#[apim.sync_runtime_artifacts.gateway.skip_list]" "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml" || \
   grep -Fxq "[apim.sync_runtime_artifacts.gateway.skip_list]" "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"; then
    echo -e "[WARN] apim.sync_runtime_artifacts.gateway.skip_list already exists"
else
    # Initialize the list
    SKIP_LIST=""

    # Conditionally add entries
    if [ "$metadata_ep_enabled" = true ]; then
        SKIP_LIST="\"_MetadataAPI_.xml\""
    fi

    if [ "$well_known_ep_enabled" = true ]; then
        # Add comma if SKIP_LIST already has an item
        if [ -n "$SKIP_LIST" ]; then
            SKIP_LIST="$SKIP_LIST, "
        fi
        SKIP_LIST="${SKIP_LIST}\"_WellKnownResourceAPI_.xml\""
    fi

    # Only write the section if at least one item is added
    if [ -n "$SKIP_LIST" ]; then
        echo -e "\n[apim.sync_runtime_artifacts.gateway.skip_list]\napis = [${SKIP_LIST}]" | \
            tee -a "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml" >/dev/null
    fi
fi

if grep -Fxq "[healthcare.organization]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "#[healthcare.organization]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
then
    # code if found
    echo -e "[WARN] healthcare.organization configuration already exists"
else
    # code if not found
    echo -e "\n#[healthcare.organization]\n#org_name = \"testOrg\"\n#contact_email = \"support@testorg.com\"\n#timezone = \"GMT\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
fi

if grep -Fxq "[[healthcare.notification.mail]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml || grep -Fxq "#[[healthcare.notification.mail]]" "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml
then
    # code if found
    echo -e "[WARN] healthcare.notification.mail configuration already exists"
else
    # code if not found
    echo -e "\n#[[healthcare.notification.mail]]\n#name = \"new_user_signup_requested_internal\"\n#enable = true\n#recipient_roles = \"approver,approver2\"\n#recipients = \"user1@test.com,user2@test.com\"\n#email_subject = \"[Developer Portal]  New User Signup - \${first_name} \${last_name}\"\n#email_body = \"<html><body>A new user has signed up at \${time} [\${timezone}] on \${date}. Visit the <a href=\\\"\${server_url}/admin/tasks/user-creation/\\\">admin portal</a> to approve/reject.</body></html>\"\n\n#[[healthcare.notification.mail]]\n#name = \"new_user_signup_completed_internal\"\n#enable = true\n#recipient_roles = \"approver,approver2\"\n#recipients = \"user1@test.com,user2@test.com\"\n#email_subject = \"[Developer Portal]  New User Signup - \${first_name} \${last_name}\"\n#email_body = \"<html><body>Signup request has been \${status} by \${approver}.</body></html>\"\n\n#[[healthcare.notification.mail]]\n#name = \"new_user_signup_completed_external\"\n#enable = true\n#email_subject = \"[\${org_name} Developer Portal] Your Signup Request Status\"\n#email_body = \"<html><body>Your signup request has been \${status}. Please email \${contact_email} if you have any questions.<br/>Thank you for your interest.<br/></body></html>\"\n\n#[[healthcare.notification.mail]]\n#name = \"new_app_creation_requested_internal\"\n#enable = true\n#recipient_roles = \"approver,approver2\"\n#recipients = \"user1@test.com,user2@test.com\"\n#email_subject = \"[Developer Portal] New Application \${app_name} Created by \${user_name}\"\n#email_body = \"<html><body>A new application has been created. Visit the <a href=\\\"\${server_url}/admin/tasks/application-creation/\\\">admin portal</a> to approve/reject.</body></html>\"\n\n#[[healthcare.notification.mail]]\n#name = \"new_app_creation_completed_internal\"\n#enable = true\n#recipient_roles = \"approver,approver2\"\n#recipients = \"user1@test.com,user2@test.com\"\n#email_subject = \"[Developer Portal] New Application \${app_name} Created by \${user_name}\"\n#email_body = \"<html><body>Application creation request has been \${status} by \${approver}.</body></html>\"\n\n#[[healthcare.notification.mail]]\n#name = \"new_app_creation_completed_external\"\n#enable = true\n#email_subject = \"[\${org_name} Developer Portal] Your Application Creation Request Status\"\n#email_body = \"<html><body>Your request to create the application \${app_name} has been \${status}. Please email \${contact_email} if you have any questions.<br/>Thank you for your interest.<br/></body></html>\""  | tee -a "${WSO2_OH_APIM_HOME}"/repository/conf/deployment.toml >/dev/null
fi

if [[ "$PROFILE" == "control-plane"  || "$PROFILE" == "traffic-manager" || "$PROFILE" == "api-key-manager-node" ]]; then
  # control-plane specific logic

  echo -e "[INFO] Removing specific message formatters and builders for $PROFILE profile."
  # Remove the ApplicationXMLFormatter for application/fhir+xml
  sed -i.bak '/\[\[custom_message_formatters\]\]/,/content_type = "application\/fhir\+xml"/d' "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"
  # Remove the ApplicationXMLBuilder for application/fhir+xml
  sed -i.bak '/\[\[custom_message_builders\]\]/,/content_type = "application\/fhir\+xml"/d' "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"
  # Remove the JsonStreamFormatter for application/fhir+json
  sed -i.bak '/\[\[custom_message_formatters\]\]/,/content_type = "application\/fhir\+json"/d' "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"
  # Remove the JsonStreamBuilder for application/fhir+json
  sed -i.bak '/\[\[custom_message_builders\]\]/,/content_type = "application\/fhir\+json"/d' "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml"
  # Clean up backup file created by sed
  rm -f "${WSO2_OH_APIM_HOME}/repository/conf/deployment.toml.bak"
  echo -e "[INFO] Removed message formatters and builders for $PROFILE profile."

  echo -e "[INFO] Applying configurations for Claims and Scopes."
  configure_claims_and_scopes

elif [[ "$PROFILE" == "gateway-worker" ]]; then
  # gateway-worker specific logic

  echo -e "[INFO] Removing specific scopes from oidc-scope-config.xml for gateway-worker profile."
  # Define the file path
  OIDC_SCOPE_CONFIG_FILE="${WSO2_OH_APIM_HOME}/repository/conf/identity/oidc-scope-config.xml"
  # Remove the <Scope id="offline_access"> block
  sed -i.bak '/<Scope id="offline_access">/,/<\/Scope>/d' "$OIDC_SCOPE_CONFIG_FILE"
  # Remove the <Scope id="launch/patient"> block
  sed -i.bak '/<Scope id="launch\/patient">/,/<\/Scope>/d' "$OIDC_SCOPE_CONFIG_FILE"
  # Remove the <Scope id="fhirUser"> block
  sed -i.bak '/<Scope id="fhirUser">/,/<\/Scope>/d' "$OIDC_SCOPE_CONFIG_FILE"
  # Clean up the backup file created by sed
  rm -f "${OIDC_SCOPE_CONFIG_FILE}.bak"
  echo -e "[INFO] Removed specific scopes from oidc-scope-config.xml for gateway-worker profile."

  echo -e "[INFO] Removing patientId claim configuration for gateway-worker profile."
  # Define the file path
  CLAIM_CONFIG_FILE="${WSO2_OH_APIM_HOME}/repository/conf/claim-config.xml"
  # Remove the patientId claim block including the opening <Claim> tag
  if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' '/<Claim>/{
            :a
            N
            /<\/Claim>/!ba
            /<ClaimURI>http:\/\/wso2.org\/claims\/patientId<\/ClaimURI>/d
        }' "$CLAIM_CONFIG_FILE"
    else
        # Linux version
        sed -i '/<Claim>/{
            :a
            N
            /<\/Claim>/!ba
            /<ClaimURI>http:\/\/wso2.org\/claims\/patientId<\/ClaimURI>/d
        }' "$CLAIM_CONFIG_FILE"
    fi
  # Clean up backup file created by sed
  rm -f "${CLAIM_CONFIG_FILE}.bak"
  echo -e "[INFO] Removed patientId claim configuration for gateway-worker profile."

  ## Calling reusable function to configure message handlers
  echo -e "[INFO] Configuring Message Handlers."
  configure_message_handlers

elif [[ -z "$PROFILE" ]]; then

  echo -e "[INFO] Applying configurations for Claims and Scopes."
  ## Calling reusable function to configure message handlers
  configure_claims_and_scopes
  ## Calling reusable function to configure message handlers
  echo -e "[INFO] Configuring Message Handlers."
  configure_message_handlers

fi

echo -e "[INFO] WSO2 Open Healthcare APIM Accelerator is successfully applied"

echo -e "$(date)" - "$USER" - "${WSO2_OH_ACCELERATOR_VERSION}" | tee -a "${WSO2_OH_ACCELERATOR_AUDIT}"/merge_audit.log >/dev/null

echo -e "[INFO] Done"
