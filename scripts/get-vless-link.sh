#!/bin/bash
set -e

if [ ! -f ".env" ]; then
    echo "Error: .env not found. Please run init.sh first."
    exit 1
fi

export $(grep -v '^#' .env | xargs)
XRAY_PORT_ALT=${XRAY_PORT_ALT:-8443}

URLEncoded_REALITY_SERVER_NAME=$(echo "$REALITY_SERVER_NAME" | sed 's/ /%20/g')

PRIMARY_VLESS_LINK="vless://${XRAY_UUID}@${SERVER_IP}:${XRAY_PORT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#Xray_Reality"
ALT_VLESS_LINK="vless://${XRAY_UUID}@${SERVER_IP}:${XRAY_PORT_ALT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#Xray_Reality_8443"

echo "========================================="
echo "      YOUR PRIMARY VLESS REALITY LINK    "
echo "========================================="
echo ""
echo "$PRIMARY_VLESS_LINK"
echo ""
echo "========================================="
echo "      YOUR FALLBACK VLESS REALITY LINK   "
echo "========================================="
echo ""
echo "$ALT_VLESS_LINK"
echo ""
echo "========================================="
