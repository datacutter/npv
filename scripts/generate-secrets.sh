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
    KEYS=$(docker run --rm teddysun/xray xray x25519)
    PRIV=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
    PUB=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
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
