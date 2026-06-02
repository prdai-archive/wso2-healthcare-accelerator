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

import { createRoot } from 'react-dom/client';

declare global {
  interface Window {
    config?: {
      CONSENT_BFF_URL: string;
      IDP_AUTHORIZE_URL: string;
    };
  }
}
import { OxygenUIThemeProvider, AcrylicOrangeTheme } from '@wso2/oxygen-ui';
import { BrowserRouter } from 'react-router-dom';
import './index.css';
import App from './App.tsx';

// Strip dark color scheme so MUI never applies dark-mode CSS variable overrides.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const baseTheme = AcrylicOrangeTheme as any;
const lightOnlyTheme = { ...baseTheme, colorSchemes: { light: baseTheme.colorSchemes?.light } };

// StrictMode intentionally omitted: double-invocation of effects would cause two
// calls to the IDP OauthConsentKey API, which invalidates the session on first use.
createRoot(document.getElementById('root')!).render(
  <OxygenUIThemeProvider theme={lightOnlyTheme}>
    <BrowserRouter basename="/open-healthcare">
      <App />
    </BrowserRouter>
  </OxygenUIThemeProvider>,
);
