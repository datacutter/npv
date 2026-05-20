#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

XRAY_CONTAINER_IMAGE=""
xray_exec() {
    if [ -z "$XRAY_CONTAINER_IMAGE" ]; then
        XRAY_CONTAINER_IMAGE=$(docker inspect -f '{{.Config.Image}}' xray 2>/dev/null || true)
    fi

    if [[ "$XRAY_CONTAINER_IMAGE" == ghcr.io/xtls/xray-core:* ]]; then
        docker exec xray /usr/local/bin/xray "$@"
    else
        docker exec xray xray "$@"
    fi
}

echo "=> Doing Healthcheck"

if ! docker ps --format '{{.Names}}' | grep -Eq "^xray$"; then
    echo "[!] ERROR: Xray docker container is NOT running."
    exit 1
fi
echo "[+] Xray container is running."

for port in 443 8443; do
    # We test with nc if the container answers locally.
    # Using a temp alpine image because the host may not have nc.
    if docker run --rm --network container:xray alpine sh -c "nc -z 127.0.0.1 $port"; then
        echo "[+] Xray is listening on port $port."
    else
        echo "[!] ERROR: Xray is NOT listening on port $port inside container!"
        exit 1
    fi
done

echo "[+] Xray Config Validation (run -test):"
if xray_exec run -test -config /etc/xray/config.json; then
    echo "[+] Config is structurally valid."
else
    echo "[!] ERROR: Xray config has errors!"
    exit 1
fi

echo "[+] Healthcheck PASSED!"
exit 0
