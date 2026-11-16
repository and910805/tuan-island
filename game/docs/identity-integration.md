# 0.25 封測身分與世界成員整合

使用協定 21 的專用 WebSocket 世界伺服器。0.25 新增個人水路觀察、分水回顧與共享紀念牌；世界格式升為4，舊v1／v2／v3可遷移。客戶端與世界伺服器必須一起更新，不能混用0.24／協定20或更早版本。育苗與地方記憶僅傳送接收者自己的私人進度，共享紀念牌則公開。玩家先向身分服務登入，再取得此世界的單次加入票券。世界伺服器以其專屬憑證兌換票券，並約每10秒重新驗證玩家；驗證失敗會中止連線。封測世界拒絕舊profile註冊；本機與受信任區網可以沿用既有模式。

## 專用伺服器設定

以下參數必須全部提供。也可用對應環境變數。

| 命令列 | 環境變數 | 用途 |
|---|---|---|
| `--identity-api` | `GAME_IDENTITY_API` | HTTPS 身分服務基底 URL |
| `--world-id` | `WORLD_ID` | 身分服務已配置的世界 ID |
| `--identity-server-key-file` | `IDENTITY_SERVER_KEY_FILE` | 私有檔案路徑，內容為該世界的服務憑證 |
| `--members` | `MEMBERS_PATH` | 持久名冊檔案路徑 |
| `--owner-account` | `OWNER_ACCOUNT` | 已配置的島主帳號 ID |
| `--public-address` | `GAME_PUBLIC_ADDRESS` | 世界目錄公開 WSS 位址 |
| `--world-name` | `GAME_WORLD_NAME` | 世界目錄顯示名稱 |

使用 `--server --transport=websocket`（也可用 `GAME_TRANSPORT=websocket`）。`--save`／`GAME_SAVE_PATH` 指向另一份持久世界檔。正式對外連線由 TLS 邊緣提供 WSS；將 Godot WebSocket 上游限制在私有或 loopback 位址，避免直接對外。CLI `--identity-test-loopback` 只供隔離 QA 連接帶埠號的字面位址 `http://127.0.0.1:<port>`，勿用於部署。

## Session 介面

```text
configure_identity(api_url, world_id, server_secret, membership_path, owner_account,
                   allow_test_loopback=false, tls_options=null, world_path="") -> Error
join_authenticated(address, port, ticket, invite, allow_test_loopback=false,
                   tls_options=null) -> Error
configure_directory(address, world_name, mode="生活", allow_test_loopback=false) -> Error
```

在專用伺服器 `host()` 前呼叫 `configure_identity()`。`tls_options` 允許嵌入端透過 `TLSOptions.client(ca)` 指定受信任 CA；`main.gd` 傳入 null 採 Godot 預設 CA，沒有對外開放 CA 檔或略過憑證驗證的旗標。最後的 `world_path` 必須非空；保留空字串預設僅使舊呼叫得到明確錯誤，不代表可以省略。伺服器 HTTPS 請求禁止重新導向。客戶端正常使用 WSS；兩端均拒絕 unsafe TLS options。

正式主程式會傳入 `world_path`，先取得世界與名冊的原生寫入鎖，再於名冊載入、遷移或世界名稱更新前恢復未完成的入島日誌。缺少世界路徑或原生鎖元件、其他程序已持有相同資源時拒絕啟動；已有世界但名冊遺失時也不建立替代帳號映射。之後 `host()` 必須使用相同世界路徑。`shutdown()` 完成關閉後釋放鎖；不能重用已關閉的 Session，重新啟動須建立新物件。

入島先在隔離副本準備角色與名冊，不立刻占用席位。將兩份候選及原檔摘要寫入 `<members>.admission-wal`，原子替換日誌成功即決定提交。接著發布世界主檔、包含新角色的世界備份和名冊，全部完成並移除日誌才接納連線。提交前失敗不改兩份資料；決定提交後失敗，世界停止操作、被動生長、定時保存、斷線保存、名冊與目錄更新，允許直接關閉並保留日誌。

重啟時重播同一份候選，不重新生成角色或重發起始物資。重播會驗證世界 ID、檔案配對、各目標原始／完成摘要和候選結構；發現意外修改會保留現況並拒絕啟動。原主檔與備份保留在 `*.admission-previous-<transaction>`，不要將這些伺服器資料公開或打包成下載。0.19 以 `<members>.admission-retention.json` 登記並保留最近三組已完成交易副本，清理前驗證來源、路徑與摘要；未登記或被修改的檔案不自動刪除。仍需營運容量監控與獨立備份。

這是受本機原生寫入鎖保護的可恢復跨檔提交。必須隨 Windows／Linux 程式交付 `addons/world_lock` 所指定的 DLL／SO。`.writer-lock` 是穩定的鎖目標，不要在執行中刪除。外部讀檔工具不能把寫入途中的某一個檔案當成完整備份；已測程序中止，未證明斷電時的檔案系統耐久性。此鎖不是分散式租約，未驗證跨核心共同掛載及網路檔案系統。遷移前先在原路徑完成恢復、停寫並一起備份世界與名冊，不能將帶原絕對路徑的待恢復日誌直接搬到另一個目錄後當作正常啟動。

營運端遷移既有角色時，先離線備份並核實帳號與舊角色的對應，再匯入名冊。玩家端不接收內部角色 ID、伺服器憑證或邀請雜湊。

在 `configure_identity()` 後、`host()` 前設定目錄。兩個目錄欄位要一起提供。名冊保存發布版本後才送出目錄快照，邀請輪替與撤銷要等相符版本確認。邀請解析提供世界預覽，實際加入由世界伺服器核對名冊和邀請。

隔離網路測試使用 `work/access/network_identity.py --directory` 驗證 HTTPS/WSS、私人目錄、邀請與重連。0.18 結果位於 `work/admission/network-evidence.json`。`work/admission/crash_recovery.py` 在三個寫入邊界強制結束 Godot 後重啟，`capture_failure.py` 讓真實入口收到保存失敗回覆並擷取畫面。雲端部署尚待驗收。
