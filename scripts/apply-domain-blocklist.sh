#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load environment
if [ ! -f ".env" ]; then
    echo "Error: .env not found."
    exit 1
fi
source .env

ENABLE_BLOCKLIST=${ENABLE_DOMAIN_BLOCKLIST:-false}
BLOCKLIST_FILE="data/blocked_domains.txt"
CONFIG_FILE="xray/config.json"

if [ "$ENABLE_BLOCKLIST" != "true" ]; then
    echo "Domain blocklist is disabled in .env (ENABLE_DOMAIN_BLOCKLIST=$ENABLE_BLOCKLIST)."
    bash scripts/reset-domain-blocklist.sh
    exit 0
fi

if [ ! -f "$BLOCKLIST_FILE" ]; then
    echo "Warning: $BLOCKLIST_FILE not found. Creating empty file."
    touch "$BLOCKLIST_FILE"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found! Render config first."
    exit 1
fi

echo "======================================"
echo " Applying Domain Blocklist to Xray    "
echo "======================================"

# Read domains, ignore empty lines and comments, format as "domain:example.com"
DOMAINS_JSON=$(grep -v '^\s*$' "$BLOCKLIST_FILE" | grep -v '^#' | sed 's/^/domain:/g' | jq -R . | jq -s .)

if [ "$DOMAINS_JSON" == "[]" ] || [ -z "$DOMAINS_JSON" ]; then
    echo "Blocklist is empty. Removing any existing routing rule..."
    bash scripts/reset-domain-blocklist.sh
    exit 0
fi

# Reset existing rule to avoid duplicates
TMP_FILE=$(mktemp)
jq 'del(.routing.rules[] | select(.tag == "domain-blocklist"))' "$CONFIG_FILE" > "$TMP_FILE"

# Inject new rule at the top of the routing rules
jq --argjson domains "$DOMAINS_JSON" \
   '.routing.rules = [{"type": "field", "outboundTag": "block", "domain": $domains, "tag": "domain-blocklist"}] + .routing.rules' \
   "$TMP_FILE" > "${TMP_FILE}.new"

mv "${TMP_FILE}.new" "$CONFIG_FILE"
rm -f "$TMP_FILE"

echo "[*] Injected Xray routing rules for $(echo "$DOMAINS_JSON" | jq 'length') domains."

# Check if Xray container is running, if so, restart it to apply
if docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[*] Restarting Xray container to apply routing changes..."
    docker restart xray
fi

echo "[+] Domain blocklist applied successfully."
