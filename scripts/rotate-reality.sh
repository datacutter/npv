#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEST_ARG=${DEST:-${1:-}}
SNI_ARG=${SNI:-${2:-}}

if [ ! -f ".env" ]; then
    echo "[+] .env not found. Copying .env.example ..."
    cp .env.example .env
fi

# shellcheck disable=SC1091
source .env

if [ -n "$DEST_ARG" ]; then
    DEST=$DEST_ARG
else
    DEST=${REALITY_DEST:-}
fi

if [ -n "$SNI_ARG" ]; then
    SNI=$SNI_ARG
elif [ -n "$DEST_ARG" ]; then
    SNI=${DEST%:*}
else
    SNI=${REALITY_SERVER_NAME:-}
fi

if [ -z "$DEST" ]; then
    echo "Usage: make rotate-reality DEST=www.microsoft.com:443 SNI=www.microsoft.com"
    exit 1
fi

if [ -z "$SNI" ]; then
    SNI=${DEST%:*}
fi

set_env() {
    local key=$1
    local value=$2
    local tmp
    tmp=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN { found = 0 }
        $0 ~ "^" key "=" {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (found == 0) {
                print key "=" value
            }
        }
    ' .env > "$tmp"

    mv "$tmp" .env
}

bash scripts/check-reality-target.sh "$DEST" "$SNI"

echo "[*] Updating Reality target in .env ..."
set_env REALITY_DEST "$DEST"
set_env REALITY_SERVER_NAME "$SNI"

if ! grep -q '^REALITY_FINGERPRINT=' .env; then
    set_env REALITY_FINGERPRINT "chrome"
fi

if ! grep -q '^REALITY_SPIDER_X=' .env; then
    set_env REALITY_SPIDER_X "/"
fi

echo "[*] Regenerating Reality private/public key pair and short ID ..."
bash scripts/generate-secrets.sh --force

echo "[*] Rendering Xray config with rotated Reality settings ..."
bash scripts/render-config.sh

echo ""
echo "[+] Reality rotation complete."
echo "[!] Existing VLESS import links are now stale because pbk/sid/SNI changed."
echo "    Re-issue client links with: make client-config USER=<username>"
