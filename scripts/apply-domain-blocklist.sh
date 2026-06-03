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
XRAY_IMAGE=${XRAY_IMAGE:-ghcr.io/xtls/xray-core:26.6.1}
BLOCKLIST_FILE="data/blocked_domains.txt"
CONFIG_FILE="xray/config.json"

validate_xray_config() {
    local config_name=${1:-config.json}

    if ! command -v docker >/dev/null 2>&1; then
        echo "[!] Docker is not available; skipping Xray config validation."
        return 0
    fi

    if [[ "$XRAY_IMAGE" == ghcr.io/xtls/xray-core:* ]]; then
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" run -test -config "/etc/xray/${config_name}" >/dev/null
    else
        docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$XRAY_IMAGE" xray run -test -config "/etc/xray/${config_name}" >/dev/null
    fi
}

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

# Read domains, ignore empty lines and comments, format as "domain:example.com".
# awk exits successfully on an empty list; grep under pipefail would not.
DOMAINS_JSON=$(awk 'NF && $0 !~ /^#/ { print "domain:" $0 }' "$BLOCKLIST_FILE" | jq -R . | jq -s .)

if [ "$DOMAINS_JSON" == "[]" ] || [ -z "$DOMAINS_JSON" ]; then
    echo "Blocklist is empty. Removing any existing routing rule..."
    bash scripts/reset-domain-blocklist.sh
    exit 0
fi

# Reset existing rule to avoid duplicates
TMP_FILE=$(mktemp)
TMP_CONFIG=$(mktemp xray/config.blocklist.XXXXXX.json)
cleanup() {
    rm -f "$TMP_FILE" "$TMP_CONFIG"
}
trap cleanup EXIT

jq 'del(.routing.rules[] | select(.tag == "domain-blocklist"))' "$CONFIG_FILE" > "$TMP_FILE"

# Inject new rule at the top of the routing rules
jq --argjson domains "$DOMAINS_JSON" \
   '.routing.rules = [{"type": "field", "outboundTag": "block", "domain": $domains, "tag": "domain-blocklist"}] + .routing.rules' \
   "$TMP_FILE" > "$TMP_CONFIG"

# Xray inside the container may run as a non-root user; temporary config
# files must be world-readable for validation through the bind mount.
chmod 644 "$TMP_CONFIG"

echo "[*] Injected Xray routing rules for $(echo "$DOMAINS_JSON" | jq 'length') domains."
echo "[*] Validating Xray config after blocklist injection..."
validate_xray_config "$(basename "$TMP_CONFIG")"

mv "$TMP_CONFIG" "$CONFIG_FILE"
rm -f "$TMP_FILE"

# Check if Xray container is running, if so, restart it to apply
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[*] Restarting Xray container to apply routing changes..."
    docker restart xray
fi

echo "[+] Domain blocklist applied successfully."
