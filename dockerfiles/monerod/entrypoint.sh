#!/usr/bin/env bash

set -ex

log_msg () {
  local caller="$1"
  local level="${2:-info}"
  local msg="$3"

  if [ -z "$caller" ] || [ -z "$msg" ]; then
    log_error "log_error" "Function was called with no caller or message!"
    return 1
  fi

  local stamp="$(date --iso-8601=seconds | sed -E 's/\+[[:digit:]]{1,2}:[[:digit:]]{1,2}$//' | sed 's/T/ /')"

  local formatted_msg="$stamp\t$caller\t$level\t$msg"

  case "$level" in
    info)
      echo -e "$formatted_msg"
      ;;

    warn|warning|error)
      echo -e "$formatted_msg" >&2
      ;;

    *)
      log_error "$0" "Invalid level $level! Expected [info|warn|warning|error]"
      return 2
      ;;
  esac

  return 0
}

set_conf_option () {
  # USAGE: set_conf_option <section ID> <section content|#> [show changes] [lines to grep]
  #        Pass a single '#' for <section content> to disable the directive
  #        Pass '-1' to [lines to grep] to disable grep output

  local section="$1"
  local content="$2"

  declare -i grep_lines="${3:-2}"

  if [ -z "$section" ] || [ -z "$content" ]; then
    log_msg "$0" 'error' 'Called with an incorrect number of arguments!'
    return 1
  fi

  local before="^### begin: $section ###\$"
  local after="^### end: $section ###\$"

  sed --in-place \
    -e "/$before/,/$after/{ /$before/{p; i $content" -e "}; /$after/p; d }" \
    '/monero/bitmonero.conf'

  if [ "$grep_lines" -gt "-1" ]; then
    grep -A$grep_lines -E "$before" '/monero/bitmonero.conf'
  fi

  return 0
}

get_onion_address () {
  local tries=0

  until [ -f /var/lib/tor/monerod/hostname ]; do
    tries=$((tries+1))

    if [ "$tries" -gt 5 ]; then
      log_msg "$0" 'error' 'Could not determine b32 URL for I2P hidden service!'
      exit 1
    fi

    # Print status to stderr so it isn't captured by var=$(get_onion_address)
    log_msg "$0" 'warn' "Waiting for onion address... ($tries)"

    sleep 1
  done

  local onion="$(cat /var/lib/tor/monerod/hostname)"

  echo -n "$onion"
}

get_i2p_address () {
  local tries=0

  local i2p_b32=""

  until [ -n "$i2p_b32" ]; do
    tries=$((tries+1))

    if [ "$tries" -gt 5 ]; then
      log_error "$0" 'Could not determine b32 URL for I2P hidden service!'
      exit 1
    fi

    # Print status to stderr so it isn't captured by var=$(get_i2p_address)
    log_msg "$0" 'warn' "Waiting for b32 address... ($tries)"

    # WARNING! This IPv4 address is hardcoded in compose.yaml
    i2p_b32="$(curl -fs 'http://172.31.255.251:7070/?page=i2p_tunnels' | grep 'monero-rpc' | grep -oE '[a-z0-9]+\.b32\.i2p')"

    sleep 3
  done

  echo -n "$i2p_b32"
}


# Sanity check in case someone mounted /monero instead of /monero/lmdb and
# didn't create bitmonero.conf in the mount point
if [ ! -f '/monero/bitmonero.conf' ]; then
  log_msg 'main' 'error' '/monero/bitmonero.conf does not exist!'
  exit 1
fi

# We need a DNS resolver that supports DNSSEC queries for some options to work.
# These include:
#   - check-updates
#   - enforce-dns-checkpointing
#   - enable-dns-blocklist
if [ -z "$DNS_PUBLIC" ]; then
  log_msg 'main' 'warn' '$DNS_PUBLIC is not set. You may see DNSSEC errors in the logs.'
fi

if [ "$MONEROD_UPDATE_BANLIST" = "true" ] && [ -n "$MONEROD_BANLIST_URL" ]; then
  # TODO: Check last modified time and don't do anything if the ban list file
  #       is less than, like, five minutes (?) old?
  #       Just so we don't hammer GitHub with requests on a failed startup.
  log_msg 'main' 'info' "Downloading $MONEROD_BANLIST_URL..."
  curl -fsSL -o '/monero/ban_list.txt' "$MONEROD_BANLIST_URL"
  log_msg 'main' 'info' '/monero/ban_list.txt updated!'
fi


## Write configuration options to /monero/bitmonero.conf

log_msg 'main' 'info' 'Setting options in /monero/bitmonero.conf...'

declare -i grep_lines=2

conf_content='#'
if [ "$MONEROD_USE_DNS_BLOCKLIST" = "true" ]; then
  conf_content='enable-dns-blocklist=1'
fi
set_conf_option \
  'enable-dns-blocklist' \
  "$conf_content"

conf_content='#'
if [ "$MONEROD_PRUNE_BLOCKCHAIN" = "true" ]; then
  conf_content="prune-blockchain=1\nsync-pruned-blocks=1"
  grep_lines=3
fi
set_conf_option \
  'prune-blockchain' \
  "$conf_content" \
  "$grep_lines"

conf_content='#'
grep_lines=2
if [ "$MONEROD_USE_TOR" = "true" ]; then
  ONION_ADDRESS="$(get_onion_address)"
  conf_content="tx-proxy=tor,172.31.255.250:9050,disable_noise,24\nanonymous-inbound=$ONION_ADDRESS:18084,127.0.0.1:18084,24"
  grep_lines=3
fi
set_conf_option \
  'tor-config' \
  "$conf_content" \
  "$grep_lines"

conf_content='#'
grep_lines=2
if [ "$MONEROD_USE_I2P" = "true" ]; then
  I2P_ADDRESS="$(get_i2p_address)"
  conf_content="tx-proxy=i2p,172.31.255.251:4447,disable_noise,24\nanonymous-inbound=$I2P_ADDRESS,127.0.0.1:18085,24"
  grep_lines=3
fi
set_conf_option \
  'i2p-config' \
  "$conf_content" \
  "$grep_lines"

if [ "$MONEROD_USE_TOR" = "true" ] || [ "$MONEROD_USE_I2P" = "true" ]; then
  if [ "$MONEROD_PAD_TRANSACTIONS" = "false" ]; then
    log_msg 'main' 'warn' 'You are using Tor and/or I2P but not padding transactions.'
    log_msg 'main' 'warn' 'This will make you vulnerable to traffic volume analysis.'
    log_msg 'main' 'warn' 'See https://github.com/monero-project/monero/pull/4787 for more info.'
  fi
else
  if [ "$MONEROD_PAD_TRANSACTIONS" = "true" ]; then
    log_msg 'main' 'warn' 'You are running a clearnet node but padding transactions.'
    log_msg 'main' 'warn' 'This only makes sense if you are running behind Tor or I2P.'
    log_msg 'main' 'warn' 'Consider setting MONEROD_PAD_TRANSACTIONS=false in your compose configuration.'
  fi
fi

conf_content='#'
grep_lines=2
if [ "$MONEROD_PAD_TRANSACTIONS" = "true" ]; then
  conf_content='pad-transactions=1'
fi
set_conf_option \
  'pad-transactions' \
  "$conf_content"

echo "==============================================================================="
echo "==  monerod is starting!"
if [ -n "$ONION_ADDRESS" ]; then
  echo "==   - Tor hidden service URL is $ONION_ADDRESS:18089"
fi
if [ -n "$I2P_ADDRESS" ]; then
  echo "==   - I2P hidden service URL is $I2P_ADDRESS:18089"
fi
if [ -n "$DNS_PUBLIC" ]; then
  echo "==   - Using $DNS_PUBLIC DNS resolver"
fi
echo "==============================================================================="

sleep 3

monerod \
  --non-interactive \
  --log-level=${MONERO_LOG_LEVEL:-0} \
  --data-dir=/monero \
  --ban-list=/monero/ban_list.txt \
  --config-file=/monero/bitmonero.conf
