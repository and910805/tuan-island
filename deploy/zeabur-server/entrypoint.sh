#!/bin/sh
set -eu

if [ "${GAME_SAVE_PATH:-/data/world.json}" != '/data/world.json' ]; then
    echo 'This container expects GAME_SAVE_PATH=/data/world.json.' >&2
    exit 1
fi
room_key=${GAME_ROOM_KEY:-}
if [ "${#room_key}" -lt 12 ]; then
    echo 'Trusted room mode requires GAME_ROOM_KEY of at least 12 characters.' >&2
    exit 1
fi
mkdir -p /data
chown island:island /data
for saved in /data/world.json /data/world.json.bak /data/world.json.tmp /data/world.json.rejected-* /data/world.json.writer-lock; do
    if [ -f "$saved" ] && [ ! -L "$saved" ]; then chown island:island "$saved"; fi
done
exec gosu island /app/tuan-island-server.x86_64 --headless -- --server "$@"
