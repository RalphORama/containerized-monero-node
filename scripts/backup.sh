#!/usr/bin/env bash

set -e
set -o pipefail

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
    echo -e "ERROR\tExpected LOG_LEVEL to be one of (DEBUG|INFO|WARN|ERROR) but got ${LOG_LEVEL}" >&2
    ;;
esac

echo -e "INFO\tLOG_LEVEL set to $LOG_LEVEL"

if [ ! -f "./compose.yaml" ]; then
  echo -e "ERROR\tThere is no compose.yaml file in $(pwd). Are you in the right place?" >&2
  exit 1
fi

if [ -z "$BACKUPS_DIR" ]; then
  echo -e "WARN\tBACKUPS_DIR not set in the environment or passed as first argument." >&2
  echo -e "WARN\tSetting BACKUPS_DIR to $(pwd)/backups" >&2
  BACKUPS_DIR="./backups"
fi

if [ ! -d "$BACKUPS_DIR" ]; then
  echo -e "ERROR\tThe directory $BACKUPS_DIR doesn't exist!" >&2
  exit 1
fi

clean_dir () {
  local target_dir="$1"

  if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
    echo -e "ERROR\tCannot delete contents of ${target_dir} because it doesn't exist!" >&2
    return 1
  fi

  # https://unix.stackexchange.com/a/86950/172280
  find "$target_dir" -mindepth 1 -maxdepth 1 -print0 | xargs -0 rm -rf $VERBOSE

  echo -e "DEBUG\tDeleted contents of ${target_dir}."

  return 0
}

service_is_running () {
  local service="$1"

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
    echo -e "ERROR\tNo arguments passed!" >&2
    return 1
  fi

  if [ "$(service_is_running $service)" = "false" ]; then
    echo -e "ERROR\tThe service ${service} is not running!"
    return 1
  fi

  for file in "${files[@]}"; do
    if ! docker compose ${COMPOSE_OPTS[@]} exec -ti "$service" \
      /usr/bin/env bash -c "test -f $file || test -d $file || exit 1"; \
    then
      echo -e "ERROR\t$file does not exist inside ${service}!" >&2
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
    echo -e "ERROR\t$service is not in the list of Docker Compose services!" >&2
    return 1
  fi

  local tmp_dir="${BACKUPS_DIR}/.tmp"
  local output_dir="${BACKUPS_DIR}/${service}"
  local tarball="${service}_${TIMESTAMP}.tar.gz"

  if [ ! -d "$output_dir" ]; then
    echo -e "INFO\tCreating $output_dir"
    mkdir -p $VERBOSE "$output_dir"
  fi

  # Clean up the previous temp contents
  if [ ! -d "$tmp_dir" ]; then
    mkdir -p $VERBOSE "$tmp_dir"
  else
    clean_dir "$tmp_dir"
  fi

  #echo -e "INFO\tChecking files exist in ${service}..."
  #check_container_files "$service" "${files[@]}"

  echo -e "INFO\tBacking up files from ${service}..."
  for file in "${files[@]}"; do
    echo -e "DEBUG\tCopying ${service}:${file} -> ${tmp_dir}"

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

  echo -e "INFO\tBackup for ${service} created at ${output_dir}/${tarball}!"

  return 0
}

# TODO: Create a file next to backup.sh that stores this info?
declare -a tor_files=("/var/lib/tor/monerod")
declare -a i2pd_files=("/var/lib/i2pd/monero-mainnet.dat")

echo -e "INFO\tChecking files exist in their containers..."
check_container_files 'tor' "${tor_files[@]}"
check_container_files 'i2pd' "${i2pd_files[@]}"

if [ "$PAUSE_CONTAINERS" = "true" ]; then
  echo -e "INFO\tPausing services while we back up files..."
  docker compose ${COMPOSE_OPTS[@]} pause
else
  echo -e "WARN\tNot pausing containers during backup. This might cause issues!"
fi

echo -e "INFO\tBacking up files for tor..."
backup_service 'tor' "${tor_files[@]}"

echo -e "INFO\tBacking up files for i2pd..."
backup_service 'i2pd' "${i2pd_files[@]}"

if [ "$PAUSE_CONTAINERS" = "true" ]; then
  echo -e "INFO\tWaiting 5 seconds before unpausing services..."
  sleep 5

  echo -e "INFO\tUnpausing services now that backups are done..."
  docker compose ${COMPOSE_OPTS[@]} unpause

  echo -e "WARN\tTor and I2P services may show as 'unhealthy' for the next ~5 minutes." >&2
  echo -e "WARN\tThis is a normal result of pausing/unpausing the services to create a backup." >&2
fi

echo -e "INFO\tFinished backing up files!"
