FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 island \
    && useradd --uid 10001 --gid island --create-home island
WORKDIR /app
COPY tuan-island-server.x86_64 /app/server
COPY libisland_world_lock.so /app/libisland_world_lock.so
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod 755 /app/server /app/entrypoint.sh && mkdir /data && chown island:island /data
ENV PORT=8080 GAME_BIND=0.0.0.0 GAME_TRANSPORT=websocket GAME_SAVE_PATH=/data/world.json
EXPOSE 8080/tcp
ENTRYPOINT ["/app/entrypoint.sh"]
