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

# --- THIS IS THE ROBUST FIX FOR THE RACE CONDITION ---
# Wait patiently for the tunnel interface to be moved into this container.
echo "[1/6] Waiting for tunnel interface '${HE_TUNNEL_IF}' to appear..."
while [ ! -d "/sys/class/net/${HE_TUNNEL_IF}" ]; do
  echo "      '${HE_TUNNEL_IF}' not found, sleeping for 1 second..."
  sleep 1
done
echo "      Interface '${HE_TUNNEL_IF}' found!"


# --- Network Configuration ---
echo "[2/6] Configuring IPv6 address for tunnel interface..."
ip addr add "${HE_CLIENT_IPV6}" dev "${HE_TUNNEL_IF}"

echo "[3/6] Bringing tunnel interface up..."
ip link set "${HE_TUNNEL_IF}" up

echo "[4/6] Setting default IPv6 route..."
ip route add ::/0 dev "${HE_TUNNEL_IF}"

echo "[5/6] Applying random source NAT (SNAT) rule..."
NETWORK_PREFIX=$(echo "${HE_ROUTED_PREFIX}" | cut -d':' -f1-4)
ip6tables -t nat -A POST_ROUTING -o "${HE_TUNNEL_IF}" -j SNAT --to-source "${NETWORK_PREFIX}::2-${NETWORK_PREFIX}:ffff:ffff:ffff:ffff" --random
echo "      iptables rule installed to randomize outgoing IPs."

echo "[6/6] Starting SOCKS5 proxy server..."

exec microsocks -u "${SOCKS_USER}" -p "${SOCKS_PASS}"
