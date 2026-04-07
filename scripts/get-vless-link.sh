#!/bin/bash
set -e

if [ ! -f ".env" ]; then
    echo "Error: .env not found. Please run init.sh first."
    exit 1
fi

export $(grep -v '^#' .env | xargs)

URLEncoded_REALITY_SERVER_NAME=$(echo "$REALITY_SERVER_NAME" | sed 's/ /%20/g')

VLESS_LINK="vless://${XRAY_UUID}@${SERVER_IP}:${XRAY_PORT}?security=reality&encryption=none&pbk=${XRAY_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${URLEncoded_REALITY_SERVER_NAME}&sid=${XRAY_SHORT_ID}#Xray_Reality"

echo "========================================="
echo "        YOUR VLESS REALITY LINK          "
echo "========================================="
echo ""
echo "$VLESS_LINK"
echo ""
echo "========================================="
