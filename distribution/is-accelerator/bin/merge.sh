#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright (c) 2026, WSO2 Inc. (http://www.wso2.com). All Rights Reserved.
#
# This software is the property of WSO2 Inc. and its suppliers, if any.
# Dissemination of any information or reproduction of any material contained
# herein is strictly forbidden, unless permitted by WSO2 in accordance with
# the WSO2 Commercial License available at http://wso2.com/licenses. For specific
# language governing the permissions and limitations under this license,
# please see the license as well as any agreement you've entered into with
# WSO2 governing the purchase of this software and any associated services.
#
# ------------------------------------------------------------------------

# merge.sh script copy the WSO2 OH IS accelerator artifacts on top of WSO2 IS base product
#
# merge.sh <WSO2_OH_IS_HOME>

# Initialize variables
WSO2_OH_IS_HOME=""
PATCH_MODE=false

# resolve links - $0 may be a softlink
PRG="$0"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --patch)
      PATCH_MODE=true
      ;;
    *)
      if [ -z "$WSO2_OH_IS_HOME" ]; then
        WSO2_OH_IS_HOME="$arg"
      else
        echo -e "[ERROR] Unknown argument: $arg"
        exit 1
      fi
      ;;
  esac
done

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
if [ "${WSO2_OH_IS_HOME}" == "" ];
  then
    WSO2_OH_IS_HOME=${ACCELERATOR_HOME}/..
fi

echo "[INFO] Product home is: ${WSO2_OH_IS_HOME}"

# validate product home
if [ ! -d "${WSO2_OH_IS_HOME}/repository/components" ]; then
  echo -e "[ERROR] Specified product path is not a valid carbon product path";
  exit 2;
else
  echo -e "[INFO] Valid carbon product path found";
fi

# Reading the config.toml file
config_toml_file="${ACCELERATOR_HOME}"/conf/config.toml

# Read values from the TOML file
enable_smart_on_fhir=$(grep -E '^enable_smart_on_fhir = ' "$config_toml_file" | cut -d'=' -f2 | tr -d ' ')

# create the hc-accelerator folder in product home, if not exist
WSO2_OH_ACCELERATOR_VERSION=$(cat "${ACCELERATOR_HOME}"/version.txt)
WSO2_OH_ACCELERATOR_AUDIT="${WSO2_OH_IS_HOME}"/hc-accelerator
WSO2_OH_ACCELERATOR_AUDIT_BACKUP="${WSO2_OH_ACCELERATOR_AUDIT}"/backup
if [ ! -d  "${WSO2_OH_ACCELERATOR_AUDIT}" ]; then
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"
   mkdir -p "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/conf
   echo -e "[INFO] Accelerator audit folder [""${WSO2_OH_ACCELERATOR_AUDIT}""] is created";
else
   echo -e "[INFO] Accelerator audit folder is present at [""${WSO2_OH_ACCELERATOR_AUDIT}""]";
fi

# backup original product files to the audit folder
echo -e "[INFO] Backup original product files.."
if [ -z "$(find "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}/conf" -mindepth 1 -print -quit)" ]; then
  cp "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}"/conf 2>/dev/null
else
  echo -e "[INFO] Backup files already exist in the audit folder"
fi

echo -e "[INFO] Copying WSO2 Healthcare artifacts.."
# adding the OH artifacts to the product pack
cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/components/* "${WSO2_OH_IS_HOME}"/repository/components

if [ "${PATCH_MODE}" == "true" ]; then
  # TODO: remove this once the patched version of org.wso2.carbon.identity.oauth is released in the WSO2 IS product pack
  # remove the stock identity.oauth jar to avoid class conflicts with the patched version
  echo -e "[INFO] Removing stock org.wso2.carbon.identity.oauth jar from plugins.."
  find "${WSO2_OH_IS_HOME}"/repository/components/plugins -maxdepth 1 -name "org.wso2.carbon.identity.oauth_*.jar" -delete
  echo -e "[INFO] Removed org.wso2.carbon.identity.oauth jar"
  # adding the temporary IS resources to the product pack until the fixes are available in official pack
  echo -e "[INFO] Copying temporary IS patch resources.."
  cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/temp/components/dropins/* "${WSO2_OH_IS_HOME}"/repository/components/dropins
  cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/temp/deployment/server/webapps/* "${WSO2_OH_IS_HOME}"/repository/deployment/server/webapps
  echo -e "[INFO] Patch resources applied"
fi

# adding the consent webapp
echo -e "[INFO] Deploying consent webapp.."
CONSENT_WEBAPP_PATH="${WSO2_OH_IS_HOME}/repository/deployment/server/webapps/open-healthcare"
CONSENT_CONFIG_JS="${CONSENT_WEBAPP_PATH}/config.js"

# backup config.js if it exists from a previous deployment
if [ -f "${CONSENT_CONFIG_JS}" ]; then
  cp -f "${CONSENT_CONFIG_JS}" "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}/config.js"
  echo -e "[INFO] Backed up existing config.js"
fi

mkdir -p "${CONSENT_WEBAPP_PATH}"
cp -R "${ACCELERATOR_HOME}"/carbon-home/repository/deployment/server/webapps/open-healthcare/* "${CONSENT_WEBAPP_PATH}"

# restore config.js after deploying new webapp artifacts
if [ -f "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}/config.js" ]; then
  cp -f "${WSO2_OH_ACCELERATOR_AUDIT_BACKUP}/config.js" "${CONSENT_CONFIG_JS}"
  echo -e "[INFO] Restored config.js"
fi

# adding configurations to deployment.toml file
echo -e "[INFO] Adding configurations to deployment.toml file"

# ensure server offset is set to 10
DEPLOYMENT_TOML="${WSO2_OH_IS_HOME}/repository/conf/deployment.toml"
SERVER_BLOCK=$(awk '/^\[server\]/{found=1; next} found && /^\[/{exit} found{print}' "${DEPLOYMENT_TOML}")
if echo "${SERVER_BLOCK}" | grep -qE '^\s*offset\s*='; then
  echo -e "[INFO] Server offset is already configured, skipping"
else
  # offset is commented or missing — insert after [server] line
  awk '/^\[server\]/{print; print "offset = 10"; next} {print}' "${DEPLOYMENT_TOML}" > "${DEPLOYMENT_TOML}.tmp" && mv "${DEPLOYMENT_TOML}.tmp" "${DEPLOYMENT_TOML}"
  echo -e "[INFO] Added offset = 10 under [server]"
fi

if [ "${enable_smart_on_fhir}" == "true" ]; then
  if grep -Fxq "[oauth]" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
    then
        # code if found
        echo -e "[WARN] oauth configuration already exist"
    else
        # code if not found
        printf '\n[oauth]\nauthorize_all_scopes = true\nallowed_scopes = ["^(patient|user|system)/.*", "^OH_.*", "fhirUser", "launch", "launch/patient", "launch/encounter", "offline_access"]\n' | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
        echo -e "[INFO] Added [oauth] configuration"
    fi

  if grep -Fxq "[oauth.endpoints.v2]" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] oauth.endpoints.v2 configuration already exist"
  else
      # code if not found
      echo -e "\n[oauth.endpoints.v2]\noidc_consent_page=\"https://\$ref{server.hostname}:\${carbon.management.port}/open-healthcare/consent\""  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "[oauth.grant_type.authorization_code]" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] oauth.grant_type.authorization_code configuration already exist"
  else
      # code if not found
      echo -e "\n[oauth.grant_type.authorization_code]\ngrant_handler = \"org.wso2.healthcare.is.tokenmgt.handlers.HealthcareAuthorizationCodeGrantHandler\""  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fq "context=\"(.*)/scim2/Me\"" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] resource.access_control for scim2/Me already exist"
  else
      # code if not found
      echo -e "\n[[resource.access_control]]\ncontext=\"(.*)/scim2/Me\"\nsecure=true\nhttp_method=\"GET\"\ncross_tenant=true\npermissions=[]\nscopes=[]"  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  J2_FILE="${WSO2_OH_IS_HOME}/repository/resources/conf/templates/repository/conf/identity/resource-access-control-v2.xml.j2"
  if grep -Fq 'context="(.*)/open-healthcare(.*)"' "${J2_FILE}"
  then
      echo -e "[WARN] resource-access-control-v2.xml.j2 already patched for consent webapp"
  else
      sed -i.bak 's|<Resource context="(.*)/console(.*)" secured="false" http-method="all"/>|<Resource context="(.*)/console(.*)" secured="false" http-method="all"/>\n        <Resource context="(.*)/open-healthcare(.*)" secured="false" http-method="all"/>|' "${J2_FILE}"
      echo -e "[INFO] Patched resource-access-control-v2.xml.j2 for consent webapp"
  fi

  if grep -Fq "context=\"(.*)/oauth2/introspect(.*)\"" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      echo -e "[WARN] resource.access_control for oauth2/introspect already exist"
  else
      echo -e "\n[[resource.access_control]]\ncontext=\"(.*)/oauth2/introspect(.*)\"\nhttp_method=\"all\"\nsecure=true\nallowed_auth_handlers=\"BasicClientAuthentication\""  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
      echo -e "[INFO] Added resource.access_control for oauth2/introspect"
  fi

  if grep -Fq "name = \"org.wso2.is.notification.ApimOauthEventInterceptor\"" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] token_revocation event_listener configuration already exist"
  else
      # code if not found
      echo -e "\n[[event_listener]]\nid = \"token_revocation\"\ntype = \"org.wso2.carbon.identity.core.handler.AbstractIdentityHandler\"\nname = \"org.wso2.is.notification.ApimOauthEventInterceptor\"\norder = 1\n\n[event_listener.properties]\nnotification_endpoint = \"https://localhost:9443/internal/data/v1/notify\"\nusername = \"\${admin.username}\"\npassword = \"\${admin.password}\"\n'header.X-WSO2-KEY-MANAGER' = \"WSO2-IS\""  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
  fi

  if grep -Fxq "[role_mgt]" "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml
  then
      # code if found
      echo -e "[WARN] role_mgt configuration already exist"
  else
      # code if not found
      echo -e "\n[role_mgt]\nallow_system_prefix_for_role = true"  | tee -a "${WSO2_OH_IS_HOME}"/repository/conf/deployment.toml >/dev/null
  fi
fi

echo -e "[INFO] WSO2 Healthcare IS Accelerator is successfully applied"

echo -e "$(date)" - "$USER" - "${WSO2_OH_ACCELERATOR_VERSION}" | tee -a "${WSO2_OH_ACCELERATOR_AUDIT}"/merge_audit.log >/dev/null

echo -e "[INFO] Done"
