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
XRAY_PORT_XHTTP=${XRAY_PORT_XHTTP:-9443}
REALITY_FINGERPRINT=${REALITY_FINGERPRINT:-edge}
REALITY_FINGERPRINTS=${REALITY_FINGERPRINTS:-$REALITY_FINGERPRINT}
REALITY_SPIDER_X=${REALITY_SPIDER_X:-/}
XHTTP_PATH=${XHTTP_PATH:-/assets}
XHTTP_MODE=${XHTTP_MODE:-auto}

for required_var in SERVER_IP REALITY_SERVER_NAME XRAY_PUBLIC_KEY XRAY_SHORT_ID; do
    if [ -z "${!required_var:-}" ]; then
        echo "Error: $required_var is missing in .env."
        exit 1
    fi
done

if [[ "$XHTTP_PATH" != /* ]]; then
    echo "Error: XHTTP_PATH must start with '/'. Current value: $XHTTP_PATH"
    exit 1
fi

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

fingerprint_list() {
    printf '%s\n' "$REALITY_FINGERPRINTS" |
        tr ',' '\n' |
        awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "" && !seen[$0]++) print $0 }'
}

client_spider_x() {
    local base=${REALITY_SPIDER_X:-/}

    if [ "$base" = "/" ]; then
        printf '/%s' "$USERNAME"
        return
    fi

    printf '%s/%s' "${base%/}" "$USERNAME"
}

build_tcp_vless_link() {
    local port=$1
    local profile_suffix=$2
    local fingerprint=$3
    local encoded_sni encoded_spx encoded_profile

    encoded_sni=$(urlencode "$REALITY_SERVER_NAME")
    encoded_spx=$(urlencode "$(client_spider_x)")
    encoded_profile=$(urlencode "${USERNAME}_tcp${profile_suffix}_${fingerprint}")

    printf 'vless://%s@%s:%s?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&fp=%s&pbk=%s&sni=%s&sid=%s&spx=%s&headerType=none#%s' \
        "$UUID" \
        "$SERVER_IP" \
        "$port" \
        "$fingerprint" \
        "$XRAY_PUBLIC_KEY" \
        "$encoded_sni" \
        "$XRAY_SHORT_ID" \
        "$encoded_spx" \
        "$encoded_profile"
}

build_xhttp_vless_link() {
    local fingerprint=$1
    local encoded_sni encoded_host encoded_path encoded_spx encoded_profile

    encoded_sni=$(urlencode "$REALITY_SERVER_NAME")
    encoded_host=$(urlencode "$REALITY_SERVER_NAME")
    encoded_path=$(urlencode "$XHTTP_PATH")
    encoded_spx=$(urlencode "$(client_spider_x)")
    encoded_profile=$(urlencode "${USERNAME}_xhttp_${fingerprint}")

    printf 'vless://%s@%s:%s?type=xhttp&security=reality&encryption=none&fp=%s&pbk=%s&sni=%s&sid=%s&spx=%s&path=%s&host=%s&mode=%s#%s' \
        "$UUID" \
        "$SERVER_IP" \
        "$XRAY_PORT_XHTTP" \
        "$fingerprint" \
        "$XRAY_PUBLIC_KEY" \
        "$encoded_sni" \
        "$XRAY_SHORT_ID" \
        "$encoded_spx" \
        "$encoded_path" \
        "$encoded_host" \
        "$XHTTP_MODE" \
        "$encoded_profile"
}

mapfile -t FINGERPRINTS < <(fingerprint_list)
if [ "${#FINGERPRINTS[@]}" -eq 0 ]; then
    FINGERPRINTS=("$REALITY_FINGERPRINT")
fi

PRIMARY_FINGERPRINT=${FINGERPRINTS[0]}
PRIMARY_XHTTP_LINK=$(build_xhttp_vless_link "$PRIMARY_FINGERPRINT")
PRIMARY_TCP_LINK=$(build_tcp_vless_link "$XRAY_PORT" "" "$PRIMARY_FINGERPRINT")
ALT_TCP_LINK=$(build_tcp_vless_link "$XRAY_PORT_ALT" "_${XRAY_PORT_ALT}" "$PRIMARY_FINGERPRINT")

echo "================================================="
echo "  Client Connection Details for: $USERNAME"
echo "================================================="
echo "- Protocol: VLESS"
echo "- Recommended transport: XHTTP + REALITY"
echo "- Legacy fallback: TCP + REALITY + xtls-rprx-vision"
echo "- UUID: $UUID"
echo "- XHTTP Server: ${SERVER_IP}:${XRAY_PORT_XHTTP}"
echo "- TCP Primary Server: ${SERVER_IP}:${XRAY_PORT}"
echo "- TCP Fallback Server: ${SERVER_IP}:${XRAY_PORT_ALT}"
echo "- SNI (ServerName): $REALITY_SERVER_NAME"
echo "- Public Key: $XRAY_PUBLIC_KEY"
echo "- Short ID: $XRAY_SHORT_ID"
echo "- XHTTP Path: $XHTTP_PATH"
echo "- XHTTP Mode: $XHTTP_MODE"
echo "- SpiderX: $(client_spider_x)"
echo "- Fingerprints: ${FINGERPRINTS[*]}"
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo "[!] Warning: SERVER_IP is still YOUR_SERVER_IP. Update .env before sharing links."
fi
echo "================================================="
echo " RECOMMENDED XHTTP IMPORT LINKS "
echo "================================================="
for fingerprint in "${FINGERPRINTS[@]}"; do
    echo ""
    echo "# XHTTP + REALITY / fp=$fingerprint"
    build_xhttp_vless_link "$fingerprint"
    echo ""
done

echo "================================================="
echo " LEGACY TCP IMPORT LINKS "
echo "================================================="
echo ""
echo "# TCP + REALITY primary / fp=$PRIMARY_FINGERPRINT"
echo "$PRIMARY_TCP_LINK"
echo ""
echo "# TCP + REALITY fallback port / fp=$PRIMARY_FINGERPRINT"
echo "$ALT_TCP_LINK"
echo ""
echo "================================================="
echo " QR example: qrencode -t ANSI '$PRIMARY_XHTTP_LINK'"
