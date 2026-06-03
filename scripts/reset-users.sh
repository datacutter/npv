#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIRM=${1:-}
USERS_FILE="data/users.json"

if [ "$CONFIRM" != "--yes" ]; then
    echo "Usage: make reset-users CONFIRM=YES"
    echo "This permanently removes all users from data/users.json after creating a backup."
    exit 1
fi

mkdir -p data

if [ -f "$USERS_FILE" ]; then
    BACKUP_FILE="data/users.json.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$USERS_FILE" "$BACKUP_FILE"
    echo "[*] Backup created: $BACKUP_FILE"
fi

echo "[]" > "$USERS_FILE"
echo "[*] All users removed from $USERS_FILE"

echo "[*] Updating Xray config..."
bash scripts/render-config.sh

echo "[+] User list has been reset."
