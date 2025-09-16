#!/bin/sh
set -e

# --- Environment Variable Validation ---
echo "Validating environment variables..."
: "${HE_REMOTE_V4?Error: HE_REMOTE_V4 is not set. (HE.net server IPv4 address)}"
: "${HE_LOCAL_V4?Error: HE_LOCAL_V4 is not set. (Set to 'auto' for dynamic detection)}"
: "${HE_IPV6_ADDR?Error: HE_IPV6_ADDR is not set. (Client IPv6 address from HE.net, e.g., 2001:470:xxx::2/64)}"

# --- Set Default Values for Optional Variables ---
SOCKS5_PORT="${SOCKS5_PORT:-1080}"
SOCKS5_USER="${SOCKS5_USER:-}"
SOCKS5_PASS="${SOCKS5_PASS:-}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-300}"
NAT64_PREFIX="64:ff9b::/96"
TUNNEL_IF="he-ipv6"

# --- Function to setup or restart the tunnel ---
# Accepts two arguments: $1=remote_v4, $2=local_v4
setup_tunnel() {
  local remote_v4="$1"
  local local_v4="$2"

  echo "Setting up HE.net IPv6 tunnel (Remote: ${remote_v4}, Local: ${local_v4})..."
  
  ip link set "${TUNNEL_IF}" down 2>/dev/null || true
  ip tunnel del "${TUNNEL_IF}" 2>/dev/null || true

  modprobe ipv6; modprobe sit

  ip tunnel add "${TUNNEL_IF}" mode sit remote "${remote_v4}" local "${local_v4}" ttl 255
  ip link set "${TUNNEL_IF}" up
  ip addr add "${HE_IPV6_ADDR}" dev "${TUNNEL_IF}"
  ip route add ::/0 dev "${TUNNEL_IF}"

  # Use sysctl, the standard and safer way to set kernel parameters
  sysctl -w net.ipv6.conf.all.use_tempaddr=2
  sysctl -w net.ipv6.conf.default.use_tempaddr=2
  sysctl -w "net.ipv6.conf.${TUNNEL_IF}.use_tempaddr=2"

  echo "Tunnel ${TUNNEL_IF} is up and configured."
}

# --- Function to handle Dynamic IP updates in the background ---
dynamic_ip_updater() {
  local last_known_ip
  last_known_ip=$(cat /tmp/current_ipv4)

  echo "Dynamic IP update service started. Checking every ${UPDATE_INTERVAL} seconds."
  
  while true; do
    sleep "${UPDATE_INTERVAL}"
    local current_public_ip
    current_public_ip=$(curl -4s --fail https://api.ipify.org || echo "")
    
    if [ -n "$current_public_ip" ] && [ "$current_public_ip" != "$last_known_ip" ]; then
      echo "IP address has changed from ${last_known_ip} to ${current_public_ip}. Updating..."
      
      # Notify he.net of the IP change
      curl -s "${HE_UPDATE_URL}"
      
      # THE CRITICAL BUG FIX: Pass the new IP to the setup function
      setup_tunnel "${HE_REMOTE_V4}" "${current_public_ip}"
      
      last_known_ip="$current_public_ip"
      echo "$last_known_ip" > /tmp/current_ipv4
    fi
  done
}

# --- Main Execution Logic ---

# Auto-detect public IP if HE_LOCAL_V4 is set to 'auto'
if [ "$HE_LOCAL_V4" = "auto" ]; then
  echo "HE_LOCAL_V4 is 'auto', detecting public IP..."
  HE_LOCAL_V4=$(curl -4s --fail https://api.ipify.org)
  if [ -z "$HE_LOCAL_V4" ]; then
    echo "Error: Failed to auto-detect public IPv4 address." >&2; exit 1
  fi
  echo "Public IP detected: ${HE_LOCAL_V4}"
fi

# Initial tunnel setup
setup_tunnel "${HE_REMOTE_V4}" "${HE_LOCAL_V4}"

# If dynamic IP mode, start updater in background
if [ -n "$HE_UPDATE_URL" ]; then
  echo "${HE_LOCAL_V4}" > /tmp/current_ipv4
  dynamic_ip_updater &
fi

# Start DNS64 service
echo "Starting Unbound (DNS64)..."
unbound &

# Start NAT64 service (simplified and correct logic)
echo "Starting Tayga (NAT64)..."
tayga --mktun &
sleep 2 # Give time for the device to be created
ip link set nat64 up
ip route add "${NAT64_PREFIX}" dev nat64

# Configure container's DNS resolver with a robust fallback
echo "Configuring DNS resolver..."
{
  echo "nameserver ::1"; # Primary: our internal DNS64
  echo "nameserver 2606:4700:4700::1111"; # Secondary: Cloudflare IPv6 DNS
} > /etc/resolv.conf

# Construct correct Gost v3 command
GOST_CMD="gost -L socks5://[::]:${SOCKS5_PORT}"
if [ -n "$SOCKS5_USER" ] && [ -n "$SOCKS5_PASS" ]; then
  echo "SOCKS5 proxy will start with authentication."
  GOST_CMD="gost -L socks5://${SOCKS5_USER}:${SOCKS5_PASS}@[::]:${SOCKS5_PORT}"
else
  echo "SOCKS5 proxy will start without authentication."
fi

echo "Starting Gost v3 SOCKS5 proxy on port ${SOCKS5_PORT}..."
exec $GOST_CMD
