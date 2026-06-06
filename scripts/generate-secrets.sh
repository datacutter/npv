#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

FORCE=0
if [ "${1:-}" == "--force" ]; then
    FORCE=1
fi

source .env
SERVER_IP=${SERVER_IP:-YOUR_SERVER_IP}
XRAY_IMAGE=${XRAY_IMAGE:-ghcr.io/xtls/xray-core:26.6.1}

run_xray_image() {
    if [[ "$XRAY_IMAGE" == ghcr.io/xtls/xray-core:* ]]; then
        docker run --rm --network none "$XRAY_IMAGE" "$@"
    else
        docker run --rm --network none --entrypoint "" "$XRAY_IMAGE" xray "$@"
    fi
}

set_env() {
    local key=$1
    local value=$2
    local tmp
    tmp=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        $0 ~ "^" key "=" {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (found == 0) {
                print key "=" value
            }
        }
    ' .env > "$tmp"

    mv "$tmp" .env
}

UPDATE_ENV=0

# Server IP
if [ "$SERVER_IP" == "YOUR_SERVER_IP" ]; then
    SERVER_IP=$(curl -s ipv4.icanhazip.com || echo "YOUR_SERVER_IP")
    set_env SERVER_IP "$SERVER_IP"
    echo "[+] Server IP updated."
fi

# Xray Keys
if [ -z "${XRAY_PRIVATE_KEY:-}" ] || [ "$FORCE" -eq 1 ]; then
    echo "[*] Generating Reality Keys..."
    
    KEYS=$(run_xray_image x25519) || {
        echo "Error: Failed to generate Xray keys."
        exit 1
    }

    PRIV=$(awk -F: '
        {
            key = tolower($1)
            if (key ~ /private[[:space:]]*key|privatekey/) {
                value = $2
                gsub(/\r/, "", value)
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                exit
            }
        }
    ' <<<"$KEYS")

    # New Xray versions call the client-side public key "Password".
    # Older builds may print "PublicKey" or "Password (PublicKey)".
    PUB=$(awk -F: '
        {
            key = tolower($1)
            if (key ~ /password|public[[:space:]]*key|publickey/) {
                value = $2
                gsub(/\r/, "", value)
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                exit
            }
        }
    ' <<<"$KEYS")

    if [ -z "$PRIV" ] || [ -z "$PUB" ]; then
        echo "Error: Could not parse Xray keys from output. Unexpected format."
        echo "Full output was:"
        echo "$KEYS"
        exit 1
    fi

    set_env XRAY_PRIVATE_KEY "$PRIV"
    set_env XRAY_PUBLIC_KEY "$PUB"
    UPDATE_ENV=1
fi

if [ -z "${XRAY_SHORT_ID:-}" ] || [ "$FORCE" -eq 1 ]; then
    SID=$(openssl rand -hex 8)
    set_env XRAY_SHORT_ID "$SID"
    UPDATE_ENV=1
fi

if [ -z "${XHTTP_PATH:-}" ] || [ "${XHTTP_PATH:-}" = "/__CHANGE_ME_XHTTP_PATH__" ] || [ "$FORCE" -eq 1 ]; then
    XHTTP_RANDOM_PATH="/assets/$(openssl rand -hex 6)"
    set_env XHTTP_PATH "$XHTTP_RANDOM_PATH"
    UPDATE_ENV=1
fi

if [ "$UPDATE_ENV" -eq 1 ]; then
    echo "[+] Secrets generated successfully."
else
    echo "[!] Secrets already exist. Use --force to regenerate."
fi
