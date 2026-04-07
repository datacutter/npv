#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG_FILE="xray/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Nothing to reset, $CONFIG_FILE not found."
    exit 0
fi

echo "======================================"
echo " Resetting Xray Domain Blocklist      "
echo "======================================"

# Remove the rule with the specific tag
TMP_FILE=$(mktemp)
jq 'del(.routing.rules[]? | select(.tag == "domain-blocklist"))' "$CONFIG_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$CONFIG_FILE"

echo "[*] Blocklist rules removed from $CONFIG_FILE."

# Restart Xray if running to clear memory
if docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[*] Restarting Xray container to apply changes..."
    docker restart xray >/dev/null
fi

echo "[+] Blocklist reset successfully."
