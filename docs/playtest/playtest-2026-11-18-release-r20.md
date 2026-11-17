# Windows r20與實際Linux伺服器驗收

## 本批結果

整合第11章羊躲雨及雞抱抱，Windows客戶端與Linux世界伺服器同為build20／protocol47，存檔26。前回合新增雞抱抱、原生與連線測試及紀錄，屬實質進度；本輪補真正交付包及獨立伺服器程序驗收，不縮小完整規劃書的目標。

## 正式匯出與本機跨程序

Windows Desktop及Linux Server都用Godot4.7.2正式release模板，排除tests。Linux使用既有Dockerfile、非root使用者與原生檔案鎖，世界資料綁到隔離的work/release-r20/server-data-v4。

- Windows正式EXE實際透過ws://127.0.0.1的動態本機埠加入Linux容器，使用原雞卡按鈕抱抱，再經原互動入口放開。錄36張真原生畫格，carried=1時ground=0，釋放後恢復ground=1；親密度只增加一次、背包相同、鏡頭相同。這是程式觸發既有按鈕與互動入口，不是實體滑鼠／鍵盤手動遊玩。
- 另兩個Windows Godot測試客戶端對同一實際Linux EXE驗證15項：真實30秒照料冷卻、同時搶抱只有一人成功、相同公開持有人、快照沒有原profile token、手工具拒絕、真正輸入移動及真實8秒到期、沒有額外背包／親密度獎勵。沒有伺服器內存快轉、贈送物資或以測試內建World替代該伺服器。
- 停止並重新建立容器，沿用同一掛載資料，另5項通過：原兩個玩家、累積親密度2及照料冷卻保留，沒有舊抱姿重播。最後只停止本輪建立的唯一QA容器，保留測試資料；未改動其他Docker服務。
- 伺服器即時日誌確認SERVER_BUILD version=0.50-dev build=20 protocol=47，實際載入原生存檔鎖並完成保存。這是同一台Windows上的Linux Docker環境，並不是騰訊／Zeabur公開部署、跨電腦或TLS/WSS驗收。

原有明確啟用的錄影路徑新增雞卡動作及被動天氣觀察。連線操作需額外capture-loopback，且地址必須精確為ws://127.0.0.1:指定埠；一般遠端地址不會獲得該錄影動作入口。明確--join啟動可從GAME_CLIENT_ROOM_KEY取得測試房間碼，不放在命令列或個人偏好檔。這些入口仍走原Session／伺服器權限、距離與材料規則，沒有伺服器特權或免費道具。

## 羊與安裝包

- 正式Windows EXE在本機真世界時間由晴／多雲跨入小雨時錄80張畫格，羊從0到32像素進既有棚，超過8個中間位置，鏡頭、地面及背包固定。野餐、友誼、站位、接近午夜的時間為明確測試預置；棚和墊實際扣正常開局4木／3纖維。不宣稱從新手開局自然完成棉棉故事。
- 相同匯出EXE與DLL做隔離QA產品的安裝驗證，兩檔SHA256相同；開始選單捷徑實際啟動r20。r13舊世界副本成功加入新測試玩家、保留原玩家和野餐旗標，原始檔雜湊不變。解除安裝保留QA世界與個人資料。未把QA安裝覆蓋使用者現有遊戲。
- 檢視正式title.png確認r20，exported-online.png確認新畫面及抱雞時沒有舊鋤頭提示，exported-rain.frames/079.png確認小雨HUD與棚下羊；藍圖UI607項與版本更新39項回歸通過。

## 實測修正的問題

- Linux匯出漏列非資源檔release.json，已加入include_filter並用實際啟動標記驗證。
- 正式Linux stdout原先被緩衝；容器活著且WebSocket已回101，但啟動日誌空白。經實際握手及程序檢查診斷後，啟用run/flush_stdout_on_print，重新匯出、建立映像並重跑。這符合[Godot專用伺服器文件](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)的日誌建議；沒有把觀察逾時當作伺服器不可用。
- 新錄影欄位最初遇到Variant型別推斷錯誤，已明確使用Vector2後重新匯出，未交付錯誤版本。
- 舊多API測試器只有Session相對路徑，不符合獨立遊戲程序的Island/Session。外部驗收器改從真正main.tscn讀根節點名稱，保持實際RPC路徑；遊戲本身RPC沒有為測試改路徑。失敗過程保留container-path-diagnostic.log，最終容器日誌無該錯誤。
- 安裝器QA原以TCP空埠啟動ENet，曾撞到不可用UDP埠，改為實際保留可用UDP埠後通過。
- 原雞抱抱原生腳本凍結部分主循環，沒抓到藍圖更新把工具提示重新顯示。正式EXE截圖發現後，兩處介面更新改用同一可見性判斷；正式連線逐格驗證所有抱姿畫格的tool_hint_visible=false，釋放後恢復；原藍圖607項保留。

## 產物與證據

- outputs/TuanIslandSetup-0.50-dev-r20.exe：97,843,504 bytes。
- outputs/TuanIslandServer-0.50-dev-r20-linux-x64.zip：88,395,561 bytes。
- outputs/TuanIsland-r20-更新內容.txt、TuanIsland-r20-產物驗證.json。
- work/release-r20/verified.log、container-verified.log、container-clients-race.log（15）、container-clients-reload.log（5）、exported-rain-verified.log、blueprint-ui.log（607）、version-final.log（39）。
- Linux包包含世界EXE、原生鎖、Docker啟動設定、版本資訊、原Godot／原生鎖授權、端點與備份工具及部署說明；沒有測試世界、房間碼、使用者資料或雲端秘密。Caddyfile為既有完整身分服務模式參考，本包僅世界程序，公開入口及身分服務需另配置。

## 部署與剩餘驗收

已於2026/11/18重新核對[Zeabur官方公告](https://zeabur.com/en-US/blogs/migration-refunds-and-security-claims)：建議11/30前搬遷，12/31全部服務停止與資料刪除。來源部署說明已改為目前protocol47，遷移目標沿用騰訊雲。這項核對及Linux包不代表已備份或遷移現有雲端世界。

本機驗收結束時尚未公開上傳GitHub、修改更新清單、部署雲端、切換網域或測試外部WSS；後續公開下載狀態以r20 Release及發布紀錄為準。完整帳號入口、遠端磁碟及跨電腦仍要在目標主機驗收；完整規劃的其他內容與真人手感也未因此完成，目標保持進行中。
