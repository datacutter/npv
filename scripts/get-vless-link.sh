#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME=${1:-}
USERS_FILE="data/users.json"

if [ -z "$USERNAME" ]; then
    if [ ! -f "$USERS_FILE" ]; then
        echo "Usage: bash scripts/get-vless-link.sh <username>"
        exit 1
    fi

    USERNAME=$(jq -r '.[] | select(.active == true) | .username' "$USERS_FILE" | head -n 1)
fi

if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ]; then
    echo "No active users found. Create one first: make add-user USER=alice"
    exit 1
fi

bash scripts/print-client-config.sh "$USERNAME"
