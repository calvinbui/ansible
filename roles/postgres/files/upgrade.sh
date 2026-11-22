#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

APP_NAME=$1

set -euo pipefail

if [[ -z $APP_NAME ]]; then
  read -rp "Application name (e.g. joplin): " APP_NAME
  if [[ -z $APP_NAME ]]; then
    echo "Nothing entered"
    exit 1
  fi
fi

PG_PATH="/apps/${APP_NAME}/postgres"
CONTAINER="${APP_NAME}-postgres"

# Check if PG_PATH exists
if [ ! -d "$PG_PATH" ]; then
    echo "Error: Postgres directory $PG_PATH does not exist."
    exit 1
fi

PG_USER=$(podman inspect "$CONTAINER" -f '{{json .Config.Env }}' | jq -r '.[] | select(test("^POSTGRES_USER=")) | sub("POSTGRES_USER="; "")')
PG_PASSWORD=$(podman inspect "$CONTAINER" -f '{{json .Config.Env }}' | jq -r '.[] | select(test("^POSTGRES_PASSWORD=")) | sub("POSTGRES_PASSWORD="; "")')

# Pre-18 images keep data directly in PG_PATH, 18+ images keep it in PG_PATH/<major>/docker
if [ -s "${PG_PATH}/PG_VERSION" ]; then
  PG_OLD_DATA="$PG_PATH"
  PG_OLD_VERSION=$(<"${PG_PATH}/PG_VERSION")
else
  PG_OLD_DATA=$(find "$PG_PATH" -mindepth 3 -maxdepth 3 -path '*/docker/PG_VERSION' -printf '%h\n' | sort -V | tail -n 1)
  if [[ -z $PG_OLD_DATA ]]; then
    echo "Error: No PG_VERSION found in ${PG_PATH} or ${PG_PATH}/*/docker"
    exit 1
  fi
  PG_OLD_VERSION=$(<"${PG_OLD_DATA}/PG_VERSION")
fi
PG_NEW_VERSION=$((PG_OLD_VERSION + 1))
echo "Upgrading from ${PG_OLD_VERSION} to ${PG_NEW_VERSION}"

if [ -e "${PG_PATH}/${PG_NEW_VERSION}" ]; then
  echo "Error: ${PG_PATH}/${PG_NEW_VERSION} already exists"
  exit 1
fi

backup_path="${PG_PATH}-${PG_OLD_VERSION}"
if [ -e "$backup_path" ]; then
  echo "Error: Backup path ${backup_path} already exists"
  exit 1
fi

# ---------------------------------------------------------
# STEP 1: Rehash MD5 passwords as SCRAM (PostgreSQL 19+ warns on every MD5 login)
# ---------------------------------------------------------
if [[ $(podman inspect "$CONTAINER" -f '{{.State.Running}}') == "true" ]]; then
  # Only rehash when the stored MD5 hash matches POSTGRES_PASSWORD, so the password is unchanged
  md5_match=$(podman exec -i "$CONTAINER" psql -U "$PG_USER" -d postgres -At \
    -v user="$PG_USER" -v pw="$PG_PASSWORD" <<'PSQL'
SELECT rolpassword = 'md5' || md5(:'pw' || :'user') FROM pg_authid WHERE rolname = :'user' AND rolpassword LIKE 'md5%';
PSQL
  )
  if [[ $md5_match == "t" ]]; then
    echo "Rehashing ${PG_USER} password as SCRAM"
    podman exec -i "$CONTAINER" psql -U "$PG_USER" -d postgres -q \
      -v ON_ERROR_STOP=1 -v user="$PG_USER" -v pw="$PG_PASSWORD" <<'PSQL'
SET password_encryption = 'scram-sha-256';
ALTER ROLE :"user" PASSWORD :'pw';
PSQL
  elif [[ $md5_match == "f" ]]; then
    echo "Warning: ${PG_USER} has an MD5 password that does not match POSTGRES_PASSWORD, leaving it as is"
  fi
else
  echo "Warning: ${CONTAINER} is not running, skipping the MD5 password check"
fi

echo "Stopping $APP_NAME"
for c in $(podman ps -a --format '{{.Names}}' | grep "^${APP_NAME}" | sort); do
  podman stop "$c" || true
done

# ---------------------------------------------------------
# STEP 2: Enable pg_checksums on pre-18 databases (18+ initdb enables them by default)
# ---------------------------------------------------------
if [[ $PG_OLD_VERSION -lt 18 ]]; then
  echo "Enabling data checksums on existing database (Version ${PG_OLD_VERSION})..."
  podman run --rm \
    -v "${PG_OLD_DATA}:/var/lib/postgresql/data" \
    "public.ecr.aws/docker/library/postgres:${PG_OLD_VERSION}" \
    pg_checksums --enable --progress -D /var/lib/postgresql/data || true

  echo "Checksums enabled."
fi

# ---------------------------------------------------------
# STEP 3: Prepare the upgrade environment
# ---------------------------------------------------------
work_dir=$(mktemp -d /tmp/postgres_upgrade.XXXXXXXX)
echo "Created temporary directory ${work_dir}"

# The upgrade image reads the old cluster from /var/lib/postgresql/<old>/data before 18
# and from /var/lib/postgresql/<old>/docker from 18
if [[ $PG_OLD_VERSION -ge 18 ]]; then
  old_subdir="docker"
else
  old_subdir="data"
fi
if [[ $PG_NEW_VERSION -ge 18 ]]; then
  new_subdir="docker"
else
  new_subdir="data"
fi

mkdir -p "${work_dir}/${PG_OLD_VERSION}"
cp -a "$PG_OLD_DATA" "${work_dir}/${PG_OLD_VERSION}/${old_subdir}"

# ---------------------------------------------------------
# STEP 4: Run the upgrade
# ---------------------------------------------------------
echo "Starting upgrade container"
podman run --rm \
  --name "${APP_NAME}-postgres-${PG_NEW_VERSION}-upgrade" \
  -e PGUSER="${PG_USER}" \
  -e POSTGRES_INITDB_ARGS="-U ${PG_USER}" \
  -v "${work_dir}":/var/lib/postgresql \
  "docker.io/tianon/postgres-upgrade:${PG_OLD_VERSION}-to-${PG_NEW_VERSION}" \
  --link

echo "host all all all scram-sha-256" >> "${work_dir}/${PG_NEW_VERSION}/${new_subdir}/pg_hba.conf"

# ---------------------------------------------------------
# STEP 5: Move the upgraded data into place
# ---------------------------------------------------------
echo "Creating a backup of old data at ${backup_path}"
mv "$PG_PATH" "$backup_path"

if [[ $PG_NEW_VERSION -ge 18 ]]; then
  mkdir -p "${PG_PATH}/${PG_NEW_VERSION}"
  mv "${work_dir}/${PG_NEW_VERSION}/${new_subdir}" "${PG_PATH}/${PG_NEW_VERSION}/"
  chown -R "$(stat -c '%u:%g' "$backup_path")" "$PG_PATH"
  chmod 700 "$PG_PATH"
else
  mv "${work_dir}/${PG_NEW_VERSION}/${new_subdir}" "$PG_PATH"
fi

rm -rf "$work_dir"

echo ""
echo "${CONTAINER} has been upgraded from $PG_OLD_VERSION to $PG_NEW_VERSION"
echo "A backup has been created at $backup_path"

if [[ $PG_OLD_VERSION -lt 18 && $PG_NEW_VERSION -ge 18 ]]; then
  echo ""
  echo "⚠️  IMPORTANT: PostgreSQL 18+ uses a new directory structure"
  echo "   The data is now located at: ${PG_PATH}/${PG_NEW_VERSION}/docker"
  echo ""
  echo "   You MUST update your container mount in your systemd unit or compose file:"
  echo "   OLD: -v ${PG_PATH}:/var/lib/postgresql/data"
  echo "   NEW: -v ${PG_PATH}:/var/lib/postgresql"
  echo ""
  echo "   (The container will automatically detect the versioned path inside)"
fi

echo ""
echo "Next: deploy ${APP_NAME} with postgres_version ${PG_NEW_VERSION}, then run update-collation.sh"
