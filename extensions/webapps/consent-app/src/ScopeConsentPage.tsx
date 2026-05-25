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

import { useState } from 'react';
import { Box, Button, Checkbox, CircularProgress, FormControlLabel, Paper, Typography } from '@wso2/oxygen-ui';
import Alert from '@mui/material/Alert';
import Snackbar from '@mui/material/Snackbar';
import { submitConsent } from './api';
import type { ConsentExpiryOption, ScopeConsentData } from './types';

const IDP_AUTHORIZE_URL = window.config?.IDP_AUTHORIZE_URL || '';

// Validates SMART on FHIR scope format
const SMART_REGEX = /^(patient|user|system)\/(\*|[A-Za-z]+)\.(cruds|(?=[cruds]+$)c?r?u?d?s?)$/;
function isValidSmartScope(s: string): boolean {
  if (/^(patient|user|system)\//.test(s)) return SMART_REGEX.test(s);
  return true;
}

const PERM_LABEL: Record<string, string> = { c: 'Write', r: 'Read', u: 'Update', d: 'Delete', s: 'Search' };

function formatScopeLabel(scope: string): string {
  const match = scope.match(/^(patient|user)\/(\*|[A-Za-z]+)\.([cruds]+)$/);
  if (!match) return scope;

  const [, compartment, resource, perms] = match;
  const resourceLabel = resource === '*' ? 'All Resources' : `/${resource}`;
  const context = compartment === 'patient'
    ? 'on current patient'
    : 'on current user';

  const types = [...new Set(perms.split(''))].map(p => PERM_LABEL[p]).filter(Boolean);
  if (types.length === 0) return scope;

  const accessLabel = types.length === 1
    ? `${types[0]} Access`
    : `${types.slice(0, -1).join(', ')} and ${types[types.length - 1]} Access`;

  return `${accessLabel} to ${resourceLabel} ${context}`;
}

function submitIdpForm(sessionDataKeyConsent: string, consent: 'approve' | 'deny', options?: {
  claims: Array<{ id: string }>;
  scopes?: string[];
}) {
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
    if (options?.scopes && options.scopes.length > 0) {
      add('scope', options.scopes.join(' '));
    }
  }

  document.body.appendChild(form);
  form.submit();
}

function parseMandatoryClaims(raw: string): Array<{ id: string; name: string }> {
  if (!raw) return [];
  return raw.split(',').map((c) => {
    const idx = c.indexOf('_');
    return idx >= 0
      ? { id: c.substring(0, idx), name: c.substring(idx + 1) }
      : { id: c, name: c };
  });
}

interface Props {
  data: ScopeConsentData;
  onApprove?: (selectedScopes: string[], expiryOption: ConsentExpiryOption) => void;
}

export default function ScopeConsentPage({ data, onApprove }: Props) {
  const { sessionDataKeyConsent, spId, user, scopes, hiddenScopes, mandatoryClaims, consentToken } = data;

  const claims = parseMandatoryClaims(mandatoryClaims);

  // Filter out OH_launch/* (already in hiddenScopes from BFF) and invalid SMART scopes
  const selectableScopes = scopes.filter(isValidSmartScope);

  const [submitting, setSubmitting] = useState<'approve' | 'deny' | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [selectedExpiry, setSelectedExpiry] = useState<ConsentExpiryOption>('24h');

  const EXPIRY_OPTIONS: { value: ConsentExpiryOption; label: string }[] = [
    { value: '24h', label: '24 Hours' },
    { value: '3months', label: '3 Months' },
    { value: 'never', label: 'Never' },
  ];

  const selectedScopes = selectableScopes;
  const allChecked = selectableScopes.length > 0;

  const handleApprove = async () => {
    if (onApprove) {
      onApprove(selectedScopes, selectedExpiry);
      return;
    }
    setSubmitting('approve');
    setSubmitError(null);
    try {
      await submitConsent({
        consentToken,
        sessionDataKeyConsent,
        spId,
        approved: true,
        approvedScopes: selectedScopes,
        hiddenScopes,
        consentExpiryOption: selectedExpiry,
        ...(data.existingConsentId ? { existingConsentId: data.existingConsentId } : {}),
      });
      submitIdpForm(sessionDataKeyConsent, 'approve', {
        claims,
        scopes: [...selectedScopes, ...hiddenScopes],
      });
    } catch (err) {
      console.error('Failed to submit consent', err);
      setSubmitError('Failed to submit consent. Please try again.');
      setSubmitting(null);
    }
  };

  const handleDeny = () => {
    setSubmitting('deny');
    submitIdpForm(sessionDataKeyConsent, 'deny');
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        bgcolor: 'background.default',
        p: 2,
      }}
    >
      <Box sx={{ mb: 3 }}>
        <img
          src="https://wso2.cachefly.net/wso2/sites/all/image_resources/logos/WSO2-Logo-Black.webp"
          alt="WSO2"
          style={{ height: 32 }}
        />
      </Box>

      <Paper sx={{ p: 4, maxWidth: 480, width: '100%' }}>
        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1, textAlign: 'center' }}>
          Authorize Access
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 3, textAlign: 'center' }}>
          Signed in as {user.displayName}{user.email ? ` (${user.email})` : ''}
        </Typography>

        {/* Mandatory claims */}
        {claims.length > 0 && (
          <Box sx={{ mb: 3 }}>
            <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'text.secondary', display: 'block', mb: 1 }}>
              Required User Attributes
            </Typography>
            <Box sx={{ bgcolor: 'background.default', borderRadius: 2, p: 1.5 }}>
              {claims.map((c) => (
                <Box key={c.id} sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.5 }}>
                  <Checkbox checked disabled size="small" sx={{ p: '2px 8px 2px 0' }} />
                  <Typography variant="body2" color="text.secondary">{c.name}</Typography>
                </Box>
              ))}
            </Box>
          </Box>
        )}

        {/* Scope list */}
        <Box sx={{ mb: 3 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'text.secondary', display: 'block', mb: 1 }}>
            Requested Permissions
          </Typography>

          <Box sx={{ bgcolor: 'background.default', borderRadius: 2, p: 1.5, minHeight: 64 }}>
            {selectableScopes.length === 0 && (
              <Typography variant="body2" color="text.secondary" sx={{ py: 1, textAlign: 'center' }}>
                No permissions requested.
              </Typography>
            )}
            {selectableScopes.map((scope) => (
              <FormControlLabel
                key={scope}
                control={
                  <Checkbox
                    checked
                    disabled
                    size="small"
                    sx={{ p: '2px 8px 2px 4px' }}
                  />
                }
                label={<Typography variant="body2">{formatScopeLabel(scope)}</Typography>}
                sx={{ m: 0, display: 'flex', py: 0.25 }}
              />
            ))}
          </Box>

          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
            {selectedScopes.length} of {selectableScopes.length} selected
          </Typography>
        </Box>

        <Box sx={{ mb: 3 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'text.secondary', display: 'block', mb: 1 }}>
            Consent Expiry
          </Typography>
          <Box sx={{ bgcolor: 'background.default', borderRadius: 2, p: 1.5, display: 'flex', gap: 1 }}>
            {EXPIRY_OPTIONS.map((opt) => (
              <FormControlLabel
                key={opt.value}
                control={
                  <Checkbox
                    checked={selectedExpiry === opt.value}
                    onChange={() => setSelectedExpiry(opt.value)}
                    size="small"
                    sx={{ p: '2px 8px 2px 4px' }}
                  />
                }
                label={<Typography variant="body2">{opt.label}</Typography>}
                sx={{ m: 0, flex: 1 }}
              />
            ))}
          </Box>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
            By clicking 'Approve', you grant the above permissions.
          </Typography>
        </Box>

        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
          <Button
            variant="contained"
            fullWidth
            onClick={() => void handleApprove()}
            disabled={submitting !== null || !allChecked}
            sx={{ borderRadius: '50px', textTransform: 'none', fontWeight: 600, fontSize: '0.95rem', py: 1.25 }}
          >
            {submitting === 'approve' ? <CircularProgress size={20} sx={{ color: 'inherit' }} /> : 'Approve'}
          </Button>
          <Button
            variant="outlined"
            fullWidth
            onClick={handleDeny}
            disabled={submitting !== null}
            sx={{ borderRadius: '50px', textTransform: 'none', fontWeight: 600, fontSize: '0.95rem', py: 1.25, borderColor: 'divider', color: 'text.secondary', '&:hover': { bgcolor: 'action.hover', borderColor: 'divider' } }}
          >
            {submitting === 'deny' ? <CircularProgress size={20} sx={{ color: 'inherit' }} /> : 'Deny'}
          </Button>
        </Box>
      </Paper>

      <Snackbar
        open={!!submitError}
        autoHideDuration={6000}
        onClose={() => setSubmitError(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert onClose={() => setSubmitError(null)} severity="error" sx={{ width: '100%' }}>
          {submitError}
        </Alert>
      </Snackbar>
    </Box>
  );
}
