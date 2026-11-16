#!/bin/sh
set -eu

# This volume is dedicated to the world and membership files.
if [ "${GAME_SAVE_PATH:-/data/world.json}" != '/data/world.json' ]; then
    echo 'This container expects GAME_SAVE_PATH=/data/world.json.' >&2
    exit 1
fi
if [ -n "${GAME_IDENTITY_API:-}${WORLD_ID:-}${IDENTITY_SERVER_KEY_FILE:-}${MEMBERS_PATH:-}${OWNER_ACCOUNT:-}${GAME_PUBLIC_ADDRESS:-}${GAME_WORLD_NAME:-}" ]; then
    : "${GAME_IDENTITY_API:?Set GAME_IDENTITY_API}"
    : "${WORLD_ID:?Set WORLD_ID}"
    : "${IDENTITY_SERVER_KEY_FILE:?Set IDENTITY_SERVER_KEY_FILE}"
    : "${OWNER_ACCOUNT:?Set OWNER_ACCOUNT}"
    : "${GAME_PUBLIC_ADDRESS:?Set GAME_PUBLIC_ADDRESS}"
    : "${GAME_WORLD_NAME:?Set GAME_WORLD_NAME}"
    if [ "${MEMBERS_PATH:-}" != '/data/members.json' ]; then
        echo 'This container expects MEMBERS_PATH=/data/members.json.' >&2
        exit 1
    fi
else
    room_key=${GAME_ROOM_KEY:-}
    if [ "${#room_key}" -lt 12 ]; then
        echo 'Trusted room mode requires GAME_ROOM_KEY of at least 12 characters.' >&2
        exit 1
    fi
fi
mkdir -p /data
chown island:island /data
for saved in /data/world.json /data/world.json.bak /data/world.json.tmp /data/world.json.rejected-* /data/members.json \
    /data/world.json.writer-lock /data/members.json.writer-lock /data/members.json.admission-wal \
    /data/members.json.admission-retention.json \
    /data/world.json.admission-previous-* /data/world.json.bak.admission-previous-* /data/members.json.admission-previous-*; do
    if [ -f "$saved" ] && [ ! -L "$saved" ]; then chown island:island "$saved"; fi
done
exec gosu island /app/server --headless -- --server "$@"
