#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Checks whether the VPS IP/ports are reachable from inside Russia, using the
# public check-host.net API (it has real nodes on Russian ISPs). This is the
# fastest way to tell an IP/subnet block apart from a protocol/SNI block:
#
#   - All RU nodes time out / refuse  -> IP or subnet is blocked (or firewall).
#     Rotating Reality will NOT help. Move to a new IP / provider.
#   - RU nodes connect (TCP OK) but clients still cannot pass traffic
#     -> protocol / Reality / SNI heuristic. Rotate Reality and/or SNI.
#
# Requires: curl, jq. Runs from anywhere (your laptop or the VPS).

API="https://check-host.net"
ACCEPT='Accept: application/json'

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "[!] This script needs 'curl' and 'jq' installed."
    exit 1
fi

HOST_IP="${1:-}"
if [ -z "$HOST_IP" ] && [ -f ".env" ]; then
    # shellcheck disable=SC1091
    source .env
    HOST_IP="${SERVER_IP:-}"
fi

if [ -z "$HOST_IP" ] || [ "$HOST_IP" = "YOUR_SERVER_IP" ]; then
    echo "Usage: bash scripts/check-ru-reachability.sh <SERVER_IP> [port1 port2 ...]"
    echo "       (or set SERVER_IP in .env)"
    exit 1
fi

shift || true
if [ "$#" -gt 0 ]; then
    PORTS=("$@")
else
    PORTS=("${XRAY_PORT:-443}" "${XRAY_PORT_ALT:-8443}" "${XRAY_PORT_XHTTP:-9443}")
fi

echo "======================================"
echo " Reachability from Russia: $HOST_IP"
echo "======================================"
echo "Ports: ${PORTS[*]}"
echo "Source: check-host.net (Russian ISP nodes)"
echo ""

overall_blocked=0

check_port() {
    local port="$1"
    local target="${HOST_IP}:${port}"

    local start
    start=$(curl -s -H "$ACCEPT" "${API}/check-tcp?host=${target}&max_nodes=30")

    if [ "$(jq -r '.ok // 0' <<<"$start")" != "1" ]; then
        echo "[port $port] [!] check-host.net rejected the request (rate limit?). Try again later."
        return
    fi

    local req_id
    req_id=$(jq -r '.request_id' <<<"$start")

    # Russian node hostnames start with "ru".
    local ru_nodes
    ru_nodes=$(jq -r '.nodes | keys[]' <<<"$start" | grep -E '^ru' || true)

    if [ -z "$ru_nodes" ]; then
        echo "[port $port] [!] No Russian nodes were assigned by check-host.net this round. Re-run the script."
        return
    fi

    local ru_total
    ru_total=$(wc -l <<<"$ru_nodes" | tr -d ' ')

    # Poll results until all RU nodes report a concrete (non-null) result, or
    # we time out (~18s). A null value means that node is still testing.
    local result="{}"
    local attempt resolved
    for attempt in $(seq 1 12); do
        sleep 1.5
        result=$(curl -s -H "$ACCEPT" "${API}/check-result/${req_id}")
        resolved=$(jq -r '
            [ to_entries[] | select(.key|startswith("ru")) | select(.value != null) ] | length
        ' <<<"$result" 2>/dev/null || echo 0)
        if [ "${resolved:-0}" -ge "$ru_total" ]; then
            break
        fi
    done

    # Tally OK vs blocked across RU nodes.
    local ok_count fail_count
    ok_count=$(jq -r '
        [ to_entries[]
          | select(.key|startswith("ru"))
          | select(.value != null)
          | .value[0]
          | select(type=="object" and has("address")) ] | length
    ' <<<"$result" 2>/dev/null || echo 0)
    fail_count=$(jq -r '
        [ to_entries[]
          | select(.key|startswith("ru"))
          | select(.value != null)
          | .value[0]
          | select(type=="object" and has("error")) ] | length
    ' <<<"$result" 2>/dev/null || echo 0)

    echo "[port $port] RU nodes: ${ru_total}  |  reachable: ${ok_count}  |  blocked/timeout: ${fail_count}"

    if [ "${ok_count:-0}" -eq 0 ] && [ "${fail_count:-0}" -gt 0 ]; then
        echo "          -> UNREACHABLE from Russia. Looks like an IP/subnet/firewall block."
        overall_blocked=1
    elif [ "${ok_count:-0}" -gt 0 ] && [ "${fail_count:-0}" -gt 0 ]; then
        echo "          -> PARTIAL. Some Russian ISPs reach it, others don't (per-ISP filtering)."
    elif [ "${ok_count:-0}" -gt 0 ]; then
        echo "          -> Reachable from Russia at the TCP level."
    else
        echo "          -> Inconclusive (nodes did not report in time). Re-run."
    fi
    echo "          Detailed view: ${API}/check-tcp?host=${target}"
}

for port in "${PORTS[@]}"; do
    check_port "$port"
    echo ""
done

echo "== Interpretation =="
if [ "$overall_blocked" -eq 1 ]; then
    echo "- At least one port is UNREACHABLE from Russia at the TCP level."
    echo "  This is an IP / subnet / hosting-range block. Rotating Reality or SNI will NOT fix it."
    echo "  Action: move the server to a fresh IP (ideally a less-targeted provider), then re-run make init."
else
    echo "- TCP reachable from Russia. If clients still fail, it is a protocol / Reality / SNI issue:"
    echo "  Action: make sure clients use the XHTTP profile, then:"
    echo "    make rotate-reality DEST=<good-sni>:443 SNI=<good-sni>"
    echo "    make client-config USER=<name>"
fi
