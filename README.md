# 糰糰島

溫暖的2D像素生活遊戲開發版。可單機種田、採集、料理與建造，隨故事解鎖島民照料及供水、林業加工。

本批試玩包：**0.50-dev r22**。

- [下載 Windows 安裝檔](https://github.com/and910805/tuan-island/releases/download/v0.50-dev-r22/TuanIslandSetup-0.50-dev-r22.exe)
- [下載 Linux 世界伺服器包](https://github.com/and910805/tuan-island/releases/download/v0.50-dev-r22/TuanIslandServer-0.50-dev-r22-linux-x64.zip)
- [更新說明與檔案校驗](https://github.com/and910805/tuan-island/releases/tag/v0.50-dev-r22)

安裝後確認主畫面左下為r22，選「住進自己的小島」即可單機玩，不需要IP。r22新增正式發行公鑰與公開簽章更新來源，保留r21的牛短程跟隨及生活動作。r21及更早公開包需先手動安裝一次r22，之後才能由遊戲提示新發行版並核對下載。

多人客戶端與世界伺服器需同用協定48；r20協定47不能混用。正式Windows EXE已連本機Linux容器測試照料與重啟保存；雲端尚未切換r22，公開WSS與跨電腦仍待驗收。正式更新清單使用獨立update-feed分支的已簽章HTTPS內容，來源與完整公開更新驗證範圍見Release附檔。

原始碼位於[game](game/README.md)，引擎Godot4.7.2。本tag與release/r22-20261118分支對應本批來源；預設分支及雲端不會因本次Release自動升級。完整遊戲仍在開發，這是預先發行試玩版。
