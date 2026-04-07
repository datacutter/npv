#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load environment configuration
if [ ! -f ".env" ]; then
    echo "Error: .env file not found. Run make init first."
    exit 1
fi
source .env

ENABLE_FIREWALL=${ENABLE_FIREWALL:-false}
FIREWALL_MODE=${FIREWALL_MODE:-balanced}

if [ "$ENABLE_FIREWALL" != "true" ]; then
    echo "Firewall is explicitly disabled in .env (ENABLE_FIREWALL=$ENABLE_FIREWALL)."
    echo "Run 'make firewall-reset' to ensure no leftover rules exist, and exit."
    exit 0
fi

echo "======================================"
echo "    Applying Xray Server Firewall     "
echo "    Mode: $FIREWALL_MODE              "
echo "======================================"

# Always reset first to ensure idempotency and no rule duplication
echo "[*] Resetting existing DOCKER-USER rules..."
bash scripts/reset-firewall.sh

echo "[*] Applying rules to DOCKER-USER chain..."

# By default, Docker traffic goes through DOCKER-USER.
# We use a custom sub-chain "VPN-FIREWALL" for neatness.
if ! sudo iptables -nL VPN-FIREWALL >/dev/null 2>&1; then
    sudo iptables -N VPN-FIREWALL
fi

# Clear our sub-chain
sudo iptables -F VPN-FIREWALL

# Divert forward traffic originating from the Xray subnet to our chain
# (Assuming typical Docker bridge, but to be sure, we apply to all FORWARDing out of Docker bridge)
# "DOCKER-USER" chain handles all routed traffic involving Docker.
sudo iptables -I DOCKER-USER -j VPN-FIREWALL

# Rule 0: Always allow established and related connections (Return traffic)
sudo iptables -A VPN-FIREWALL -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# We skip host traffic filtering on INPUT because DOCKER-USER deals strictly with forwarded/docker traffic.
# The host's protection (SSH, etc.) is handled by UFW.

if [ "$FIREWALL_MODE" == "balanced" ]; then
    echo "[+] Mode: balanced - Blocking known Torrent ports."
    
    # Block standard torrent ports (TCP and UDP)
    sudo iptables -A VPN-FIREWALL -p tcp --dport 6881:6999 -j DROP
    sudo iptables -A VPN-FIREWALL -p udp --dport 6881:6999 -j DROP

    # Allow everything else routed from Docker
    sudo iptables -A VPN-FIREWALL -j RETURN

elif [ "$FIREWALL_MODE" == "strict" ]; then
    echo "[+] Mode: strict - Applying whitelist approach."
    
    # Allow DNS (UDP and TCP)
    sudo iptables -A VPN-FIREWALL -p udp --dport 53 -j ACCEPT
    sudo iptables -A VPN-FIREWALL -p tcp --dport 53 -j ACCEPT
    
    # Allow target routing (HTTP, HTTPS / TCP fallback QUIC)
    sudo iptables -A VPN-FIREWALL -p tcp --dport 80 -j ACCEPT
    sudo iptables -A VPN-FIREWALL -p tcp --dport 443 -j ACCEPT
    
    # Note: QUIC (UDP 443) is INTENTIONALLY DROPPED.
    # This mitigates heavy UDP P2P/torrent traffic while forcing apps (YouTube, Socials) 
    # to seamlessly fallback to TCP 443 (HTTPS) which is highly effective and safe.
    
    # Drop everything else
    sudo iptables -A VPN-FIREWALL -j DROP
else
    echo "Error: Unknown FIREWALL_MODE: $FIREWALL_MODE. Use 'balanced' or 'strict'."
    exit 1
fi

echo "[+] Firewall rules successfully applied."
