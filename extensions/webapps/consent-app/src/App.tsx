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

import { useEffect, useRef, useState } from 'react';
import { Routes, Route, Navigate, useSearchParams, useNavigate, useLocation } from 'react-router-dom';
import { Box, CircularProgress, Typography } from '@wso2/oxygen-ui';
import { getConsentData, submitConsent } from './api';
import ScopeConsentPage from './ScopeConsentPage';
import PurposeConsentPage from './PurposeConsentPage';
import PatientPickerPage from './PatientPickerPage';
import type { ConsentData, ConsentExpiryOption, ScopeConsentData, PurposeConsentData, RedirectConsentData } from './types';

const IDP_AUTHORIZE_URL = window.config?.IDP_AUTHORIZE_URL || '';

function submitIdpForm(
  sessionDataKeyConsent: string,
  consent: 'approve' | 'deny',
  options?: { claims?: Array<{ id: string }>; scopes?: string[] },
) {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = IDP_AUTHORIZE_URL;
  const add = (name: string, value: string) => {
    const el = document.createElement('input');
    el.type = 'hidden';
    el.name = name;
    el.value = value;
    form.appendChild(el);
  };
  add('sessionDataKeyConsent', sessionDataKeyConsent);
  add('consent', consent);
  add('hasApprovedAlways', 'false');
  if (consent === 'approve') {
    add('user_claims_consent', 'true');
    for (const claim of options?.claims ?? []) {
      add(`consent_${claim.id}`, 'approved');
    }
    if (options?.scopes?.length) {
      add('scope', options.scopes.join(' '));
    }
  }
  document.body.appendChild(form);
  form.submit();
}

function parseMandatoryClaims(raw: string): Array<{ id: string }> {
  if (!raw) return [];
  return raw.split(',').map((c) => {
    const idx = c.indexOf('_');
    return idx >= 0 ? { id: c.substring(0, idx) } : { id: c };
  });
}

function AutoApproveScopePage({ sessionDataKeyConsent }: { sessionDataKeyConsent: string }) {
  const submitted = useRef(false);
  useEffect(() => {
    if (submitted.current) return;
    submitted.current = true;
    submitIdpForm(sessionDataKeyConsent, 'approve');
  }, [sessionDataKeyConsent]);

  return (
    <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <CircularProgress size={36} />
    </Box>
  );
}

function ConsentRoute() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const sessionDataKeyConsent = searchParams.get('sessionDataKeyConsent') ?? '';
  const spId = searchParams.get('spId') ?? '';

  const [data, setData] = useState<ConsentData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!sessionDataKeyConsent) {
      setError('Missing sessionDataKeyConsent parameter.');
      setLoading(false);
      return;
    }
    getConsentData(sessionDataKeyConsent, spId)
      .then((d) => {
        if (d.flow === 'redirect') {
          window.location.replace((d as RedirectConsentData).redirectUrl);
          return;
        }
        setData(d);
      })
      .catch((err: unknown) => {
        console.error('Failed to load consent data', err);
        setError('Failed to load consent data. Please try again.');
      })
      .finally(() => setLoading(false));
  }, [sessionDataKeyConsent, spId]);

  if (loading) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <CircularProgress size={36} />
      </Box>
    );
  }

  if (error || !data) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', p: 3 }}>
        <Typography sx={{ fontSize: '3rem', mb: 2, lineHeight: 1 }}>😔</Typography>
        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
          Oops, something went wrong.
        </Typography>
        <Typography variant="body2" color="text.secondary">
          {error ?? 'Please try again later or contact support.'}
        </Typography>
      </Box>
    );
  }

  if (data.flow === 'scope') {
    const scopeData = data as ScopeConsentData;
    if (scopeData.scopes.length === 0) {
      return <AutoApproveScopePage sessionDataKeyConsent={sessionDataKeyConsent} />;
    }

    if (scopeData.isPractitioner && (scopeData.patients?.length ?? 0) > 0) {
      return (
        <ScopeConsentPage
          data={scopeData}
          onApprove={(scopes, expiryOption) =>
            navigate(
              `/select-patient?sessionDataKeyConsent=${encodeURIComponent(sessionDataKeyConsent)}&spId=${encodeURIComponent(spId)}`,
              { state: { approvedScopes: scopes, scopeData, consentExpiryOption: expiryOption } },
            )
          }
        />
      );
    }

    return <ScopeConsentPage data={scopeData} />;
  }

  return <PurposeConsentPage data={data as PurposeConsentData} />;
}

interface PatientPickerState {
  approvedScopes: string[];
  scopeData: ScopeConsentData;
  consentExpiryOption: ConsentExpiryOption;
}

function PatientPickerRoute() {
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const sessionDataKeyConsent = searchParams.get('sessionDataKeyConsent') ?? '';
  const spId = searchParams.get('spId') ?? '';

  const state = location.state as PatientPickerState | null;
  if (!state?.approvedScopes || !state?.scopeData) {
    return <Navigate to={`/consent?${searchParams.toString()}`} replace />;
  }

  const { approvedScopes, scopeData, consentExpiryOption } = state;

  return (
    <PatientPickerPage
      patients={scopeData.patients ?? []}
      user={scopeData.user}
      onProceed={async (patient) => {
        const fhirUser = patient.fhirUser ?? '';
        const patientId = fhirUser.startsWith('Patient/') ? fhirUser.slice('Patient/'.length) : fhirUser;
        const patientScope = patientId ? `OH_patient/${patientId}` : null;
        const finalScopes = patientScope ? [...approvedScopes, patientScope] : [...approvedScopes];
        const claims = parseMandatoryClaims(scopeData.mandatoryClaims);
        await submitConsent({
          consentToken: scopeData.consentToken,
          sessionDataKeyConsent,
          spId,
          approved: true,
          approvedScopes: finalScopes,
          hiddenScopes: scopeData.hiddenScopes,
          consentExpiryOption,
          ...(scopeData.existingConsentId ? { existingConsentId: scopeData.existingConsentId } : {}),
        });
        submitIdpForm(sessionDataKeyConsent, 'approve', {
          claims,
          scopes: [...finalScopes, ...scopeData.hiddenScopes],
        });
      }}
      onCancel={() => submitIdpForm(sessionDataKeyConsent, 'deny')}
    />
  );
}

function RedirectToConsentPage() {
  const [searchParams] = useSearchParams();
  return <Navigate to={`/consent?${searchParams.toString()}`} replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/consent" element={<ConsentRoute />} />
      <Route path="/select-patient" element={<PatientPickerRoute />} />
      <Route path="*" element={<RedirectToConsentPage />} />
    </Routes>
  );
}
