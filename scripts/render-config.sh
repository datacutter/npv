#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source .env
XRAY_IMAGE=${XRAY_IMAGE:-ghcr.io/xtls/xray-core:26.6.1}
XHTTP_PATH=${XHTTP_PATH:-/assets}
XHTTP_MODE=${XHTTP_MODE:-auto}

validate_xray_config() {
    local config_name=${1:-config.json}

    if [[ "$XRAY_IMAGE" == ghcr.io/xtls/xray-core:* ]]; then
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" run -test -config "/etc/xray/${config_name}"
    else
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" xray run -test -config "/etc/xray/${config_name}"
    fi
}

TEMPLATE="xray/config.template.json"
TARGET="xray/config.json"
TMP_TARGET=$(mktemp xray/config.XXXXXX.json)
USERS_FILE="data/users.json"

cleanup() {
    if [ -n "${TMP_TARGET:-}" ] && [ -f "$TMP_TARGET" ]; then
        rm -f "$TMP_TARGET"
    fi
}
trap cleanup EXIT

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: $TEMPLATE not found!"
    exit 1
fi

if [ ! -f "$USERS_FILE" ]; then
    echo "[]" > "$USERS_FILE"
fi

if [ -z "${REALITY_DEST:-}" ] || [ -z "${REALITY_SERVER_NAME:-}" ]; then
    echo "Error: REALITY_DEST and REALITY_SERVER_NAME must be set in .env."
    exit 1
fi

if [ -z "${XRAY_PRIVATE_KEY:-}" ] || [ -z "${XRAY_SHORT_ID:-}" ]; then
    echo "Error: XRAY_PRIVATE_KEY and XRAY_SHORT_ID must be set. Run 'make regenerate-secrets'."
    exit 1
fi

if [[ "$XHTTP_PATH" != /* ]]; then
    echo "Error: XHTTP_PATH must start with '/'. Current value: $XHTTP_PATH"
    exit 1
fi

if [ "${SKIP_REALITY_TARGET_CHECK:-false}" != "true" ]; then
    bash scripts/check-reality-target.sh --warn-only "$REALITY_DEST" "$REALITY_SERVER_NAME"
fi

# Extract active clients and transform them for Xray config format.
# Vision flow is valid for RAW/TCP + REALITY. XHTTP clients intentionally
# omit flow to avoid advertising an incompatible transport/flow combination.
ACTIVE_TCP_CLIENTS=$(jq '[.[] | select(.active == true) | {id: .uuid, email: .username, flow: "xtls-rprx-vision"}]' "$USERS_FILE")
ACTIVE_XHTTP_CLIENTS=$(jq '[.[] | select(.active == true) | {id: .uuid, email: .username}]' "$USERS_FILE")

echo "[*] Rendering config..."

# We inject the clients array and replace placeholders
jq --argjson tcpClients "$ACTIVE_TCP_CLIENTS" \
   --argjson xhttpClients "$ACTIVE_XHTTP_CLIENTS" \
   --arg dest "$REALITY_DEST" \
   --arg serverName "$REALITY_SERVER_NAME" \
   --arg privateKey "$XRAY_PRIVATE_KEY" \
   --arg shortId "$XRAY_SHORT_ID" \
   --arg xhttpPath "$XHTTP_PATH" \
   --arg xhttpMode "$XHTTP_MODE" \
   '
   def apply_reality:
      .streamSettings.realitySettings.dest = $dest |
      del(.streamSettings.realitySettings.target) |
      .streamSettings.realitySettings.serverNames = [$serverName] |
      .streamSettings.realitySettings.privateKey = $privateKey |
      .streamSettings.realitySettings.shortIds = [$shortId];

   .inbounds |= map(
      if .protocol == "vless" and (.streamSettings.security // "") == "reality" then
        apply_reality |
        if (.streamSettings.network // "tcp") == "xhttp" then
          .settings.clients = $xhttpClients |
          .streamSettings.xhttpSettings.path = $xhttpPath |
          if $xhttpMode == "" then
            del(.streamSettings.xhttpSettings.mode)
          else
            .streamSettings.xhttpSettings.mode = $xhttpMode
          end
        else
          .settings.clients = $tcpClients
        end
      else
        .
      end
    )' \
    "$TEMPLATE" > "$TMP_TARGET"

# Xray inside the container may run as a non-root user; temporary config
# files must be world-readable for validation through the bind mount.
chmod 644 "$TMP_TARGET"

echo "[*] Validating Xray config..."
if validate_xray_config "$(basename "$TMP_TARGET")"; then
    mv "$TMP_TARGET" "$TARGET"
    echo "[+] Config is valid."
else
    rm -f "$TMP_TARGET"
    echo "[-] Config validation FAILED. Not applying this config."
    exit 1
fi

# Apply Domain Blocklist if enabled (this modifies config.json inside)
echo "[*] Injecting Domain Blocklist..."
bash scripts/apply-domain-blocklist.sh

# Note: apply-domain-blocklist.sh restarts docker container on its own,
# so we don't need a double restart here.
# But just in case blocklist is disabled, we restart it manually.
if [ "${ENABLE_DOMAIN_BLOCKLIST:-false}" != "true" ]; then
    if docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
        echo "[*] Restarting Xray wrapper to apply new config..."
        docker restart xray >/dev/null
    fi
fi

echo "[+] Render complete."
