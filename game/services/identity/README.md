# 封測身分服務 0.50-dev

這個服務負責穩定帳號、登入、短效世界票證、在線資格驗證與私人世界目錄。遊戲伺服器再核對自己的世界成員清單，邀請碼不能取代登入。開帳號、停權與輪替金鑰必須在營運端執行，沒有公開管理端點。

## 憑證與保存

- 帳號使用固定 UUID，顯示名字可修改。同名不等於同一帳號。
- 封測帳號憑證由服務產生 32 bytes 隨機值，直到輪替或停權前有效。它不是使用者自行設定的密碼，也不是邀請碼。
- 登入工作階段有效 15 分鐘，遊戲每 5 分鐘續期；初次登入後最長 8 小時。斷線或重試不得讓已失效工作階段復活。
- 世界票證最長 30 秒、綁定世界、只能兌換一次。只能用該世界專用後端金鑰兌換；玩家端不持有後端金鑰。
- 世界伺服器每 10 秒驗證在線資格。登出、停權及帳號憑證輪替會使資格失效；驗證失聯則停止認證連線。票證或資料庫故障不會降級為 profile token 登入。
- SQLite 只存憑證摘要。資料變更提交後才回覆成功。帳號資料庫、世界成員檔、世界存檔都必須持久保存，跨檔加入交易目前採保留席位和角色映射再重試，詳見 `game/docs/identity-integration.md`。

## 本機營運端準備

以 Python 3.12 建立獨立環境後安裝 `requirements.txt`。路徑使用專屬可寫資料目錄；金鑰輸出檔必須放在只有營運者可讀的目錄，不能放網站靜態資料夾或提交到原始碼。

```text
python admin.py --database /data/identity.sqlite account-create --name 小糰 --output-file /private/player.json
python admin.py --database /data/identity.sqlite world-key --world-id first-island --output-file /private/world.key
```

帳號檔含 account_id 與 credential，僅交給對應玩家。世界金鑰檔只交給該世界伺服器。工具拒絕覆寫既有輸出檔；若資料庫變更已成功但輸出磁碟失敗，先修復儲存再輪替到另一個新檔，不假稱舊金鑰仍有效。

```text
python admin.py --database /data/identity.sqlite account-rotate --account-id ACCOUNT_UUID --output-file /private/replacement.json
python admin.py --database /data/identity.sqlite account-disable --account-id ACCOUNT_UUID
```

## HTTPS 與健康檢查

可從此目錄建置身分服務映像。容器使用 UID／GID 10001，持久卷須允許該身分寫入 `/data`，憑證則以唯讀方式掛載。容器的預設入口已指定資料庫與 8081 埠，啟動參數仍須提供 `--tls-cert` 和 `--tls-key`，或提供實際 TLS 代理的 `--trusted-proxy` 位址。世界服務與身分服務各自使用獨立的持久卷。

```text
python serve.py --database /data/identity.sqlite --host 0.0.0.0 --port 8081 --tls-cert /private/fullchain.pem --tls-key /private/key.pem
```

也可由 TLS 反向代理終止 HTTPS，但必須透過 `--trusted-proxy` 指定實際代理 IP，將後端服務埠限制為僅代理可達。工具拒絕萬用信任 `*`。程式不自行信任外來 X-Forwarded-*，正式請求若沒有已驗證代理提供的 HTTPS scheme 就拒絕。`GET /healthz` 檢查資料庫可存取，不回傳帳號資訊。

僅隔離測試可使用 `--host 127.0.0.1 --test-loopback`，對應遊戲的 `--identity-test-loopback`。這不是對外部署方式。正式玩家使用 HTTPS 身分服務與 WSS 世界入口，憑證及主機名必須驗證成功。

本輪未部署 Zeabur，也未驗證 Linux 容器、外部 Windows、代理轉送 IP、持久卷重啟與備份復原。此服務暫採一個 Uvicorn worker、最多 64 個並行連線、8 KiB JSON 上限、5 秒收取資料期限及每來源／端點速率限制；多 worker／多副本必須另做共享限速與運維容量驗收。公開註冊、帳號恢復、自助開世界與可點擊的外部邀請連結仍未完成。

## API

所有 POST 都使用 `application/json`，不接受多餘或重複欄位。除了登入，使用 `Authorization: Bearer ...`；後端端點只接受世界後端金鑰。所有 JSON 回應帶 `Cache-Control: no-store`，失敗以 400／401／413／429／503 等狀態和固定中文訊息回覆，不回顯秘密。

| 路徑 | 呼叫身分 | 內容 |
| --- | --- | --- |
| `/v1/login` | 帳號 ID + 封測憑證 | `{account_id, credential}` |
| `/v1/refresh` | 工作階段 | `{}` |
| `/v1/logout` | 工作階段 | `{}` |
| `/v1/profile` | 工作階段 | `{display_name}` |
| `/v1/tickets` | 工作階段 | `{world_id}` |
| `/v1/redeem` | 對應世界後端 | `{world_id, ticket}` |
| `/v1/validate` | 對應世界後端 | `{world_id, admission_id}` |
| `/v1/worlds` | 工作階段 | `{}` 或 `{cursor}`，最多八個已加入世界及下一頁游標 |
| `/v1/resolve` | 工作階段 | `{invitation}`，完整 `TI1` 邀請信，僅預覽、不取得成員身分 |
| `/v1/publish` | 對應世界後端 | 帶持久版本的世界快照；欄位見 `identity_store.py` 的 `_validate_snapshot` |

## 世界目錄與邀請

資料庫 schema 3 會由舊版升級，保留原帳號及工作階段。世界伺服器每十秒發布一次目錄；超過 35 秒未收到新的版本時，已加入的世界仍可列出，但顯示離線、線上人數為零。相同版本的重送可確認成功，不能延長在線狀態。舊版本或同版本但不同內容會被拒絕。

世界卡片只提供公開名稱、角色、席位與在線狀態，不傳其他人的帳號 ID、角色保存鍵或邀請摘要。完整邀請格式為 `TI1.<world_id 的無填充 base64url>.<隨機邀請碼>`；使用者貼上後，服務驗證到期、撤銷、在線狀態及席位。取得卡片不代表成功加入，遊戲伺服器仍須驗票並保存成員。

島主輪替邀請後，先顯示同步中，只有目錄確認了相符版本才顯示完整邀請信。撤銷後的舊碼在權威遊戲端立即失效；目錄同步失敗時可能暫時仍能解析舊卡片，但不能入會。必須一起備份世界、成員名冊與身分資料庫；目錄版本機制不能取代單一寫入者租約。

## 驗證

安裝 `requirements-test.txt` 後在本目錄執行 `python -B -m unittest -v test_identity_store test_api test_admin test_directory`。實際多程序 HTTPS／WSS 目錄測試為專案根目錄 `work/access/network_identity.py --tls --directory`，介面流程為 `work/directory/network_directory_ui.py`。所有帳號、私鑰與存檔均為獨立臨時資料，不操作玩家真實資料。

設計依據：[OWASP 工作階段管理](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)、[Python SQLite 交易](https://docs.python.org/3/library/sqlite3.html)、[Starlette 請求處理](https://starlette.dev/requests/)、[Uvicorn 部署設定](https://www.uvicorn.org/settings/)。
