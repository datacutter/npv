#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
if [ -z "$USERNAME" ]; then
    echo "Usage: make client-config USER=alice"
    exit 1
fi

USERS_FILE="data/users.json"
# shellcheck disable=SC1091
source .env
XRAY_PORT=${XRAY_PORT:-443}
XRAY_PORT_ALT=${XRAY_PORT_ALT:-8443}
REALITY_FINGERPRINT=${REALITY_FINGERPRINT:-chrome}
REALITY_SPIDER_X=${REALITY_SPIDER_X:-/}

for required_var in SERVER_IP REALITY_SERVER_NAME XRAY_PUBLIC_KEY XRAY_SHORT_ID; do
    if [ -z "${!required_var:-}" ]; then
        echo "Error: $required_var is missing in .env."
        exit 1
    fi
done

if ! jq -e --arg username "$USERNAME" '.[] | select(.username == $username)' "$USERS_FILE" > /dev/null; then
    echo "User '$USERNAME' does not exist."
    exit 1
fi

UUID=$(jq -r --arg username "$USERNAME" '.[] | select(.username == $username) | .uuid' "$USERS_FILE")
ACTIVE=$(jq -r --arg username "$USERNAME" '.[] | select(.username == $username) | .active' "$USERS_FILE")

if [ "$ACTIVE" != "true" ]; then
    echo "Warning: This user is currently REVOKED."
fi

urlencode() {
    jq -rn --arg value "$1" '$value | @uri'
}

client_spider_x() {
    local base=${REALITY_SPIDER_X:-/}

    if [ "$base" = "/" ]; then
        printf '/%s' "$USERNAME"
        return
    fi

    printf '%s/%s' "${base%/}" "$USERNAME"
}

build_vless_link() {
    local port=$1
    local profile_suffix=$2
    local encoded_sni encoded_spx encoded_profile

    encoded_sni=$(urlencode "$REALITY_SERVER_NAME")
    encoded_spx=$(urlencode "$(client_spider_x)")
    encoded_profile=$(urlencode "${USERNAME}${profile_suffix}")

    printf 'vless://%s@%s:%s?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&fp=%s&pbk=%s&sni=%s&sid=%s&spx=%s&headerType=none#%s' \
        "$UUID" \
        "$SERVER_IP" \
        "$port" \
        "$REALITY_FINGERPRINT" \
        "$XRAY_PUBLIC_KEY" \
        "$encoded_sni" \
        "$XRAY_SHORT_ID" \
        "$encoded_spx" \
        "$encoded_profile"
}

PRIMARY_VLESS_LINK=$(build_vless_link "$XRAY_PORT" "")
ALT_VLESS_LINK=$(build_vless_link "$XRAY_PORT_ALT" "_${XRAY_PORT_ALT}")

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
echo "- Fingerprint: $REALITY_FINGERPRINT"
echo "- SpiderX: $(client_spider_x)"
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo "[!] Warning: SERVER_IP is still YOUR_SERVER_IP. Update .env before sharing links."
fi
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
