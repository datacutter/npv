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

VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#${USERNAME}"

echo "================================================="
echo "  Client Connection Details for: $USERNAME"
echo "================================================="
echo "- Protocol: VLESS"
echo "- UUID: $UUID"
echo "- Server: ${SERVER_IP}:${XRAY_PORT}"
echo "- Flow: xtls-rprx-vision"
echo "- Network: tcp"
echo "- Security: reality"
echo "- SNI (ServerName): $REALITY_SERVER_NAME"
echo "- Public Key: $XRAY_PUBLIC_KEY"
echo "- Short ID: $XRAY_SHORT_ID"
echo "- Fingerprint: chrome"
echo "================================================="
echo " IMPORT LINK (For NekoBox Android & Shadowrocket) "
echo "================================================="
echo ""
echo "$VLESS_LINK"
echo ""
echo "================================================="
echo " (To create a QR code, you can use: qrencode -t ANSI '$VLESS_LINK')"
