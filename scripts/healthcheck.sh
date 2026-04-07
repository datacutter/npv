#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=> Doing Healthcheck"

if ! docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[!] ERROR: Xray docker container is NOT running."
    exit 1
fi
echo "[+] Xray container is running."

# We test with nc if the container answers on 443 locally
# Using a temp busybox/alpine because Host might not have nc
if docker run --rm --network container:xray alpine sh -c "nc -z 127.0.0.1 443"; then
    echo "[+] Xray is listening on port 443."
else
    echo "[!] ERROR: Xray is NOT listening on port 443 inside container!"
    exit 1
fi

echo "[+] Xray Config Validation (run -test):"
if docker exec xray xray run -test -confdir /etc/xray; then
    echo "[+] Config is structurally valid."
else
    echo "[!] ERROR: Xray config has errors!"
    exit 1
fi

echo "[+] Healthcheck PASSED!"
exit 0
