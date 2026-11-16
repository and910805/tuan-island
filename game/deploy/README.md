# 糰糰島 0.50-dev 封測部署

世界伺服器與 Windows 客戶端須使用多人協定 45。此開發版使用世界存檔格式 26。升級前請停止世界寫入，另存世界主檔、備份檔、名冊與身分資料庫。若要回退舊版，須使用升級前的完整備份。

八人登入、分區移動、耕種、捐修閘門與跨區轉乘已在本機驗證。Zeabur 首次部署仍需用隔離世界驗證外部 Windows 客戶端、WSS 登入與重連，以及持久卷重啟後的存檔。完成 Zeabur 驗收後再驗證騰訊雲搬遷。

## 身分服務

參照 `services/identity` 的安裝依賴及 `admin.py --help` 配置世界和帳號。將 SQLite 資料庫放在只有身分服務可以存取的持久磁碟，保留一致性備份。世界服務憑證以私有檔案交給遊戲伺服器，玩家帳號憑證透過私下管道交付。切勿將資料庫、憑證、邀請碼或 TLS 私鑰提交至原始碼或日誌。

身分服務可用 `serve.py --database /data/identity.sqlite --tls-cert <cert> --tls-key <key>` 直接提供 TLS，也可用 `--trusted-proxy <指定 IP>` 讓私有上游信任已配置的 TLS 邊緣。HTTP 健康檢查路徑為 `/healthz`。

## 世界伺服器與目錄

使用 `--server --transport=websocket` 或 Dockerfile 的等效預設。環境變數如下。

| 變數 | 設定 |
|---|---|
| `PORT` | 平台提供的世界伺服器埠號 |
| `GAME_BIND` | 裸機建議綁定私有或 loopback 位址，容器依網路隔離設定 |
| `GAME_TRANSPORT` | `websocket` |
| `GAME_SAVE_PATH` | Docker 固定使用 `/data/world.json` |
| `GAME_IDENTITY_API` | 世界伺服器可達且能驗證憑證的 HTTPS 身分服務 URL |
| `WORLD_ID` | 營運端已配置的世界 ID |
| `IDENTITY_SERVER_KEY_FILE` | 掛載的唯讀世界憑證檔，UID 10001 須能讀取 |
| `MEMBERS_PATH` | Docker 固定使用 `/data/members.json` |
| `OWNER_ACCOUNT` | 已配置的島主帳號 |
| `GAME_PUBLIC_ADDRESS` | 玩家可達的公開 WSS 位址 |
| `GAME_WORLD_NAME` | 世界目錄顯示名稱 |

遊戲上游只允許 TLS 代理存取。代理須保留 WebSocket Upgrade，設定適合長連線的閒置逾時。遊戲埠使用 TCP 健康檢查；`SERVER_READY` 只確認監聽已啟動。一般區網可使用原信任房間，勿將它當作公開身分驗證。

## Zeabur 與騰訊

在 Zeabur 先為世界和身分服務各配置持久儲存與 TLS 網域。世界服務僅跑一個寫入實例。先用隔離測試世界驗證登入、邀請入會、撤銷、WSS 重連、重啟恢復與檔案權限，再規劃搬遷。

可先從外部 Windows 執行 `python check_endpoints.py --identity-health https://<身分網域>/healthz --world wss://<世界網域>/`，確認兩個入口的正式憑證、HTTPS 健康回應與 WebSocket 升級。接著用桌面客戶端完成帳號登入、驗證舊版拒絕，並在重啟後確認原角色、名冊和世界進度。

騰訊 Linux x86_64 可沿用同一組服務，將代理 443 轉向私有遊戲及身分服務埠。以下是待實機驗收的世界容器範例，`island.env` 只含設定與秘密檔路徑。

```sh
docker build -t tuan-island:0.50-dev .
docker volume create tuan-island-data
docker run -d --name tuan-island --restart unless-stopped \
  --env-file island.env -p 127.0.0.1:8080:8080 \
  --mount source=tuan-island-data,target=/data \
  --mount type=bind,src=/srv/island/world-server.key,dst=/run/secrets/world-server.key,readonly \
  tuan-island:0.50-dev
```

搬遷前停寫並一致備份世界主檔、備份檔、名冊和身分 SQLite。恢復時保留角色映射、邀請世代與目錄版本。不可只還原舊名冊而保留較新的目錄資料庫，否則版本倒退會被拒絕。啟動後核對舊角色資產、成員權限、目錄狀態及撤銷結果，再切換玩家入口。

## 入島保存日誌（0.18）

帳號首次加入或更新跨越名冊與世界時，伺服器先保存入島日誌，然後發布世界、備份與名冊。若發布中斷，請保留 `members.json.admission-wal`，在同一世界 ID 與存檔路徑重新啟動，讓程式完成重播。日誌存在或重播失敗時暫停寫入，請保留現有檔案與錯誤日誌供排查。

備份或搬遷前請停止唯一寫入程序。保留名冊、世界主檔與備份，並保存任何待重播日誌及 `*.admission-previous-*` 歷史副本。日誌記錄檔案的原路徑，請先在原位置完成重播，再搬遷。歷史副本會佔用磁碟空間，請在重播成功、確認無待處理日誌且另有備份後，依營運保留政策離線歸檔。這些檔案可能含玩家資料，存取權應與主檔相同。

此流程已測試單一寫入者下的程序終止與重播。斷電耐久性、跨主機多寫入者及雲端部署尚未驗收。

