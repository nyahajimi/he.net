#!/bin/sh
set -e

# --- Environment Variable Validation ---
echo "Validating environment variables..."
: "${HE_REMOTE_V4?Error: HE_REMOTE_V4 is not set.}"
: "${HE_LOCAL_V4?Error: HE_LOCAL_V4 is not set.}"
: "${HE_IPV6_ADDR?Error: HE_IPV6_ADDR is not set.}"
: "${SOCKS5_CREDENTIALS?Error: SOCKS5_CREDENTIALS must be set for security reasons. Format: user1:pass1,user2:pass2}"

# --- Set Default Values for Optional Variables ---
SOCKS5_PORT="${SOCKS5_PORT:-1080}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-300}"
INBOUND_STATIC_IPV6="${INBOUND_STATIC_IPV6:-}" 
NAT64_PREFIX="64:ff9b::/96"
TUNNEL_IF="he-ipv6"

# --- Helper Functions ---
validate_ipv6_in_subnet() {
  local subnet="$1"; local ip_to_check="$2";
  local subnet_prefix=$(echo "$subnet" | cut -d':' -f1-4);
  if ! echo "$ip_to_check" | grep -q "^${subnet_prefix}"; then
    echo "Error: Provided INBOUND_STATIC_IPV6 (${ip_to_check}) does not belong to the HE.net subnet (${subnet})." >&2; exit 1;
  fi
  echo "IPv6 address ${ip_to_check} validated successfully."
}

# --- Tunnel and Network Setup Functions ---
setup_tunnel() {
  local remote_v4="$1"; local local_v4="$2"; local inbound_addr="$3";

  echo "Setting up HE.net IPv6 tunnel (Remote: ${remote_v4}, Local: ${local_v4})..."
  ip link set "${TUNNEL_IF}" down 2>/dev/null || true
  ip tunnel del "${TUNNEL_IF}" 2>/dev/null || true

  # 【关键修改点】忽略 modprobe 的错误
  modprobe ipv6 || true
  modprobe sit || true
  
  ip tunnel add "${TUNNEL_IF}" mode sit remote "${remote_v4}" local "${local_v4}" ttl 255
  ip link set "${TUNNEL_IF}" up
  ip addr add "${HE_IPV6_ADDR}" dev "${TUNNEL_IF}"
  local primary_addr=$(echo "${HE_IPV6_ADDR}" | cut -d'/' -f1)
  if [ "$inbound_addr" != "$primary_addr" ]; then
    echo "Assigning dedicated inbound static address ${inbound_addr} to interface."
    ip addr add "${inbound_addr}/128" dev "${TUNNEL_IF}"
  fi
  ip route add ::/0 dev "${TUNNEL_IF}"
  sysctl -w net.ipv6.conf.all.use_tempaddr=2
  sysctl -w net.ipv6.conf.default.use_tempaddr=2
  sysctl -w "net.ipv6.conf.${TUNNEL_IF}.use_tempaddr=2"
  echo "Tunnel ${TUNNEL_IF} is up and configured."
}

dynamic_ip_updater() {
  local last_known_ip=$(cat /tmp/current_ipv4)
  echo "Dynamic IP update service started. Checking every ${UPDATE_INTERVAL} seconds."
  while true; do
    sleep "${UPDATE_INTERVAL}"
    local current_public_ip=$(curl -4s --fail https://api.ipify.org || echo "")
    if [ -n "$current_public_ip" ] && [ "$current_public_ip" != "$last_known_ip" ]; then
      echo "IP address has changed from ${last_known_ip} to ${current_public_ip}. Updating..."
      curl -s "${HE_UPDATE_URL}"
      setup_tunnel "${HE_REMOTE_V4}" "${current_public_ip}" "$STATIC_INBOUND_ADDR"
      last_known_ip="$current_public_ip"
      echo "$last_known_ip" > /tmp/current_ipv4
    fi
  done
}

# --- Main Execution Logic ---
if [ "$HE_LOCAL_V4" = "auto" ]; then
  echo "HE_LOCAL_V4 is 'auto', detecting public IP..."
  HE_LOCAL_V4=$(curl -4s --fail https://api.ipify.org);
  if [ -z "$HE_LOCAL_V4" ]; then echo "Error: Failed to auto-detect public IPv4." >&2; exit 1; fi
  echo "Public IP detected: ${HE_LOCAL_V4}"
fi
STATIC_INBOUND_ADDR=""
if [ -z "$INBOUND_STATIC_IPV6" ]; then
    STATIC_INBOUND_ADDR=$(echo "${HE_IPV6_ADDR}" | cut -d'/' -f1)
    echo "INBOUND_STATIC_IPV6 not set, defaulting to tunnel endpoint: ${STATIC_INBOUND_ADDR}"
elif [ "$INBOUND_STATIC_IPV6" = "RANDOM" ] || [ "$INBOUND_STATIC_IPV6" = "::" ]; then
    echo "Generating a random static IPv6 address for inbound traffic..."
    IPV6_PREFIX=$(echo "${HE_IPV6_ADDR}" | sed 's@::.*/64@::@')
    RANDOM_SUFFIX=$(printf '%x:%x:%x:%x' "0x$(openssl rand -hex 2)" "0x$(openssl rand -hex 2)" "0x$(openssl rand -hex 2)" "0x$(openssl rand -hex 2)")
    STATIC_INBOUND_ADDR="${IPV6_PREFIX}${RANDOM_SUFFIX}"
    echo "==================================================================="
    echo ">>  Random Inbound IPv6 Address: ${STATIC_INBOUND_ADDR}"
    echo "==================================================================="
else
    validate_ipv6_in_subnet "${HE_IPV6_ADDR}" "${INBOUND_STATIC_IPV6}"
    STATIC_INBOUND_ADDR="$INBOUND_STATIC_IPV6"
    echo "Using user-defined static IPv6 for inbound traffic: ${STATIC_INBOUND_ADDR}"
fi
setup_tunnel "${HE_REMOTE_V4}" "${HE_LOCAL_V4}" "$STATIC_INBOUND_ADDR"
if [ -n "$HE_UPDATE_URL" ]; then
  echo "${HE_LOCAL_V4}" > /tmp/current_ipv4
  dynamic_ip_updater &
fi
echo "Starting background services (Unbound and Tayga)..."
unbound &
tayga --mktun &
sleep 2 
ip link set nat64 up
ip route add "${NAT64_PREFIX}" dev nat64
{ echo "nameserver ::1"; echo "nameserver 2606:4700:4700::1111"; } > /etc/resolv.conf
echo "Constructing Gost command with mandatory authentication..."
GOST_CMD="gost"
echo "$SOCKS5_CREDENTIALS" | tr ',' '\n' | while read -r cred; do
    if [ -n "$cred" ]; then
      GOST_CMD="$GOST_CMD -L socks5://${cred}@[::]:${SOCKS5_PORT}"
    fi
done
echo "Starting Gost v3 SOCKS5 proxy..."
exec su-exec appuser $GOST_CMD
