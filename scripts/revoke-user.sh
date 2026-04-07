#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
if [ -z "$USERNAME" ]; then
    echo "Usage: make revoke-user USER=alice"
    exit 1
fi

USERS_FILE="data/users.json"

if ! jq -e ".[] | select(.username == \"$USERNAME\")" "$USERS_FILE" > /dev/null; then
    echo "User '$USERNAME' does not exist."
    exit 1
fi

echo "[*] Revoking user '$USERNAME'..."

TMP_FILE=$(mktemp)
jq "map((select(.username == \"$USERNAME\") | .active) = false)" "$USERS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$USERS_FILE"

echo "[*] Updating Xray config..."
bash scripts/render-config.sh

echo "[+] User '$USERNAME' has been deactivated."
