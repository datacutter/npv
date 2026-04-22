#!/bin/bash
# tune-kernel.sh — Enable TCP BBR and optimize kernel network parameters
# for maximum VPN throughput and minimum latency.
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-vpn-tuning.conf"

echo "======================================"
echo "   Kernel Network Tuning for VPN      "
echo "======================================"

# Check if BBR is already active
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
if [ "$CURRENT_CC" == "bbr" ]; then
    echo "[!] TCP BBR is already active. Checking other parameters..."
fi

cat > "$SYSCTL_FILE" << 'EOF'
# === VPN Performance Tuning ===
# Applied by: make tune-kernel

# --- TCP BBR Congestion Control ---
# BBR improves throughput by 30-50% on lossy/high-latency links
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP Buffer Sizes (16MB max) ---
# Allows higher throughput per connection on fast links
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- Connection Handling ---
# Prevent packet drops during traffic bursts
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096

# Reuse TIME_WAIT sockets faster (safe for proxy servers)
net.ipv4.tcp_tw_reuse = 1
EOF

sysctl -p "$SYSCTL_FILE" > /dev/null

# Verify BBR is active
VERIFY_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
if [ "$VERIFY_CC" == "bbr" ]; then
    echo "[+] TCP BBR: ACTIVE"
else
    echo "[!] WARNING: TCP BBR could not be activated (kernel may not support it)."
    echo "    Current: $VERIFY_CC"
fi

echo "[+] Buffer sizes: rmem_max=$(sysctl -n net.core.rmem_max), wmem_max=$(sysctl -n net.core.wmem_max)"
echo "[+] Backlog: netdev_max_backlog=$(sysctl -n net.core.netdev_max_backlog), somaxconn=$(sysctl -n net.core.somaxconn)"
echo "[+] Kernel tuning applied successfully."
