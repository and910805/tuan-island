FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 island \
    && useradd --uid 10001 --gid island --create-home island

WORKDIR /app
ARG SERVER_ARCHIVE_URL=https://github.com/and910805/tuan-island/releases/download/v0.50-dev-20261115/TuanIsland-Linux-Server-0.50-dev-20261116.tar.gz
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 15 "$SERVER_ARCHIVE_URL" -o /tmp/server.tar.gz; \
    printf '%s  %s\n' 'd8e019fedcaa6c08b9b7f7d3e0aabdd189b4f7e1f7c8213a647892ab6560f9ff' '/tmp/server.tar.gz' | sha256sum -c -; \
    tar -xzf /tmp/server.tar.gz -C /app; \
    rm -f /tmp/server.tar.gz

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod 755 /app/tuan-island-server.x86_64 /app/entrypoint.sh /app/libisland_world_lock.so \
    && mkdir /data \
    && chown island:island /data

ENV PORT=8080 GAME_BIND=0.0.0.0 GAME_TRANSPORT=websocket GAME_SAVE_PATH=/data/world.json
EXPOSE 8080/tcp
ENTRYPOINT ["/app/entrypoint.sh"]
