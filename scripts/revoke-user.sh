#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
if [ -z "$USERNAME" ]; then
    echo "Usage: make revoke-user USER=alice"
    exit 1
fi

if ! [[ "$USERNAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    echo "Error: username must be 1-64 chars and contain only letters, digits, dot, underscore, or dash."
    exit 1
fi

USERS_FILE="data/users.json"

if ! jq -e --arg username "$USERNAME" '.[] | select(.username == $username)' "$USERS_FILE" > /dev/null; then
    echo "User '$USERNAME' does not exist."
    exit 1
fi

echo "[*] Revoking user '$USERNAME'..."

TMP_FILE=$(mktemp)
jq --arg username "$USERNAME" 'map((select(.username == $username) | .active) = false)' "$USERS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$USERS_FILE"

echo "[*] Updating Xray config..."
bash scripts/render-config.sh

echo "[+] User '$USERNAME' has been deactivated."
