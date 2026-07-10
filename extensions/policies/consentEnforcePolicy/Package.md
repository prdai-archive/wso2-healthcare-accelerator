# Consent Enforce Policy

## Overview

Enforces consent validation for API requests. Extracts the `consent_id` from the Bearer access token or X-JWT-Assertion header and the resource path from the mediation context to validate consent before allowing the request to proceed.
