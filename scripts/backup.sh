#!/usr/bin/env bash

set -euo pipefail

# https://stackoverflow.com/a/12694189/3722806
SCRIPT_DIR="${BASH_SOURCE%/*}"
if [ ! -d "$SCRIPT_DIR" ]; then SCRIPT_DIR="$PWD"; fi

source "${SCRIPT_DIR}/lib/logging.sh"

unset SCRIPT_DIR

LOG_LEVEL="${LOG_LEVEL:-INFO}"
VERBOSE=""
TIMESTAMP="$(date --utc --iso-8601=seconds | sed 's/T/_/' | sed 's/:/-/g' | sed -E 's/\+[[:digit:]]{2}.[[:digit:]]{2}$//')"
BACKUPS_DIR="${BACKUPS_DIR:-$1}"
PAUSE_CONTAINERS="${PAUSE_CONTAINERS:-true}"

declare -a COMPOSE_OPTS=("--ansi=never")

case "$LOG_LEVEL" in
  "DEBUG" | "debug")
    VERBOSE="-v"
    COMPOSE_OPTS+=("--progress=plain")
    ;;
  "INFO" | "info")
    COMPOSE_OPTS+=("--progress=quiet")
    ;;
  "WARN" | "warn" | "WARNING" | "warning")
    COMPOSE_OPTS+=("--progress=quiet")
    ;;
  "ERROR" | "error")
    COMPOSE_OPTS+=("--progress=quiet")
    ;;
  *)
    log_msg 'ERROR' "Expected LOG_LEVEL to be one of (DEBUG|INFO|WARN|ERROR) but got ${LOG_LEVEL}" 'main'
    ;;
esac

log_msg 'DEBUG' "LOG_LEVEL set to $LOG_LEVEL" 'main'

if [ ! -f "./compose.yaml" ]; then
  log_msg 'ERROR' "There is no compose.yaml file in $(pwd). Are you in the right place?" 'main'
  exit 1
fi

if [ -z "$BACKUPS_DIR" ]; then
  log_msg 'WARN' "BACKUPS_DIR not set in the environment or passed as first argument." 'main'
  log_msg 'WARN' "Setting BACKUPS_DIR to $(pwd)/backups" 'main'
  BACKUPS_DIR="./backups"
fi

if [ ! -d "$BACKUPS_DIR" ]; then
  log_msg 'ERROR' "The directory $BACKUPS_DIR doesn't exist!" 'main'
  exit 1
fi

clean_dir () {
  local target_dir="$1"

  if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
    log_msg 'ERROR' "Cannot delete contents of ${target_dir} because it doesn't exist!" 'clean_dir'
    return 1
  fi

  # https://unix.stackexchange.com/a/86950/172280
  find "$target_dir" -mindepth 1 -maxdepth 1 -print0 | xargs -0 rm -rf $VERBOSE

  log_msg 'DEBUG' "Deleted contents of ${target_dir}" 'clean_dir'

  return 0
}

service_is_running () {
  local service="$1"

  log_msg 'DEBUG' "Checking if ${service} is running..." 'service_is_running'

  docker compose ${COMPOSE_OPTS[@]} ps \
    --services \
    --status=running \
    "$service" \
    2>/dev/null && \
    echo "true" || echo "false"

  return 0
}

check_container_files () {
  local service="$1"
  declare -a files=("${@:2}")

  if [ -z "$service" ]; then
    log_msg 'ERROR' "No arguments passed!" 'check_container_files'
    return 1
  fi

  if [ "$(service_is_running $service)" = "false" ]; then
    log_msg 'ERROR' "The service ${service} is not running!" 'check_container_files'
    return 1
  fi

  for file in "${files[@]}"; do
    if ! docker compose ${COMPOSE_OPTS[@]} exec -ti "$service" \
      /usr/bin/env bash -c "test -f $file || test -d $file || exit 1"; \
    then
      log_msg 'ERROR' "${file} does not exist inside ${service}!" 'check_container_files'
      return 1
    fi
  done

  return 0
}

backup_service () {
  # USAGE: backup_service [service name] [file-1] [file-2] ... [file-n]
  local service="$1"
  declare -a files=("${@:2}")

  local service_exists="$(docker compose ${COMPOSE_OPTS[@]} config --services | grep -o $service || true)"

  if [ -z "$service" ] || [ -z "$service_exists" ]; then
    log_msg "Service $service is not in the list of Docker Compose services!"
    return 1
  fi

  local tmp_dir="${BACKUPS_DIR}/.tmp"
  local output_dir="${BACKUPS_DIR}/${service}"
  local tarball="${service}_${TIMESTAMP}.tar.gz"

  if [ ! -d "$output_dir" ]; then
    log_msg 'INFO' "Creating $output_dir"
    mkdir -p $VERBOSE "$output_dir"
  fi

  # Clean up the previous temp contents
  if [ ! -d "$tmp_dir" ]; then
    mkdir -p $VERBOSE "$tmp_dir"
  else
    clean_dir "$tmp_dir"
  fi

  log_msg 'INFO' "Backing up files from ${service}..."
  for file in "${files[@]}"; do
    log_msg 'DEBUG' "Copying ${service}:${file} -> ${tmp_dir}"

    docker compose ${COMPOSE_OPTS[@]} cp \
      --archive \
      --follow-link \
      "${service}:${file}" \
      "${tmp_dir}"
  done

  # Use "." for the path since -C changes the working directory for tar.
  # This strips extra components (./backups/.tmp/) off of created tarballs
  tar -cz $VERBOSE \
    -C "$tmp_dir" \
    -f "${output_dir}/${tarball}" \
    "."

  clean_dir "$tmp_dir"

  log_msg 'INFO' "Backup for ${service} created at ${output_dir}/${tarball}!"

  return 0
}

# TODO: Create a file next to backup.sh that stores this info?
declare -a tor_files=("/var/lib/tor/monerod")
declare -a i2pd_files=("/var/lib/i2pd/monero-mainnet.dat")

log_msg 'INFO' "Checking files exist in their containers..." 'main'
check_container_files 'tor' "${tor_files[@]}"
check_container_files 'i2pd' "${i2pd_files[@]}"

if [ "$PAUSE_CONTAINERS" = "true" ]; then
  log_msg 'INFO' "Pausing services while we back up files..." 'main'
  docker compose ${COMPOSE_OPTS[@]} pause
else
  log_msg 'WARN' "Not pausing containers during backup. This might cause issues!" 'main'
fi

log_msg 'WARN' "FIXME Running hardcoded Tor backup..." 'main'
backup_service 'tor' "${tor_files[@]}"

log_msg 'WARN' "FIXME Running hardcoded I2PD backup..." 'main'
backup_service 'i2pd' "${i2pd_files[@]}"

if [ "$PAUSE_CONTAINERS" = "true" ]; then
  declare -i SLEEP_TIME=5
  log_msg 'INFO' "Waiting ${SLEEP_TIME} seconds before unpausing services..." 'main'
  sleep $SLEEP_TIME

  log_msg 'INFO' "Unpausing services now that backups are done..." 'main'
  docker compose ${COMPOSE_OPTS[@]} unpause

  log_msg 'WARN' "Tor and I2P services may show as 'unhealthy' for the next ~5 minutes." 'main'
  log_msg 'WARN' "This is a normal result of pausing/unpausing the services to create a backup." 'main'
fi

log_msg 'INFO' "Finished backing up files!"
