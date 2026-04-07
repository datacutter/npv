#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
if [ -z "$USERNAME" ]; then
    echo "Usage: make add-user USER=alice"
    exit 1
fi

USERS_FILE="data/users.json"

# Check if user already exists
if jq -e ".[] | select(.username == \"$USERNAME\")" "$USERS_FILE" > /dev/null; then
    ACTIVE=$(jq -r ".[] | select(.username == \"$USERNAME\") | .active" "$USERS_FILE")
    if [ "$ACTIVE" == "true" ]; then
        echo "User '$USERNAME' already exists and is active."
        exit 0
    else
        echo "User '$USERNAME' exists but is deactivated. Reactivating..."
        TMP_FILE=$(mktemp)
        jq "map((select(.username == \"$USERNAME\") | .active) = true)" "$USERS_FILE" > "$TMP_FILE"
        mv "$TMP_FILE" "$USERS_FILE"
    fi
else
    # Create new user
    UUID=$(cat /proc/sys/kernel/random/uuid)
    DATE_STR=$(date +%Y-%m-%dT%H:%M:%SZ)
    
    echo "[*] Generating UUID for $USERNAME: $UUID"
    
    TMP_FILE=$(mktemp)
    jq ". += [{\"username\": \"$USERNAME\", \"uuid\": \"$UUID\", \"created_at\": \"$DATE_STR\", \"active\": true}]" "$USERS_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$USERS_FILE"
fi

echo "[*] Updating Xray config..."
bash scripts/render-config.sh

echo "----------------------------------------"
echo " User added: $USERNAME"
echo "----------------------------------------"
bash scripts/print-client-config.sh "$USERNAME"
