#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "====================================="
echo "   VPN Init: Xray + VLESS Reality    "
echo "====================================="

# Check requirements
for cmd in docker jq openssl curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' is not installed."
        echo "Please install it: sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq openssl curl"
        exit 1
    fi
done

# Ensure basic files exist
mkdir -p data xray scripts
if [ ! -f "data/users.json" ]; then
    echo "[]" > data/users.json
    echo "[+] Initialized empty users.json"
fi

if [ ! -f ".env" ]; then
    echo "[+] .env not found. Copying .env.example ..."
    cp .env.example .env
fi

# Run Secret Generator
echo "[*] Step 1: Generating Secrets ..."
bash scripts/generate-secrets.sh

# Render Final Config
echo "[*] Step 2: Rendering Config ..."
bash scripts/render-config.sh

# Apply Firewall Rules
echo "[*] Step 3: Configuring Firewall ..."
if sudo iptables -h >/dev/null 2>&1; then
    bash scripts/apply-firewall.sh
else
    echo "[!] Iptables not found or no sudo privileges. Skipping firewall setup."
fi

echo "[+] Initialization complete. You can now run: make up"
