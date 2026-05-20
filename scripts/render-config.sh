#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

source .env
XRAY_IMAGE=${XRAY_IMAGE:-ghcr.io/xtls/xray-core:26.5.3}

validate_xray_config() {
    if [[ "$XRAY_IMAGE" == ghcr.io/xtls/xray-core:* ]]; then
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" run -test -config /etc/xray/config.json >/dev/null 2>&1
    else
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" xray run -test -config /etc/xray/config.json >/dev/null 2>&1
    fi
}

TEMPLATE="xray/config.template.json"
TARGET="xray/config.json"
USERS_FILE="data/users.json"

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: $TEMPLATE not found!"
    exit 1
fi

if [ ! -f "$USERS_FILE" ]; then
    echo "[]" > "$USERS_FILE"
fi

# Extract active clients and transform them for Xray config format
ACTIVE_CLIENTS=$(jq '[.[] | select(.active == true) | {id: .uuid, email: .username, flow: "xtls-rprx-vision"}]' "$USERS_FILE")

echo "[*] Rendering config..."

# We inject the clients array and replace placeholders
jq --argjson clients "$ACTIVE_CLIENTS" \
   --arg dest "$REALITY_DEST" \
   --arg serverName "$REALITY_SERVER_NAME" \
   --arg privateKey "$XRAY_PRIVATE_KEY" \
   --arg shortId "$XRAY_SHORT_ID" \
   '.inbounds |= map(
      if .protocol == "vless" and (.streamSettings.security // "") == "reality" then
        .settings.clients = $clients |
        .streamSettings.realitySettings.dest = $dest |
        .streamSettings.realitySettings.serverNames = [$serverName] |
        .streamSettings.realitySettings.privateKey = $privateKey |
        .streamSettings.realitySettings.shortIds = [$shortId]
      else
        .
      end
    )' \
    "$TEMPLATE" > "$TARGET"

echo "[*] Validating Xray config..."
if validate_xray_config; then
    echo "[+] Config is valid."
else
    echo "[-] Config validation FAILED. Rolling back might be needed."
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
