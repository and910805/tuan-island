# 糰糰島 0.50-dev 封測部署

開發版 Windows 安裝包在 `release.json` 使用 `version` 與 `build`。例如主畫面的 `0.50-dev r11` 在簽署更新清單中對應 `0.50.11-dev`，舊版可用原本的數字版號比較辨識新版。發布同一系列時請遞增 `build`，最低版號若要指定 r10 則用 `0.50.10-dev`。多人協定由其獨立欄位決定。

多人協定以 `release.json` 為準；本批 r20 為 47，世界伺服器與 Windows 客戶端須一致。此開發版使用世界存檔格式 26。升級前請停止世界寫入，另存世界主檔、備份檔、名冊與身分資料庫。若要回退舊版，須使用升級前的完整備份。

八人登入、分區移動、耕種、捐修閘門與跨區轉乘已有本機驗證紀錄。Zeabur 已公告將於 2026 年 12 月 31 日結束營運，雲端發行改以騰訊雲為目標。公開 Windows 客戶端、WSS 登入及重連、持久磁碟重啟後的存檔仍須在目標主機驗收。[Zeabur 遷移時程](https://zeabur.com/en-US/blogs/migration-refunds-and-security-claims)

若 Zeabur 上仍有正式世界，先盤點專案與掛載資料並確認實例到期日。官方建議在 2026 年 11 月 30 日前完成搬遷，專用主機可能在 12 月 31 日前依到期日刪除。匯出副本應在服務仍能存取時完成。切換後的回復點使用有驗證的離線副本與仍受支援的主機，保留切換後累積的最新進度。[Zeabur 遷移指南](https://zeabur.com/en-US/blogs/migrate-from-zeabur)

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

遊戲上游只允許 TLS 代理存取。遊戲埠使用 TCP 健康檢查，`SERVER_READY` 只確認監聽已啟動。一般區網可使用原信任房間，勿將它當作公開身分驗證。

同機部署可用隨附的 `Caddyfile`。將 `TUAN_PUBLIC_HOST` 設成你的公開網域，DNS 指向主機，並在防火牆開放 Caddy 的 TCP 80 與 443。遊戲與身分服務預設使用私有的 `127.0.0.1:8080` 和 `127.0.0.1:8081`，可分別用 `TUAN_WORLD_UPSTREAM` 及 `TUAN_IDENTITY_UPSTREAM` 覆蓋。使用 `caddy validate --config Caddyfile` 檢查設定，再以同一組環境變數啟動 Caddy。

世界服務設定 `GAME_PUBLIC_ADDRESS=wss://你的網域/island`，身分服務 URL 設成 `https://你的網域`。`/island` 只接受 WebSocket 升級，並保留查詢參數供快照壓縮使用。身分服務以主機程序綁定 loopback 時，Uvicorn 使用 `--trusted-proxy 127.0.0.1`。若身分服務進容器，依實際網路設定信任 Caddy 的確切來源 IP，並讓身分服務的上游埠維持私有。[Caddy 反向代理文件](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)

## 騰訊雲切換與驗收

先在騰訊雲為身分與世界服務配置持久儲存及 TLS 網域。每個世界只啟動一個寫入實例。用隔離世界驗證登入、邀請入會、撤銷、WSS 重連、重啟恢復與檔案權限。

如有舊 Zeabur 世界，停止接收變更並確認保存後，再匯出世界卷、身分資料庫與必要設定。若發現待重播的入島日誌，先在原位置完成重播。比對傳輸前後檔案摘要並以副本驗證還原；切換公開入口前核對原角色、背包、地塊及名冊。記下原網域與新端點，保留可在另一個仍受支援的主機啟動的復原副本。若需切回，先停止新端寫入，再匯出最新資料。

可先從外部 Windows 執行 `python check_endpoints.py --identity-health https://<身分網域>/healthz --world wss://<世界網域>/island`。兩個入口各自回報結果，也可單獨指定 `--world` 檢查舊世界的公開 WSS 位址。握手通過後，用桌面客戶端完成帳號登入、驗證舊版拒絕，並在重啟後確認原角色、名冊和世界進度。

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

### 搬遷備份與驗證

停止世界與身分服務後，從部署包目錄使用 Python 3.11 或更新版本。輸出目錄的上層須存在。每次匯出與還原使用新的輸出目錄。

```sh
python3 world_backup.py export --world-directory /srv/island/world-data \
  --identity-database /srv/island/identity-data/identity.sqlite \
  --world-id YOUR_WORLD_ID --output /srv/backup/transfer-01
python3 world_backup.py verify /srv/backup/transfer-01
python3 world_backup.py restore /srv/backup/transfer-01 --output /srv/island/restored-01
```

驗證檔案內容的 SHA-256、SQLite 完整性、世界編號、島主帳號與名冊版本。還原完成後，將 `restored-01/data/world` 和 `restored-01/data/identity` 分別用於兩項服務，並沿用原本的世界編號、島主及世界服務憑證。另行保存憑證、部署設定及入島歷史副本。若身分資料庫共用於多座島，在同一維護時段匯出各世界。備份含玩家資料與身分資料庫，請透過私有通道傳輸並限制目錄存取。保留可信的原備份，移轉後才核對摘要與啟動。

使用隨附的身分服務容器時，將還原後的身分目錄及 SQLite 檔案交給容器使用者 UID/GID 10001。SQLite 也需要能寫入所在目錄。以實際還原路徑替換下列範例，在 Linux 宿主機執行後將該目錄掛載至身分容器的 `/data`。

```sh
sudo chown 10001:10001 /srv/island/restored-01/data/identity /srv/island/restored-01/data/identity/identity.sqlite
sudo chmod 700 /srv/island/restored-01/data/identity
sudo chmod 600 /srv/island/restored-01/data/identity/identity.sqlite
```

### 本機搬遷演練

以同一版原始碼或專服包分別建置世界與身分服務映像。下列指令從專案根目錄執行，使用本機的 r10 映像名稱作為範例。

```powershell
$env:TUAN_RELOCATION_WORLD_IMAGE = 'tuan-world:0.50-dev-r10'
$env:TUAN_RELOCATION_IDENTITY_IMAGE = 'tuan-identity:0.50-dev-r10'
python work/access/network_identity_docker_restart_050.py --directory --relocate
```

演練會建立獨立的測試世界。兩項服務停止後，以 `world_backup.py` 匯出、驗證並還原主檔、備份、名冊和 SQLite，核對世界列表發布新的 WSS 入口，再以原帳號登入。島主會在新環境鋪一格木地板。回退時使用同一工具搬回新環境的最新資料，驗證木地板和扣料都保留。輸出會列出搬移和回退的本機停機時間。

## 容量與每月費用

容量測試從專案根目錄執行 `python work/access/measure_world_capacity.py work/capacity-new --seconds 22`，需要 Python 的 `psutil`。測試使用各自隔離的存檔、Godot 4.7.2 Windows 專服及本機 WebSocket 客戶端。CPU 與記憶體計入 Godot 主程序及 Windows console wrapper；下行資料量由 TCP 轉送器計數，包含 WebSocket 訊框，未含外網 TLS、代理及 IP 層。身分服務、長時間模擬與雲端尖峰須另量。

每月資料量試算使用「實測 bytes／秒 × 每月在線秒數 ÷ 10 億」。每月以 30 日計。實例費以固定月租估算，備份、稅金與其他服務依實際配置另計。騰訊雲官方列出的東京與新加坡 Lighthouse Linux Razor Speed 2 核 2 GB 方案為每月 US$5.60，標示峰值 200 Mbps 及不限量流量。香港 Linux Starter 2 核 2 GB 為每月 US$6.00，峰值 20 Mbps、512 GB／月。實際可購買的規格與價格以結帳頁為準。[騰訊雲 Lighthouse 計價](https://www.tencentcloud.com/document/product/1103/47794)

2026 年 11 月 17 日未壓縮基準在 Ryzen 7 7700 的 Windows 主機取得。每場量測 22 秒，四人都在望安，八人分布在望安與北門。混合操作包括鋤地、播種、澆水、捐閘門木板及移動。開局資料來自預置世界。

| 場景 | 平均 CPU 核數 | 峰值記憶體 MiB | 平均／單秒峰值下行 Mbps | 每天 4 小時、每月 GB | 24 小時、每月 GB |
|---|---:|---:|---:|---:|---:|
| 空房 | 0.013 | 232.0 | 0／0 | 0 | 0 |
| 1 人移動 | 0.179 | 231.2 | 3.54／3.75 | 191.2 | 1,146.9 |
| 4 人移動 | 0.281 | 231.2 | 14.71／15.59 | 794.2 | 4,765.2 |
| 8 人分區移動 | 0.474 | 233.7 | 29.44／31.00 | 1,589.8 | 9,538.6 |
| 8 人混合操作 | 0.474 | 230.9 | 30.23／40.16 | 1,632.4 | 9,794.4 |

空房期間世界時間維持在 0，遊戲伺服器仍常駐。入島從連線嘗試到收到第一張世界快照為 44 ms。這是本機空房後進入既有程序的時間。另量到啟動程序至確認監聽約 5.6–6.1 秒。雲端停機後恢復及外網加入時間待量。

新版 WebSocket 客戶端在連線要求加上 `tuan-snapshot=zstd1`，要求壓縮個人世界快照。部署代理須把查詢參數轉送到遊戲伺服器才會啟用壓縮。未收到參數時，伺服器使用協定 45 的既有格式。ENet 延用原格式。八人混合負載重跑 22 秒後，平均下行為 6.12 Mbps、單秒峰值 8.48 Mbps、平均 0.527 核、峰值約 226 MiB，全部八位玩家完成且每人收到 203–205 張快照。以每天 4 小時計，30 日約 330 GB。若長時間滿房或代理未啟用壓縮，需以相應情境的流量另估。

東京或新加坡 Razor Speed 是下一輪隔離驗收的候選，固定月租試算 US$5.60。世界程式之外還需量測身分服務、代理、作業系統、正式世界存檔和雲端可用頻寬。

## 入島保存日誌（0.18）

帳號首次加入或更新跨越名冊與世界時，伺服器先保存入島日誌，然後發布世界、備份與名冊。若發布中斷，請保留 `members.json.admission-wal`，在同一世界 ID 與存檔路徑重新啟動，讓程式完成重播。日誌存在或重播失敗時暫停寫入，請保留現有檔案與錯誤日誌供排查。

備份或搬遷前請停止唯一寫入程序。保留名冊、世界主檔與備份，並保存任何待重播日誌及 `*.admission-previous-*` 歷史副本。日誌記錄檔案的原路徑，請先在原位置完成重播，再搬遷。歷史副本會佔用磁碟空間，請在重播成功、確認無待處理日誌且另有備份後，依營運保留政策離線歸檔。這些檔案可能含玩家資料，存取權應與主檔相同。

若停機後發現 `world.json.bak.staged`，請和主檔及 `world.json.bak` 一起保留。它是備份輪替中上一次成功保存的世界。主檔缺失或無法讀取時，遊戲會優先嘗試讀取該檔。

此流程已測試單一寫入者下的程序終止與重播。斷電耐久性、跨主機多寫入者及雲端部署尚未驗收。

## Windows 安裝包

以 Godot 的 `Windows Desktop` 發行設定匯出 `TuanIsland.exe`。在同一目錄保留匯出時產生的 `island_world_lock.dll`。用 NSIS 3.11 編譯安裝包時，指定匯出目錄、Godot 授權檔所在目錄，以及 `game/release.json` 裡的版本。

```powershell
& $makensis /INPUTCHARSET UTF8 "/DINPUT_DIR=$exportDir" "/DENGINE_DIR=$engineDir" "/DOUTPUT_FILE=$installerPath" "/DAPP_VERSION=$version" game/deploy/windows_installer.nsi
```

以上目錄及輸出檔請使用絕對路徑。安裝預設放在目前使用者的 `%LOCALAPPDATA%\TuanIsland`，並建立開始功能表捷徑和 Windows 的解除安裝項目。解除安裝移除安裝包內的遊戲檔案及捷徑，保留遊戲存檔與下載的更新版本。

## Windows 版本清單

從已完成的 Windows 發行 ZIP 產生更新清單。版本讀自匯出時的 `game/release.json`。最低支援版本、下載頁及 ZIP 的直接網址由發行者指定。

```powershell
python game/deploy/build_update_manifest.py --archive <Windows-ZIP> --release game/release.json --minimum-version <最低支援版本> --download-url <HTTPS下載頁> --archive-url <HTTPS壓縮檔網址> --signing-key <私鑰PEM路徑> --output update-manifest.json
```

使用 `work/package_game.py` 打包時，設定 `TUAN_UPDATE_MINIMUM_VERSION`、`TUAN_UPDATE_DOWNLOAD_URL`、`TUAN_UPDATE_ARCHIVE_URL` 及 `TUAN_UPDATE_SIGNING_KEY` 可一併產生簽章清單。簽署環境需要 Python 的 `cryptography`。私鑰存放在發行專案之外。Windows 匯出前，把對應的公鑰存成 `game/update-release-public.pem`，並設定 `application/config/update_manifest_url` 指向正式 HTTPS 清單。遊戲驗證清單後才顯示版本及下載頁。玩家從下載頁取得 ZIP 後，可在更新提示選「驗證下載的 ZIP」，核對簽章清單中的大小和 SHA-256。

更新提示中的「準備新版」會先複製並重新核對 ZIP，再把遊戲執行檔及存檔 DLL 放在使用者的獨立更新目錄。成功後可以開啟新版資料夾。現有安裝及世界存檔留在原位置。

簽章清單有有效的 HTTPS ZIP 網址時，Windows 更新提示也會顯示「在遊戲內下載」。下載時會顯示進度，完成後驗證並準備新版。可使用會轉向另一個 HTTPS 下載入口的發行網址。下載失敗時可重試或改從下載頁取得 ZIP。

Windows 主選單上的「啟動新版」需要新版 EXE 與 DLL 的 SHA-256 都符合簽章清單。新版抵達主選單並回報成功後，原程序成功記下簽章清單才會退出。若記錄寫入失敗，會關閉這次啟動的新版並保留原版主選單。玩家下次用原捷徑啟動時，遊戲會重驗清單與新版檔案，由最新的可用版本開始嘗試。候選檔案遭更改或未回報時，會繼續嘗試其他已驗證版本，最後保留原版。啟動器與可回復的版本留在各自目錄。

