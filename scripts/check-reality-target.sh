#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

WARN_ONLY=false
if [ "${1:-}" = "--warn-only" ]; then
    WARN_ONLY=true
    shift
fi

DEST=${1:-${REALITY_DEST:-}}
SNI=${2:-${REALITY_SERVER_NAME:-}}

if [ -z "$DEST" ] || [ -z "$SNI" ]; then
    if [ -f ".env" ]; then
        # shellcheck disable=SC1091
        source .env
        DEST=${DEST:-${REALITY_DEST:-}}
        SNI=${SNI:-${REALITY_SERVER_NAME:-}}
    fi
fi

fail() {
    if [ "$WARN_ONLY" = true ]; then
        echo "[!] Reality target check warning: $*"
        exit 0
    fi

    echo "Error: $*"
    exit 1
}

warn() {
    echo "[!] $*"
}

if [ -z "$DEST" ] || [ -z "$SNI" ]; then
    fail "REALITY_DEST and REALITY_SERVER_NAME are required."
fi

if [[ "$DEST" != *:* ]]; then
    fail "REALITY_DEST must include a port, for example www.microsoft.com:443."
fi

DEST_HOST=${DEST%:*}
DEST_PORT=${DEST##*:}

if [ -z "$DEST_HOST" ] || [ -z "$DEST_PORT" ] || ! [[ "$DEST_PORT" =~ ^[0-9]+$ ]]; then
    fail "REALITY_DEST has invalid host:port format: $DEST"
fi

if [ "$DEST_HOST" != "$SNI" ]; then
    warn "REALITY_DEST host ($DEST_HOST) and REALITY_SERVER_NAME ($SNI) differ. This only works if SNI is present in the target certificate SAN."
fi

if ! command -v openssl >/dev/null 2>&1; then
    fail "openssl is not installed; cannot validate Reality target TLS profile."
fi

echo "[*] Checking Reality target $DEST with SNI $SNI ..."

TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(timeout 15)
fi

OUTPUT=$(
    "${TIMEOUT_CMD[@]}" openssl s_client \
        -connect "$DEST" \
        -servername "$SNI" \
        -verify_hostname "$SNI" \
        -tls1_3 \
        -alpn h2 \
        </dev/null 2>&1
) || fail "TLS handshake failed for $DEST with SNI $SNI."

if ! grep -q "Verify return code: 0 (ok)" <<<"$OUTPUT"; then
    fail "certificate verification failed for SNI $SNI."
fi

if ! grep -q "TLSv1.3" <<<"$OUTPUT"; then
    fail "$DEST did not negotiate TLS 1.3."
fi

if grep -q "ALPN protocol: h2" <<<"$OUTPUT"; then
    echo "[+] Reality target OK: valid certificate, TLS 1.3, ALPN h2."
else
    warn "$DEST negotiated TLS 1.3 but did not confirm ALPN h2. Prefer a target with HTTP/2 support."
fi
