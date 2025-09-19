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
echo "[1/4] Configuring IPv6 address for tunnel interface..."
ip addr add "${HE_CLIENT_IPV6}" dev "${HE_TUNNEL_IF}"
echo "      Interface '${HE_TUNNEL_IF}' is now configured with ${HE_CLIENT_IPV6}."

# !!! --- THIS IS THE FIX --- !!!
# When an interface is moved to a new network namespace, it is brought down.
# We must bring it back up before we can use it for routing.
echo "[2/4] Bringing tunnel interface up..."
ip link set "${HE_TUNNEL_IF}" up
echo "      Interface '${HE_TUNNEL_IF}' is now UP."

echo "[3/4] Setting default IPv6 route..."
ip route add ::/0 dev "${HE_TUNNEL_IF}"
echo "      Default IPv6 route now points to '${HE_TUNNEL_IF}'."

echo "[4/4] Applying random source NAT (SNAT) rule..."
ip6tables -t nat -A POSTROUTING -o "${HE_TUNNEL_IF}" -j SNAT --to-source "${HE_ROUTED_PREFIX}" --random
echo "      iptables rule installed to randomize outgoing IPs from prefix ${HE_ROUTED_PREFIX}."

echo "[5/5] Starting SOCKS5 proxy server..."

exec microsocks -u "${SOCKS_USER}" -p "${SOCKS_PASS}"
