#!/bin/bash
set -e

echo "Ensuring directories exist..."
mkdir -p xray/data wireguard/config clients

if [ ! -f .env ]; then
    echo "=> .env file not found. Generating from .env.example..."
    cp .env.example .env
    
    echo "=> Autodetecting Server IP..."
    SERVER_IP=$(curl -s ipv4.icanhazip.com || echo "YOUR_SERVER_IP")
    sed -i "s/YOUR_SERVER_IP/$SERVER_IP/g" .env

    echo "=> Generating XRAY UUID..."
    XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "s/^XRAY_UUID=.*/XRAY_UUID=$XRAY_UUID/g" .env

    echo "=> Generating XRAY Reality Keys..."
    XRAY_KEYS=$(docker run --rm teddysun/xray xray x25519)
    XRAY_PRIV=$(echo "$XRAY_KEYS" | grep "Private key" | awk '{print $3}')
    XRAY_PUB=$(echo "$XRAY_KEYS" | grep "Public key" | awk '{print $3}')
    sed -i "s/^XRAY_PRIVATE_KEY=.*/XRAY_PRIVATE_KEY=$XRAY_PRIV/g" .env
    sed -i "s/^XRAY_PUBLIC_KEY=.*/XRAY_PUBLIC_KEY=$XRAY_PUB/g" .env

    echo "=> Generating XRAY Short ID..."
    XRAY_SHORT_ID=$(openssl rand -hex 8)
    sed -i "s/^XRAY_SHORT_ID=.*/XRAY_SHORT_ID=$XRAY_SHORT_ID/g" .env

    echo "=> Generating WireGuard Server Keys..."
    WG_PRIV=$(docker run --rm --entrypoint wg lscr.io/linuxserver/wireguard genkey)
    WG_PUB=$(echo "$WG_PRIV" | docker run --rm -i --entrypoint wg lscr.io/linuxserver/wireguard pubkey)
    sed -i "s|^WG_SERVER_PRIVATE_KEY=.*|WG_SERVER_PRIVATE_KEY=$WG_PRIV|g" .env
    sed -i "s|^WG_SERVER_PUBLIC_KEY=.*|WG_SERVER_PUBLIC_KEY=$WG_PUB|g" .env
    
    echo "[+] Generated .env successfully."
else
    echo "[*] .env file already exists. Skipping secret generation."
fi

echo "=> Sourcing .env..."
export $(grep -v '^#' .env | xargs)

echo "=> Rendering templates..."
sed -e "s/\${XRAY_UUID}/$XRAY_UUID/g" \
    -e "s/\${REALITY_DEST}/$REALITY_DEST/g" \
    -e "s/\${REALITY_SERVER_NAME}/$REALITY_SERVER_NAME/g" \
    -e "s/\${XRAY_PRIVATE_KEY}/$XRAY_PRIVATE_KEY/g" \
    -e "s/\${XRAY_SHORT_ID}/$XRAY_SHORT_ID/g" \
    templates/xray.json.template > xray/config.json

sed -e "s|\${WG_SERVER_PRIVATE_KEY}|$WG_SERVER_PRIVATE_KEY|g" \
    templates/wg0.conf.template > wireguard/config/wg0.conf

echo "[+] Rendered config files into xray/ and wireguard/ directories."
echo "[+] Init step completed perfectly."
