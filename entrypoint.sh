#!/bin/sh

# This script will exit immediately if any command fails.
set -e

# --- Configuration Validation ---
# This section ensures the user has provided all necessary environment variables.
# The script will fail with a helpful error message if any are missing.

# The name of the tunnel interface inside the container. Defaults to 'he-tunnel'.
HE_TUNNEL_IF=${HE_TUNNEL_IF:-he-tunnel}

# Use POSIX parameter expansion to check for mandatory variables.
# If a variable is unset or null, it prints the error message and the script exits.
: "${HE_CLIENT_IPV6:?Error: Required environment variable HE_CLIENT_IPV6 is not set. Example: 2001:470:c:def::2/64}"
: "${HE_ROUTED_PREFIX:?Error: Required environment variable HE_ROUTED_PREFIX is not set. Example: 2001:470:abcd:123::/64}"
: "${SOCKS_USER:?Error: Required environment variable SOCKS_USER is not set.}"
: "${SOCKS_PASS:?Error: Required environment variable SOCKS_PASS is not set.}"

echo "--- IPv6 Random Proxy Entrypoint ---"
echo "------------------------------------"

# --- Network Configuration ---
echo "[1/4] Configuring IPv6 address for tunnel interface..."
# Assign the HE.net client endpoint IPv6 address to the tunnel interface.
ip addr add "${HE_CLIENT_IPV6}" dev "${HE_TUNNEL_IF}"
echo "      Interface '${HE_TUNNEL_IF}' is now configured with ${HE_CLIENT_IPV6}."

echo "[2/4] Setting default IPv6 route..."
# Route all outgoing IPv6 traffic through the tunnel interface.
ip route add ::/0 dev "${HE_TUNNEL_IF}"
echo "      Default IPv6 route now points to '${HE_TUNNEL_IF}'."

echo "[3/4] Applying random source NAT (SNAT) rule..."
# This is the core feature:
# For any outgoing packet on the tunnel interface (-o), rewrite its source address (-j SNAT)
# to a random address (--random) from the provided routed prefix (--to-source).
ip6tables -t nat -A POSTROUTING -o "${HE_TUNNEL_IF}" -j SNAT --to-source "${HE_ROUTED_PREFIX}" --random
echo "      iptables rule installed to randomize outgoing IPs from prefix ${HE_ROUTED_PREFIX}."

echo "[4/4] Starting SOCKS5 proxy server..."

# --- Start the SOCKS5 Server ---
# 'exec' replaces the current shell process with the microsocks process.
# This makes microsocks the main process (PID 1) of the container, allowing it to
# receive signals correctly from Docker (e.g., for 'docker stop').
exec microsocks -u "${SOCKS_USER}" -p "${SOCKS_PASS}"
