#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "Xray container is not running!"
    exit 1
fi

echo "[*] Querying Xray API (10085)..."
STATS_JSON=$(docker exec xray xray api statsquery -server=127.0.0.1:10085)

# Some Xray builds may return null/empty stats for users without traffic yet.
# Normalize to a safe array to avoid jq runtime errors.
STAT_ENTRIES=$(echo "$STATS_JSON" | jq -c '(.stat // .stats // [])')

echo ""
printf "%-20s %-15s %-15s %-15s\n" "USERNAME" "UPLINK" "DOWNLINK" "TOTAL"
echo "----------------------------------------------------------------------"

# Convert bytes to human readable form
human_readable() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" == "null" ]; then
        echo "0B"
        return
    fi
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        # Print GB with 2 precision points
        awk "BEGIN {printf \"%.2fGB\", $bytes / 1073741824}"
    fi
}

USERS_FILE="data/users.json"
if [ ! -f "$USERS_FILE" ]; then
    echo "No users.json found."
    exit 0
fi

jq -r '.[] | .username' "$USERS_FILE" | while read -r username; do
    up=$(echo "$STAT_ENTRIES" | jq -r ".[] | select(.name == \"user>>>${username}>>>traffic>>>uplink\") | .value")
    down=$(echo "$STAT_ENTRIES" | jq -r ".[] | select(.name == \"user>>>${username}>>>traffic>>>downlink\") | .value")
    
    [ -z "$up" ] && up=0
    [ -z "$down" ] && down=0
    total=$((up + down))
    
    hr_up=$(human_readable "$up")
    hr_down=$(human_readable "$down")
    hr_tot=$(human_readable "$total")
    
    printf "%-20s %-15s %-15s %-15s\n" "$username" "$hr_up" "$hr_down" "$hr_tot"
done

echo ""
