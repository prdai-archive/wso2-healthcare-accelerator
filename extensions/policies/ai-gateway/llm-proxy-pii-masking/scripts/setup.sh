#!/usr/bin/env bash
# Provision the WSO2 API Platform AI Gateway + AI Workspace, end to end:
# download tooling and distributions, build the custom gateway image
# (with the pii-masking-openmed Python policy), start the compose stack,
# connect the gateway to the control plane, and deploy the OpenAI
# provider. Safe to re-run. See the main() at the bottom for the flow.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

GW_VERSION="1.2.0-alpha2"
WS_VERSION="1.0.0-alpha2"
AP_VERSION="0.9.0"
AP="${AP:-$HOME/.local/bin/ap}"
GW_DIR="$REPO_ROOT/gateway"
DIST_DIR="$GW_DIR/dist"
WS_DIR="$REPO_ROOT/workspace/dist"
MGMT="http://localhost:9090/api/management/v1"
PLATFORM="https://localhost:9243"
RUNTIME_IMAGE="ghcr.io/wso2/api-platform/pii-gateway-gateway-runtime:$GW_VERSION"
COMPOSE=(docker compose -f "$DIST_DIR/docker-compose.yaml" -f "$REPO_ROOT/docker-compose.yaml" --project-directory "$DIST_DIR")

# os_arch — echo the "<os>-<arch>" pair used in ap CLI release asset names
os_arch() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    arm64 | aarch64) arch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  echo "$os-$arch"
}

# download_dist <url> <target-dir> — fetch a release zip and unpack its
# single top-level directory into the target
download_dist() {
  local url=$1 target=$2 tmp
  tmp=$(mktemp -d)
  curl -fsSLo "$tmp/dist.zip" "$url" || die "failed to download $url"
  unzip -oq "$tmp/dist.zip" -d "$tmp"
  mkdir -p "$target"
  cp -r "$tmp"/*/. "$target/"
  rm -rf "$tmp"
}

# wait_for <name> <curl-args...> — poll a health URL for up to a minute
wait_for() {
  local name=$1
  shift
  for _ in $(seq 1 30); do
    curl -sf "$@" >/dev/null && return 0
    sleep 2
  done
  die "$name did not become healthy"
}

ensure_ap_cli() {
  step "Ensuring ap CLI $AP_VERSION is installed"
  if command -v ap >/dev/null; then
    AP=ap
    info "found $(ap version 2>/dev/null | head -1 || echo ap)"
  elif [[ -x "$AP" ]]; then
    info "found at $AP"
  else
    info "downloading ap CLI $AP_VERSION"
    local tmp platform
    tmp=$(mktemp -d)
    platform=$(os_arch)
    curl -fsSLo "$tmp/ap.zip" "https://github.com/wso2/api-platform/releases/download/ap/v$AP_VERSION/ap-$platform-v$AP_VERSION.zip" ||
      die "failed to download ap CLI $AP_VERSION for $platform"
    unzip -oq "$tmp/ap.zip" -d "$tmp"
    mkdir -p "$(dirname "$AP")"
    mv "$tmp/ap-$platform-v$AP_VERSION/ap" "$AP" 2>/dev/null || mv "$tmp/ap" "$AP"
    chmod +x "$AP"
    rm -rf "$tmp"
    info "installed to $AP"
  fi
}

ensure_gateway_dist() {
  step "Ensuring gateway distribution $GW_VERSION is present"
  if [[ -f "$DIST_DIR/docker-compose.yaml" ]]; then
    info "already extracted at gateway/dist"
  else
    info "downloading distribution"
    download_dist "https://github.com/wso2/api-platform/releases/download/ai-gateway/v$GW_VERSION/wso2apip-ai-gateway-$GW_VERSION.zip" "$DIST_DIR"
    info "extracted to gateway/dist"
  fi
}

ensure_workspace_dist() {
  step "Ensuring AI Workspace distribution $WS_VERSION is present"
  if [[ -f "$WS_DIR/docker-compose.yaml" ]]; then
    info "already extracted at workspace/dist"
  else
    info "downloading distribution"
    download_dist "https://github.com/wso2/api-platform/releases/download/portals/ai-workspace/v$WS_VERSION/wso2apip-ai-workspace-$WS_VERSION.zip" "$WS_DIR"
    info "extracted to workspace/dist"
  fi
  if [[ ! -f "$WS_DIR/api-platform.env" ]]; then
    info "generating Workspace secrets and certificates (admin/admin)"
    (cd "$WS_DIR" && ADMIN_USERNAME=admin ADMIN_PASSWORD=admin ./scripts/setup.sh)
  fi
}

build_gateway_image() {
  step "Building custom gateway image with the pii-masking-openmed policy"
  if docker image inspect "$RUNTIME_IMAGE" >/dev/null 2>&1 && [[ "${REBUILD:-}" != "1" ]]; then
    info "image already built (REBUILD=1 to force)"
    return
  fi
  # Snap-confined docker CLIs cannot read top-level hidden dirs like
  # ~/.wso2ap, so relocate the ap workspace into the repo
  mkdir -p "$GW_DIR/.apwork"
  if ! (cd "$GW_DIR" && HOME="$GW_DIR/.apwork" "$AP" gateway image build --name pii-gateway); then
    die "image build failed — on rootful Docker the ap builder needs root: re-run as 'sudo -E ./scripts/setup.sh'"
  fi
  info "built pii-gateway images"
}

start_control_plane() {
  step "Starting the control plane"
  "${COMPOSE[@]}" up -d platform-api ai-workspace
  wait_for "Platform API" -k "$PLATFORM/health"
  info "control plane is healthy"
}

# Sets AUTH to a bearer-token header for the Platform API
platform_login() {
  local token
  token=$(curl -sk -X POST "$PLATFORM/api/portal/v0.9/auth/login" \
    -d 'username=admin&password=admin' | jq -r '.token // empty')
  [[ -n "$token" ]] || die "could not log in to the Platform API"
  AUTH=(-H "Authorization: Bearer $token")
}

register_gateway() {
  step "Registering the gateway with the control plane"
  platform_login

  if curl -sk "${AUTH[@]}" "$PLATFORM/api/v0.9/gateways/pii-gateway" | jq -e '.id' >/dev/null 2>&1; then
    info "gateway pii-gateway already registered"
  else
    curl -sk "${AUTH[@]}" -X POST "$PLATFORM/api/v0.9/gateways" -H 'Content-Type: application/json' -d '{
      "id": "pii-gateway",
      "displayName": "PII Gateway",
      "description": "Local AI gateway with OpenMed PII masking",
      "endpoints": ["https://localhost:8443"],
      "isCritical": false,
      "functionalityType": "ai",
      "vhost": "localhost"
    }' | jq -e '.id' >/dev/null || die "gateway registration failed"
    info "registered gateway pii-gateway"
  fi

  # Always mint a fresh token: a stale one makes the controller exit at boot
  local tid reg_token
  for tid in $(curl -sk "${AUTH[@]}" "$PLATFORM/api/v0.9/gateways/pii-gateway/tokens" | jq -r '.list[]?.id // empty'); do
    curl -sk "${AUTH[@]}" -X DELETE "$PLATFORM/api/v0.9/gateways/pii-gateway/tokens/$tid" >/dev/null
  done
  reg_token=$(curl -sk "${AUTH[@]}" -X POST "$PLATFORM/api/v0.9/gateways/pii-gateway/tokens" | jq -r '.token // empty')
  [[ -n "$reg_token" ]] || die "registration token generation failed"
  cat > "$DIST_DIR/.env" <<EOF
GATEWAY_CONTROLPLANE_HOST=platform-api:9243
GATEWAY_REGISTRATION_TOKEN=$reg_token
EOF
  info "wrote gateway/dist/.env with a fresh registration token"
}

start_gateway() {
  step "Starting the gateway"
  "${COMPOSE[@]}" up -d
  # The runtime runs as the wso2 user but the hf-cache volume is created
  # root-owned; hand it over so the model download can be cached
  "${COMPOSE[@]}" exec -u 0 gateway-runtime chown -R wso2 /data/hf-cache
  wait_for "gateway controller" http://localhost:9094/health

  local active
  for _ in $(seq 1 30); do
    active=$(curl -sk "${AUTH[@]}" "$PLATFORM/api/v0.9/gateways/pii-gateway" | jq -r '.isActive')
    [[ "$active" == "true" ]] && break
    sleep 2
  done
  if [[ "${active:-false}" == "true" ]]; then
    info "gateway is connected (Active in the UI)"
  else
    info "gateway not showing Active yet — check 'make gateway-logs'"
  fi
}

deploy_provider() {
  step "Deploying the OpenAI LLM provider (with PII masking policy)"
  local manifest response code verb url
  manifest=$(OPENAI_API_KEY="$OPENAI_API_KEY" \
    envsubst '$OPENAI_API_KEY' < "$GW_DIR/manifests/llm-provider.yaml")

  verb=POST url="$MGMT/llm-providers"
  if curl -s -u admin:admin "$MGMT/llm-providers" | jq -r '.providers[]?.metadata.name // empty' | grep -qx openai-provider; then
    verb=PUT url="$MGMT/llm-providers/openai-provider"
  fi
  response=$(curl -s -w '\n%{http_code}' -u admin:admin -X "$verb" "$url" \
    -H 'Content-Type: application/yaml' --data-binary "$manifest")
  code=$(tail -1 <<<"$response")
  [[ "$code" =~ ^2 ]] || die "provider deployment failed (HTTP $code): $(sed '$d' <<<"$response")"
  info "openai-provider deployed"
}

# Poke the gateway with tiny chat requests until the OpenMed model is loaded (first boot downloads it, ~2 min)
warm_up_model() {
  step "Waiting for the OpenMed model to warm up"
  local code
  for _ in $(seq 1 60); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 40 -X POST \
      "https://localhost:8443/openai/latest/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"gpt-5-nano","messages":[{"role":"user","content":"ping"}],"max_completion_tokens":1}')
    if [[ "$code" == "200" ]]; then
      info "model is warm — gateway is ready for traffic"
      return
    fi
    sleep 5
  done
  info "model still warming up — the first request may be slow (check 'make logs')"
}

write_test_env() {
  cat > "$REPO_ROOT/test/.env" <<EOF
OPENAI_API_KEY=not-needed
OPENAI_BASE_URL=https://localhost:8443/openai/latest
EOF
  info "wrote test/.env"
}

# When run under sudo, hand artifacts back to the invoking user
fix_ownership() {
  [[ -n "${SUDO_USER:-}" ]] && chown -R "$SUDO_USER" "$REPO_ROOT/test/.env" "$DIST_DIR" "$WS_DIR" 2>/dev/null || true
}

main() {
  require_tools
  require_env
  trap fix_ownership EXIT

  ensure_ap_cli
  ensure_gateway_dist
  ensure_workspace_dist
  build_gateway_image
  start_control_plane
  register_gateway
  start_gateway
  deploy_provider
  warm_up_model
  write_test_env

  step "Done"
  info "UI: https://localhost:5380 (admin/admin)"
  info "try it: cd test && go run .   (then 'make logs' to watch the masking in the gateway runtime)"
}

main "$@"
