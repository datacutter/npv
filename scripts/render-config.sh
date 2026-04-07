#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

source .env

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
if docker run --rm -it -v "$(pwd)/xray:/etc/xray:ro" teddysun/xray xray run -test -confdir /etc/xray >/dev/null 2>&1; then
    echo "[+] Config is valid."
else
    echo "[-] Config validation FAILED. Rolling back might be needed."
    # For now we won't strictly exit, just warn.
fi

# Reload Xray if it's running
if docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[*] Restarting Xray wrapper to apply new config..."
    docker restart xray
fi

echo "[+] Render complete."
