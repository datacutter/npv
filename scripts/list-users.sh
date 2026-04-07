#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

USERS_FILE="data/users.json"

if [ ! -f "$USERS_FILE" ]; then
    echo "No users found (users.json does not exist)."
    exit 0
fi

echo ""
printf "%-20s %-40s %-25s %-10s\n" "USERNAME" "UUID" "CREATED AT" "STATUS"
echo "------------------------------------------------------------------------------------------------"

jq -r '.[] | "\(.username) \(.uuid) \(.created_at) \(.active)"' "$USERS_FILE" | while read -r username uuid created active; do
    status="[ACTIVE]"
    if [ "$active" != "true" ]; then
        status="[REVOKED]"
    fi
    printf "%-20s %-40s %-25s %-10s\n" "$username" "$uuid" "$created" "$status"
done

echo ""
