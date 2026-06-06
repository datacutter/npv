#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "======================================"
echo " Xray Connectivity Diagnostics"
echo "======================================"

if [ ! -f ".env" ]; then
    echo "[!] .env not found. Run make init first."
    exit 1
fi

# shellcheck disable=SC1091
source .env

echo ""
echo "== Environment summary =="
echo "SERVER_IP=${SERVER_IP:-}"
echo "REALITY_DEST=${REALITY_DEST:-}"
echo "REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-}"
echo "REALITY_FINGERPRINT=${REALITY_FINGERPRINT:-}"
echo "REALITY_FINGERPRINTS=${REALITY_FINGERPRINTS:-}"
echo "XRAY_PORT=${XRAY_PORT:-443}"
echo "XRAY_PORT_ALT=${XRAY_PORT_ALT:-8443}"
echo "XRAY_PORT_XHTTP=${XRAY_PORT_XHTTP:-9443}"
echo "XHTTP_PATH=${XHTTP_PATH:-}"
echo "XHTTP_MODE=${XHTTP_MODE:-auto}"
echo "XRAY_IMAGE=${XRAY_IMAGE:-ghcr.io/xtls/xray-core:26.6.1}"

echo ""
echo "== Docker status =="
docker compose ps || true

echo ""
echo "== Rendered VLESS inbounds =="
if [ -f "xray/config.json" ]; then
    jq -r '
      .inbounds[]
      | select(.protocol == "vless")
      | [
          (.tag // "-"),
          (.port | tostring),
          (.streamSettings.network // "tcp"),
          (.streamSettings.security // "none"),
          (.streamSettings.xhttpSettings.path // "-")
        ]
      | @tsv
    ' xray/config.json
else
    echo "[!] xray/config.json not found."
fi

echo ""
echo "== Local healthcheck =="
if bash scripts/healthcheck.sh; then
    echo "[+] Local Xray healthcheck passed."
else
    echo "[!] Local Xray healthcheck failed. Fix server/config before testing from clients."
fi

echo ""
echo "== Host listening TCP ports =="
if command -v ss >/dev/null 2>&1; then
    ss -ltnp | grep -E ":(443|8443|9443)[[:space:]]" || true
else
    echo "[!] ss not installed; skipping host port listing."
fi

echo ""
echo "== UFW status =="
if command -v sudo >/dev/null 2>&1 && command -v ufw >/dev/null 2>&1; then
    sudo -n ufw status numbered || echo "[!] Cannot read UFW status without interactive sudo."
else
    echo "[!] ufw not installed; skipping."
fi

echo ""
echo "== Reality target check =="
bash scripts/check-reality-target.sh --warn-only "${REALITY_DEST:-}" "${REALITY_SERVER_NAME:-}"

echo ""
echo "== Recent Xray logs =="
docker compose logs --tail=80 xray || true

echo ""
echo "== Interpretation =="
echo "- If healthcheck fails: server/config problem."
echo "- If healthcheck passes but users in Russia cannot connect: likely DPI/IP/ASN/fingerprint filtering."
echo "- If TCP 443 fails but XHTTP 9443 works: keep XHTTP as the primary profile."
echo "- If no profile works from multiple Russian ISPs while logs show no attempts: likely IP/subnet block."
echo "- If attempts appear in logs but stall: try another fingerprint first, then rotate Reality."
