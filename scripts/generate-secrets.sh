#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

FORCE=0
if [ "${1:-}" == "--force" ]; then
    FORCE=1
fi

source .env

UPDATE_ENV=0

# Server IP
if [ "$SERVER_IP" == "YOUR_SERVER_IP" ]; then
    SERVER_IP=$(curl -s ipv4.icanhazip.com || echo "YOUR_SERVER_IP")
    sed -i "s/YOUR_SERVER_IP/$SERVER_IP/g" .env
    echo "[+] Server IP updated."
fi

# Xray Keys
if [ -z "${XRAY_PRIVATE_KEY:-}" ] || [ "$FORCE" -eq 1 ]; then
    echo "[*] Generating Reality Keys..."
    
    # We use empty entrypoint to ensure the command is found in PATH
    KEYS=$(docker run --rm --network none --entrypoint "" teddysun/xray xray x25519) || {
        echo "Error: Failed to generate Xray keys."
        exit 1
    }

    # Format: PrivateKey: <key>
    PRIV=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r')
    # Format: Password (PublicKey): <key>
    PUB=$(echo "$KEYS" | grep "PublicKey):" | awk '{print $3}' | tr -d '\r')

    if [ -z "$PRIV" ] || [ -z "$PUB" ]; then
        echo "Error: Could not parse Xray keys from output. Unexpected format."
        echo "Full output was:"
        echo "$KEYS"
        exit 1
    fi

    sed -i "s|^XRAY_PRIVATE_KEY=.*|XRAY_PRIVATE_KEY=$PRIV|g" .env
    sed -i "s|^XRAY_PUBLIC_KEY=.*|XRAY_PUBLIC_KEY=$PUB|g" .env
    UPDATE_ENV=1
fi

if [ -z "${XRAY_SHORT_ID:-}" ] || [ "$FORCE" -eq 1 ]; then
    SID=$(openssl rand -hex 8)
    sed -i "s|^XRAY_SHORT_ID=.*|XRAY_SHORT_ID=$SID|g" .env
    UPDATE_ENV=1
fi

if [ "$UPDATE_ENV" -eq 1 ]; then
    echo "[+] Secrets generated successfully."
else
    echo "[!] Secrets already exist. Use --force to regenerate."
fi
