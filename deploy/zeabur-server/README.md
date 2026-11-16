# 糰糰島 Zeabur 測試伺服器

此服務使用 Godot 4.7.2 的 0.50-dev Linux 專用伺服器，接收 WebSocket 連線，預設監聽 Zeabur 提供的 `PORT`（通常是 8080）。Dockerfile 會從公開 GitHub 預發布版取得伺服器封包，並以 SHA-256 驗證後才解壓。

## Zeabur 設定

- 建置根目錄：`deploy/zeabur-server`
- 服務來源：Dockerfile
- TCP 連接埠：`8080`
- 環境變數：`PORT=8080`、`GAME_BIND=0.0.0.0`、`GAME_TRANSPORT=websocket`、`GAME_SAVE_PATH=/data/world.json`，以及至少 12 個字元的 `GAME_ROOM_KEY`
- 持久磁碟掛載點：`/data`。先掛載後再讓玩家加入，避免世界存檔留在暫存容器中。
- 保持單一副本；世界資料由單一伺服器程序寫入。

這個測試服務使用房間通行碼，沒有接上帳號身分服務。只把通行碼提供給預定測試玩家；正式公開前需完成帳號服務、更新網址、備份及跨機驗收。
