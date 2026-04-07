#!/bin/bash
set -euo pipefail

echo "======================================"
echo "    Resetting Xray Server Firewall    "
echo "======================================"

# Remove the jump rule from DOCKER-USER
# Loop to ensure multiple insertions are completely eradicated
while sudo iptables -D DOCKER-USER -j VPN-FIREWALL >/dev/null 2>&1; do
    echo "[*] Removed jump to VPN-FIREWALL from DOCKER-USER."
done

# Flush and delete our custom chain
if sudo iptables -nL VPN-FIREWALL >/dev/null 2>&1; then
    sudo iptables -F VPN-FIREWALL
    sudo iptables -X VPN-FIREWALL
    echo "[*] VPN-FIREWALL chain flushed and deleted."
else
    echo "[*] VPN-FIREWALL chain does not exist, nothing to delete."
fi

echo "[+] Firewall successfully reverted to Docker defaults."
