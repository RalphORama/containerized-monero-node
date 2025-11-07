#!/usr/bin/env bash

set -euo pipefail

# This file isn't meant to run on its own. Source it from other scripts.

log_msg () {
  local USAGE="log_msg <level> <message> [domain]"
  local LOG_LEVEL="${LOG_LEVEL:-INFO}"
  LOG_LEVEL="${LOG_LEVEL^^}"

  local level="$1"
  local message="$2"
  local domain="$3"

  local reset='\e[0m'
  declare -A fgc
  declare -A bgc

  fgc[black]='\e[30m'
  fgc[red]='\e[31m'
  fgc[green]='\e[32m'
  fgc[yellow]='\e[33m'
  fgc[blue]='\e[34m'
  fgc[magenta]='\e[35m'
  fgc[cyan]='\e[36m'
  fgc[gray]='\e[37m'
  fgc[white]='\e[38m'

  bgc[black]='\e[40m'
  bgc[red]='\e[41m'
  bgc[green]='\e[42m'
  bgc[yellow]='\e[43m'
  bgc[blue]='\e[44m'
  bgc[magenta]='\e[45m'
  bgc[cyan]='\e[46m'
  bgc[gray]='\e[47m'
  bgc[white]='\e[48m'

  if [ -z "$level" ] || [ -z "$message" ]; then
    log_msg "ERROR" "Expected at least two positional arguments but got \$1: $1, \$2: $2" "log_msg"
    return 1
  fi

  level="${level^^}"

  if [ -n "$domain" ]; then
    domain="(${domain})\t"
  fi

  local stamp="${fgc[gray]}$(date '+%Y-%M-%d %H:%m:%S')${reset}"

  declare -A prefix
  prefix[ERROR]="${fgc[red]}ERROR${reset}"
  prefix[WARN]="${fgc[yellow]}WARN${reset}"
  prefix[INFO]="${fgc[green]}INFO${reset}"
  prefix[DEBUG]="${fgc[black]}${bgc[gray]}DEBUG${reset}"

  local skip="true"

  case "$level" in
    "ERROR")
      [ "$LOG_LEVEL" = "ERROR" ] && skip="false"
      ;&
    "WARN")
      [ "$LOG_LEVEL" = "WARN" ] && skip="false"
      ;&
    "INFO")
      [ "$LOG_LEVEL" = "INFO" ] && skip="false"
      ;&
    "DEBUG")
      [ "$LOG_LEVEL" = "DEBUG" ] && skip="false"
      ;;
    *)
      log_msg "ERROR" "Expected one of (DEBUG|INFO|WARN|ERROR) for <level> but got $level" "log_msg"
      return 1
      ;;
  esac

  [ "$skip" = "true" ] && return 0

  local fmt_string="${stamp}\t${prefix[$level]}\t${domain}${message}"

  case "$level" in
    "ERROR" | "error")
      echo -e "$fmt_string" >&2
      ;;
    *)
      echo -e "$fmt_string"
  esac

  return 0
}
