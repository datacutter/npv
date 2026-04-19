#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

source .env
XRAY_IMAGE=${XRAY_IMAGE:-teddysun/xray:26.4.15}

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
   '.inbounds[1].settings.clients = $clients | 
    .inbounds[1].streamSettings.realitySettings.dest = $dest |
    .inbounds[1].streamSettings.realitySettings.serverNames = [$serverName] |
    .inbounds[1].streamSettings.realitySettings.privateKey = $privateKey |
    .inbounds[1].streamSettings.realitySettings.shortIds = [$shortId]' \
    "$TEMPLATE" > "$TARGET"

echo "[*] Validating Xray config..."
if docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" xray run -test -config /etc/xray/config.json >/dev/null 2>&1; then
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
