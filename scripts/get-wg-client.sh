#!/bin/bash
set -e

if [ ! -f ".env" ]; then
    echo "Error: .env not found."
    exit 1
fi
export $(grep -v '^#' .env | xargs)

CLIENT_NAME=$1
if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: ./get-wg-client.sh <client_name>"
    CLIENT_NAME="client1"
    echo "Defaulting to client name: $CLIENT_NAME"
fi

CLIENT_FILE="clients/${CLIENT_NAME}.conf"

if [ -f "$CLIENT_FILE" ]; then
    echo "[!] Config for $CLIENT_NAME already exists: $CLIENT_FILE"
    exit 0
fi

mkdir -p clients

echo "=> Generating keys for client: $CLIENT_NAME"
CLIENT_PRIV=$(docker run --rm --entrypoint wg lscr.io/linuxserver/wireguard genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | docker run --rm -i --entrypoint wg lscr.io/linuxserver/wireguard pubkey)

# We need to assign an IP addr. Let's find the last assigned IP in wg0.conf
# This handles extraction safely. If config doesn't exist, exit.
if [ ! -f "wireguard/config/wg0.conf" ]; then
    echo "Error: Server wg0.conf not found. Ensure init is run."
    exit 1
fi

LAST_IP=$(grep -oP 'AllowedIPs = 10\.13\.13\.\K\d+' wireguard/config/wg0.conf | tail -n 1 || echo "")
if [ -z "$LAST_IP" ]; then
    NEXT_IP=2
else
    NEXT_IP=$((LAST_IP + 1))
fi

if [ "$NEXT_IP" -gt 254 ]; then
    echo "IP range is fully occupied."
    exit 1
fi

CLIENT_IP="10.13.13.${NEXT_IP}/32"

# Append peer to server config
echo "" >> wireguard/config/wg0.conf
echo "### Client: $CLIENT_NAME" >> wireguard/config/wg0.conf
echo "[Peer]" >> wireguard/config/wg0.conf
echo "PublicKey = $CLIENT_PUB" >> wireguard/config/wg0.conf
echo "AllowedIPs = $CLIENT_IP" >> wireguard/config/wg0.conf

# Create client config file
cat > "$CLIENT_FILE" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.13.13.${NEXT_IP}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $WG_SERVER_PUBLIC_KEY
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo "[+] Client config generated at: $CLIENT_FILE"
echo ""
echo "Note: If the wireguard container is running, restart it to apply the new peer:"
echo "docker-compose restart wireguard"
