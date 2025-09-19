#!/bin/sh

set -e

# --- Configuration Validation ---
HE_TUNNEL_IF=${HE_TUNNEL_IF:-he-tunnel}
: "${HE_CLIENT_IPV6:?Error: Required environment variable HE_CLIENT_IPV6 is not set.}"
: "${HE_ROUTED_PREFIX:?Error: Required environment variable HE_ROUTED_PREFIX is not set.}"
: "${SOCKS_USER:?Error: Required environment variable SOCKS_USER is not set.}"
: "${SOCKS_PASS:?Error: Required environment variable SOCKS_PASS is not set.}"

echo "--- IPv6 Random Proxy Entrypoint ---"
echo "------------------------------------"

# --- Network Configuration ---
echo "[1/5] Configuring IPv6 address for tunnel interface..."
ip addr add "${HE_CLIENT_IPV6}" dev "${HE_TUNNEL_IF}"

echo "[2/5] Bringing tunnel interface up..."
ip link set "${HE_TUNNEL_IF}" up

echo "[3/5] Setting default IPv6 route..."
ip route add ::/0 dev "${HE_TUNNEL_IF}"

echo "[4/5] Applying random source NAT (SNAT) rule..."
# Extract the network part from the prefix (e.g., 2001:470:c:def::)
NETWORK_PART=$(echo "${HE_ROUTED_PREFIX}" | cut -d'/' -f1 | sed 's/::.*$/::/')
# This is the corrected command using a valid range for --to-source
ip6tables -t nat -A POSTROUTING -o "${HE_TUNNEL_IF}" -j SNAT --to-source "${NETWORK_PART}2-${NETWORK_PART}ffff:ffff:ffff:ffff" --random
echo "      iptables rule installed to randomize outgoing IPs."

echo "[5/5] Starting SOCKS5 proxy server..."

exec microsocks -u "${SOCKS_USER}" -p "${SOCKS_PASS}"
