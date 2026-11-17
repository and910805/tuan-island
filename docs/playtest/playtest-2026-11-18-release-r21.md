# Windows／Linux r21 試玩包驗收 — 2026-11-18

## 範圍與進展

前一目標回合新增奶糖牛短程照料跟隨及原生／多人證據，有實際進展。本輪整合釣魚等待與漁獲擺動、加工成品落架、共用操作提示位置及牛跟隨，製作可執行試玩包。不是只確認編輯器能跑，也不是把公開r20檔案改名。

Windows安裝檔 `outputs/TuanIslandSetup-0.50-dev-r21.exe`，97,851,912 bytes，SHA256 `71be316da426e84d1a1a6c67e7097fbb9e08660e643ffa94cf67e5639e7c42c7`。

Linux世界包 `outputs/TuanIslandServer-0.50-dev-r21-linux-x64.zip`，88,404,323 bytes，SHA256 `ad68857322394e04d38aa57f4441611b0d46e2ba87501795eb3ef6e1e9a2a5b3`。

版本0.50-dev、build21、protocol48、世界schema26。公開r20仍protocol47；本輪沒有公開上傳、改GitHub預設分支、切換雲端或配置簽署更新清單。

## 實際匯出與連線

以Godot4.7.2正式release模板分別匯出Windows與Linux，保留原生存檔鎖，排除測試檔。Linux使用非root執行的既有Dockerfile，綁定本輪專屬隔離資料夾。容器日誌確認 `SERVER_BUILD version=0.50-dev build=21 protocol=48`。

真正Windows匯出EXE透過本機WebSocket加入獨立Linux程序，用原牛卡按鈕送摸頭請求，錄48張原生畫格。牛位移超過八種且走出20像素以上；親密度只加一次，背包與相機不變，沒有兩條瞬時提示同時可見。這是既有明確啟用的QA錄影入口觸發按鈕，不是人手點擊。

另兩個Windows測試客戶端對實際Linux EXE完成12項：同時摸頭僅一成功、同一公開照料對象、沒有原始profile token、真實輸入仍按碰撞移動、真實18秒到期、原30秒冷卻仍拒絕新照料、材料與親密度不重複。沒有對Linux伺服器內存快轉或贈送材料。

實際停止並重建Linux容器，掛載同一資料。4項客戶端確認原公開身份、沒有舊跟隨姿勢、親密度及原照料時間；同時從磁碟確認兩個原玩家都保留、last_pet及bond完全相同。快照只列在線玩家，沒有拿快照人數冒充磁碟名冊驗收。

本輪僅停止自己建立的唯一名稱容器；隔離世界與診斷檔保留於work/release-r21，不改其他Docker服務或雲端世界。

## 安裝、舊世界與畫面

使用同一Windows EXE／DLL承載檔，以獨立QA產品名驗證安裝；檔案SHA256與匯出相同。開始選單捷徑實際啟動，title.png顯示「0.50-dev r21」。複製r13世界後真正加入新QA玩家，既有玩家與野餐旗標保留，來源世界雜湊不變。解除安裝後仍保留QA存檔與個人資料；未覆蓋使用者現有正式安裝。

原生重新檢查共用提示位置57項，含三解析度、最大既有文字倍率及正式材料不足→排程→完工→領取。版本39項通過。牛及其他新增內容的細部驗證沿用各自本日報告；本輪沒有宣稱重跑完整數百支測試清單。

檢視正式title.png及exported-cow.png：版本r21、角色、牛、原場景及圖示工具欄可見，操作提示只留一條。原始完整圖在work/release-r21；新版牛卡與動畫見前一牛照料報告。

## 驗收器修正

- 第一個QA profile只有七字，原連線門檻要求12至64字，因而被正確拒絕；改用合法長度測試身份並加入fixture長度檢查，未放寬遊戲加入條件。錯誤記錄保留exported-cow-invalid-profile.log。
- 初版重啟測試錯用只含在線玩家的快照驗證兩個磁碟角色；改成實際磁碟前後名冊比對及公開身份重連。沒有為測試把離線角色公開給客戶端。診斷記錄clients-reload-snapshot-diagnostic.log，最終12＋4項通過。
- 一次提示截圖誤用headless模式，等待不到繪圖事件；只停止已核對命令列屬於本輪的兩個Godot程序，再原生重跑57項。新提示及牛錄影腳本加入無畫面模式快速拒絕，避免未來掛住。這些測試檔不在匯出包內。
- 每次容器驗收從只讀測試模板複製新的唯一資料夾，避免重試時沿用照料冷卻或上次狀態；保留失敗資料而不刪使用者世界。

## 包內容與界線

Linux ZIP逐檔白名單、CRC及正式測過的ELF雜湊一致；包含世界程序、原生鎖、版本JSON、Docker／啟動設定、部署說明、端點與備份工具及授權。沒有QA世界或房間碼。Caddyfile是完整身分服務模式參考，本世界包不含身分服務程序。

產物及驗證：outputs/TuanIsland-r21-更新內容.txt、TuanIsland-r21-產物驗證.json；work/release-r21/release-verified.log、container-verified.log、container-data.json、verified.log、server-zip-verified.log、notice-ui-final.log、version-final.log。

可先單機試玩，或與同版r21伺服器連線。未驗實體跨電腦、公開TLS/WSS、真人完整新手旅程或遠端資料遷移。Windows安裝器沒有程式碼簽署；正式自動更新來源仍未配置。完整遊戲規劃尚未完成，目標保持進行中。
