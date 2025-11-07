#!/usr/bin/env bash

# Check to see if our hideen services are working!
# Run on the host machine with this command:
#   docker compose exec -ti monerod /test_hidden_services.sh

set -euo pipefail

get_node_height () {
  curl -fsS -o- -x "$1" "$2/get_info" | grep -oE '"height": [[:digit:]]+' | grep -oE '[[:digit:]]+'
}

TARGET_HEIGHT="$(curl -fs -o- 'http://127.0.0.1:18089/get_info' | grep -oE '"target_height": [[:digit:]]+' | grep -oE '[[:digit:]]+')"

if [ -f '/var/lib/tor/monerod/hostname' ]; then
  ONION_URL="$(cat '/var/lib/tor/monerod/hostname')"
  NODE_HEIGHT="$(get_node_height 'socks5h://172.31.255.250:9050' $ONION_URL:18089)"

  if [ -z "$NODE_HEIGHT" ]; then
    echo "ERROR: Encountered an error getting node details over Tor. Check your configuration."
  else
    echo "Tor hidden service details:"
    echo "  - URL: $ONION_URL:18089"
    echo "  - Height: $NODE_HEIGHT / $TARGET_HEIGHT"
  fi
else
  echo "WARNING: /var/lib/tor/monerod/hostname doesn't exist! Is Tor running?"
fi

I2P_URL="$(curl -fs 'http://172.31.255.251:7070/?page=i2p_tunnels' | grep 'monero-rpc' | grep -oE '[a-z0-9]+\.b32\.i2p')"

if [ -n "$I2P_URL" ]; then
  unset NODE_HEIGHT

  NODE_HEIGHT="$(get_node_height 'socks5h://172.31.255.251:4447' $I2P_URL:18089)"

  if [ -z "$NODE_HEIGHT" ]; then
    echo "ERROR: Encountered a problem fetching node details over I2P network. Check your configuration."
  else
    echo "I2P hidden service details:"
    echo "  - URL: $I2P_URL:18089"
    echo "  - Height: $NODE_HEIGHT / $TARGET_HEIGHT"
  fi
else
  echo "WARNING: Cannot get information about I2P tunnels! Is I2PD running?"
fi
