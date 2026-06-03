#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET_IMAGE="ghcr.io/xtls/xray-core:26.6.1"
TARGET_ALT_PORT="8443"

ensure_env_default() {
    local key=$1
    local value=$2

    if grep -q "^${key}=" .env; then
        return
    fi

    printf '\n%s=%s\n' "$key" "$value" >> .env
    echo "[+] $key added to .env"
}

if [ ! -f ".env" ]; then
    echo "Error: .env not found. Run 'make init' first."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed or not in PATH."
    exit 1
fi

CURRENT_IMAGE=$(grep '^XRAY_IMAGE=' .env | cut -d= -f2- || true)
if grep -q '^XRAY_IMAGE=' .env; then
    case "$CURRENT_IMAGE" in
        ""|teddysun/xray:*|ghcr.io/xtls/xray-core:*)
            sed -i "s|^XRAY_IMAGE=.*|XRAY_IMAGE=$TARGET_IMAGE|g" .env
            echo "[+] XRAY_IMAGE set to $TARGET_IMAGE"
            ;;
        *)
            echo "[!] XRAY_IMAGE uses a custom image ($CURRENT_IMAGE). Leaving it unchanged."
            ;;
    esac
else
    echo "XRAY_IMAGE=$TARGET_IMAGE" >> .env
    echo "[+] XRAY_IMAGE added to .env"
fi

if grep -q '^XRAY_PORT_ALT=' .env; then
    CURRENT_ALT_PORT=$(grep '^XRAY_PORT_ALT=' .env | cut -d= -f2- || true)
    if [ -z "$CURRENT_ALT_PORT" ]; then
        sed -i "s|^XRAY_PORT_ALT=.*|XRAY_PORT_ALT=$TARGET_ALT_PORT|g" .env
        echo "[+] XRAY_PORT_ALT set to $TARGET_ALT_PORT"
    fi
else
    printf '\nXRAY_PORT_ALT=%s\n' "$TARGET_ALT_PORT" >> .env
    echo "[+] XRAY_PORT_ALT added to .env"
fi

ensure_env_default REALITY_FINGERPRINT "chrome"
ensure_env_default REALITY_SPIDER_X "/"

echo "[*] Re-rendering Xray config..."
bash scripts/render-config.sh

echo "[*] Pulling updated Xray image..."
docker compose pull xray

echo "[*] Recreating xray service..."
docker compose up -d xray

echo "[*] Verifying xray service..."
bash scripts/healthcheck.sh

echo ""
echo "[!] Reminder: update client apps to the latest available release on each device."
echo "    For Reality-based links this is important on Android/iPhone clients too."
echo "[!] If the current server is already blocked in Russia, run:"
echo "    make rotate-reality DEST=www.microsoft.com:443 SNI=www.microsoft.com"
echo "    Then re-issue links with: make client-config USER=<username>"
