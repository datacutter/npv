#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
if [ -z "$USERNAME" ]; then
    echo "Usage: make client-config USER=alice"
    exit 1
fi

USERS_FILE="data/users.json"
source .env
XRAY_PORT_ALT=${XRAY_PORT_ALT:-8443}

if ! jq -e ".[] | select(.username == \"$USERNAME\")" "$USERS_FILE" > /dev/null; then
    echo "User '$USERNAME' does not exist."
    exit 1
fi

UUID=$(jq -r ".[] | select(.username == \"$USERNAME\") | .uuid" "$USERS_FILE")
ACTIVE=$(jq -r ".[] | select(.username == \"$USERNAME\") | .active" "$USERS_FILE")

if [ "$ACTIVE" != "true" ]; then
    echo "Warning: This user is currently REVOKED."
fi

URLEncoded_REALITY_SERVER_NAME=$(echo "$REALITY_SERVER_NAME" | sed 's/ /%20/g')

PRIMARY_VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#${USERNAME}"
ALT_VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT_ALT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#${USERNAME}_8443"

echo "================================================="
echo "  Client Connection Details for: $USERNAME"
echo "================================================="
echo "- Protocol: VLESS"
echo "- UUID: $UUID"
echo "- Primary Server: ${SERVER_IP}:${XRAY_PORT}"
echo "- Fallback Server: ${SERVER_IP}:${XRAY_PORT_ALT}"
echo "- Flow: xtls-rprx-vision"
echo "- Network: tcp"
echo "- Security: reality"
echo "- SNI (ServerName): $REALITY_SERVER_NAME"
echo "- Public Key: $XRAY_PUBLIC_KEY"
echo "- Short ID: $XRAY_SHORT_ID"
echo "- Fingerprint: chrome"
echo "================================================="
echo " PRIMARY IMPORT LINK (default port) "
echo "================================================="
echo ""
echo "$PRIMARY_VLESS_LINK"
echo ""
echo "================================================="
echo " FALLBACK IMPORT LINK (use if 443 is filtered) "
echo "================================================="
echo ""
echo "$ALT_VLESS_LINK"
echo ""
echo "================================================="
echo " (To create a QR code, you can use: qrencode -t ANSI '$PRIMARY_VLESS_LINK')"
