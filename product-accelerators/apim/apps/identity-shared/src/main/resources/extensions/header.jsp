
<%--
    ~ Copyright (c) 2025, WSO2 LLC. (https://www.wso2.com).
    ~
    ~  WSO2 LLC. licenses this file to you under the Apache License,
    ~ Version 2.0 (the "License"); you may not use this file except
    ~ in compliance with the License.
    ~ You may obtain a copy of the License at
    ~
    ~    http://www.apache.org/licenses/LICENSE-2.0
    ~
    ~ Unless required by applicable law or agreed to in writing,
    ~ software distributed under the License is distributed on an
    ~ "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
    ~ KIND, either express or implied.  See the License for the
    ~ specific language governing permissions and limitations
    ~ under the License.
--%>

<!-- localize.jsp MUST already be included in the calling script -->

<%@ page import="java.io.File" %>
<%@ page import="java.io.FileReader" %>
<%@ page import="org.json.simple.parser.JSONParser"%>
<%@ page import="org.json.simple.JSONObject"%>
<%@ page import="java.net.URI"%>
<%@ page import="org.apache.commons.lang.StringUtils"%>
<%@ page import="org.wso2.healthcare.apim.core.api.server.DeploymentConfigAPI" %>
<%@ page import="org.owasp.encoder.Encode" %>

<%@ page import="org.wso2.carbon.identity.application.authentication.endpoint.util.AuthenticationEndpointUtil" %>
<%@ page import="org.wso2.carbon.identity.mgt.endpoint.util.IdentityManagementEndpointUtil" %>

<%
  String tenant = request.getParameter("tenantDomain");
  if (tenant == null) {
        tenant = request.getParameter("TenantDomain");
    }
  if (tenant == null) {
      String cb = request.getParameter("callback");
      cb = StringUtils.replace(cb, " ", "");
      if (cb != null) {
          URI uri = new URI(cb);
          String decodedValue = uri.getQuery();
          String[] params = decodedValue.split("&");
          for (String param : params) {
              if (param.startsWith("tenantDomain=") || param.startsWith("TenantDomain=")) {
                  String[] keyVal = param.split("=");
                  tenant = keyVal[1];
              }
          }
      }
  }

  String headerTitle = DeploymentConfigAPI.getOHDeploymentName();
  String mainColor = DeploymentConfigAPI.getWebappMainColor();
  String pageTitle = DeploymentConfigAPI.getWebappTitle();
  String footerText = DeploymentConfigAPI.getWebappFooter();
  String faviconSrc = DeploymentConfigAPI.getWebappFavicon();
  String additionalFooterElement = DeploymentConfigAPI.getWebappFooterSecondaryHTML();
  String logoSrc = "extensions/customAssets/wso2-logo.svg";
  String logoHeight = "50";
  String logoWidth = "60";
  String logoAltText = "";
  File customCSSFile = null;
  FileReader fr = null;
  String customCSS = "";
  String tenantThemeDirectoryName = "";
  boolean showCookiePolicy = false;
  boolean showPrivacyPolicy = false;
  String cookiePolicyText = null;
  String privacyPolicyText = null;

  if (tenant != null) {
      String current = new File(".").getCanonicalPath();
      String tenantConfLocation = "/repository/deployment/server/jaggeryapps/devportal/site/public/tenant_themes/";
      tenantThemeDirectoryName = tenant;
      String tenantThemeFile =  current + tenantConfLocation + tenantThemeDirectoryName + "/login/" + "loginTheme.json";
      customCSS = current + tenantConfLocation + tenantThemeDirectoryName + "/login/css/" + "loginTheme.css";
      File directory = new File(current + tenantConfLocation + tenantThemeDirectoryName);
      if (directory != null && directory.exists() && directory.isDirectory()) {
          File themeFile = new File(tenantThemeFile);
          customCSSFile = new File(customCSS);
          if (themeFile != null && themeFile.exists() && themeFile.isFile()) {
            try {
              fr = new FileReader(themeFile);
              JSONParser parser = new JSONParser();
              Object obj = parser.parse(fr);
              JSONObject jsonObject = (JSONObject) obj;

              pageTitle = (String)jsonObject.get("title") != null ? (String)jsonObject.get("title") : "WSO2 API Manager";

              JSONObject headerThemeObj = (JSONObject)jsonObject.get("header");
              if (headerThemeObj != null) {
                  headerTitle = (String)(headerThemeObj.get("title")) != null ? (String)(headerThemeObj.get("title")) : "API Manager";
              }

              JSONObject footerThemeObj = (JSONObject)jsonObject.get("footer");
              if (footerThemeObj != null) {
                  footerText = (String)(footerThemeObj.get("name"));
              }

              JSONObject faviconThemeObj = (JSONObject)jsonObject.get("favicon");
              if (faviconThemeObj != null) {
                  String fileName = (String)(faviconThemeObj.get("src"));
                  if (!StringUtils.isEmpty(fileName)) {
                      faviconSrc = "/devportal/site/public/tenant_themes/" + tenantThemeDirectoryName + "/login/images/"
                                + fileName;
                  }
              }

              JSONObject logoThemeObj = (JSONObject)jsonObject.get("logo");
              if (logoThemeObj != null) {
                  String fileName = (String)(logoThemeObj.get("src"));
                  if (!StringUtils.isEmpty(fileName)) {
                      logoSrc = "/devportal/site/public/tenant_themes/" + tenantThemeDirectoryName + "/login/images/"
                                + fileName;
                  }
                  logoHeight = (String)(logoThemeObj.get("height")) != null ? (String)(logoThemeObj.get("height")) : logoHeight;
                  logoWidth = (String)(logoThemeObj.get("width")) != null ? (String)(logoThemeObj.get("width")) : logoWidth;
                  logoAltText = (String)(logoThemeObj.get("alt"));
              }

              JSONObject cookiePolicyThemeObj = (JSONObject)jsonObject.get("cookie-policy");
              if (cookiePolicyThemeObj != null) {
                  showCookiePolicy = (Boolean)(cookiePolicyThemeObj.get("visible"));
                  cookiePolicyText = (String)cookiePolicyThemeObj.get("text");
              }

              JSONObject privacyPolicyThemeObj = (JSONObject)jsonObject.get("privacy-policy");
              if (privacyPolicyThemeObj != null) {
                  showPrivacyPolicy = (Boolean)(privacyPolicyThemeObj.get("visible"));
                  privacyPolicyText = (String)privacyPolicyThemeObj.get("text");
              }
            } finally {
                if (fr != null) {
                    fr.close();
                }
            }
          }
      }
  }
  request.setAttribute("headerTitle", headerTitle);
  request.setAttribute("pageTitle", pageTitle);
  request.setAttribute("footerText", footerText);
  request.setAttribute("faviconSrc", faviconSrc);
  request.setAttribute("showCookiePolicy", showCookiePolicy);
  request.setAttribute("showPrivacyPolicy", showPrivacyPolicy);
  request.setAttribute("cookiePolicyText", cookiePolicyText);
  request.setAttribute("privacyPolicyText", privacyPolicyText);
  request.setAttribute("logoSrc", logoSrc);
  request.setAttribute("logoHeight", logoHeight);
  request.setAttribute("logoWidth", logoWidth);
  request.setAttribute("logoAltText", logoAltText);

  if (customCSSFile != null && customCSSFile.exists() && customCSSFile.isFile()) {
  String cssRelativePath = "/devportal/site/public/tenant_themes/" + tenantThemeDirectoryName + "/login/css/" + "loginTheme.css";
      request.setAttribute("customCSS", cssRelativePath);
  } else {
      request.setAttribute("customCSS", "");
  }

%>

<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<link rel="icon" href="libs/themes/default/assets/images/favicon.ico" type="image/x-icon"/>
<link href="libs/themes/default/theme.70534561.min.css" rel="stylesheet">

<title><%=request.getAttribute("pageTitle")%></title>
<style>
    input:focus + label {
        color: #342382;
    }
    input:hover{
        border: solid 1px #342382; 
    }
    .round input[type="checkbox"]:checked + label {
        background-color: #342382;
        border-color: #342382;
    }
    .ui.primary.large.button{       
        background-color:#342382;
    }
    .ui.primary.button{       
        background-color:#342382;
    }
    .ui.primary.large.button:hover{
        background-color: #342382;
    }
    /* unvisited link */
    a:link {
        color: #342382;
        text-decoration: underline;
    }
    /* visited link */
    a:visited {
        color: #342382;
        text-decoration: underline;
    }
    /* mouse over link */
    a:hover {
        color: #342382;
        filter: brightness(90%);
        text-decoration: underline;
    }
    /* selected link */
    a:active {
        color: #342382;
        text-decoration: underline;
    }
    .ui.visible.negative.message.header {
        color: #342382;
    }
    .ui.primary.button.cancel{
        background-color: #342382;
    }
    .ui.primary.button.cancel:hover{
        background-color: #342382;
    }
    .grantRadioButton {
        border: 2px solid #342382;
    }
    .grantCancelButton{
        color: #342382;
    }
    .grantCancelButton:hover {
        color: #342382;
    }
    main .ui.segment.toc ul.ui.list.nav > li:hover a {
        color: #342382;
        text-decoration: none;
    }
    main .ui.segment.toc ul.ui.list.nav > li:hover:before {
        color:  #342382;
    }
</style>

<%
  String cssPath = request.getAttribute("customCSS") + "";
  if (!StringUtils.isEmpty(cssPath)) {
%>
      <link href="<%=Encode.forHtmlAttribute(cssPath)%>" rel="stylesheet" type="text/css">
<%	}
%>

<script src="libs/jquery_3.6.0/jquery-3.6.0.min.js"></script>
