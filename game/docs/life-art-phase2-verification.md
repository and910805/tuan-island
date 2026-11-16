# 生活美術第二階段驗證

比對基線是已批准的第一階段村莊預覽。第一階段封包及畫面已備份至 `work/checkpoint-life-art-phase2/`。八個核心腳本的 SHA-256 與基線逐檔相符。

## 回歸結果

九套核心測試 661 項，第一階段 UI、角色畫面、舒適設定、視覺約定和旗標 UI 共 292 項，合計 953 項通過。另以預覽旗標執行一般 UI 測試，109 項通過。日誌及結構化結果位於 `work/life-art-tests/` 和 `work/life-art-phase2-core-results.json`。

以 `work/village-village.json` 的副本讀取、保存並重新載入。使用 Python 對序列化 JSON 逐值比對，全部原欄位及數值相同，包含 1 位玩家的所有背包物品與數量、6 格作物。原檔與保存時建立的備份位元相同。1 張長椅及 3 個花箱仍阻擋通行。Godot 測試為 `res://tests/test_life_art_stage1_save.gd`，傳入第一階段存檔及未使用的副本絕對路徑。

## 自動測試涵蓋的功能

- **玩家四向**　上、下、左、右各測站立、開始走路及停止，確認停住後保留朝向、腳底對齊互動格、斜走等速。另檢查遠近鏡頭、減少動態以及多人角色辨識。
- **居民互動**　阿榆在 `(38, 29)`，米露在 `(44, 31)`。確認近距離提示和 E 互動仍以原座標判定，走遠後提示消失，故事交件和手帳照常更新。確認新圖的腳底與格座標相符。
- **作物成長**　同時比對乾地、澆水、幼苗、成長和成熟的畫面及狀態。以原規則的成熟秒數、採收數量及背包變化為準。
- **番茄再生**　每次收成 2 顆，共 3 收。前兩次採收後回到待澆水狀態，重新澆水才進下一輪，第三次後作物清空。中途存檔重載，確認輪次和物資保留。
- **保存相容**　用第一階段實際存檔的副本測讀取、保存和重載。比對角色位置、背包與鈴幣、農地與成熟狀態、建物、居民、圖鑑進度；測原檔雜湊前後相同。若只能建立測試夾具，須記錄來源與差異。
- **第一階段 UI**　開啟工具列、任務面板、地圖、故事手帳與設定。確認 1280×800 和 1280×720 的底列可操作，工具與施工點擊不被 HUD 吃掉，拖曳施工可取消且不扣料。

| 作物 | 澆水後成熟秒數 | 每次採收 |
| --- | ---: | ---: |
| 奶白蘿蔔 | 90 | 1 |
| 圓葉萵苣 | 75 | 1 |
| 星點小麥 | 120 | 2 |
| 糖心胡蘿蔔 | 105 | 1 |
| 小馬鈴薯 | 150 | 2 |
| 太陽番茄 | 120 | 2 |

## 第二階段最終結果

角色圖集 93 項、作物圖集與成長規則 145 項、世界視圖整合 14 項，新增 252 項全數通過。加上既有 953 項，共 1,205 項；另以預覽旗標重跑一般 UI 109 項。總計 1,314 次檢查，無失敗。

Windows 匯出使用 `village_art_preview` feature，獨立使用者資料目錄 `TuanIsland-Life-Art-Preview-2`。由實際匯出的執行檔擷取村莊、農園、渡口、居民手帳、圖鑑、背包與糯米雞面板，共七張 1280×800 畫面，皆正常退出，無引擎錯誤或存檔備份復原。這是本機匯出煙霧測試；本階段未重跑跨機網路壓力測試。

玩家四方向各有站立、左步、右步，腳底固定，不額外上下晃動。正常速度約每秒兩個步態循環。附錄 GIF 使用同一渲染器輸出，以半速方便觀察；不是即時錄影。作物包含六種類、每種四階段；已成熟的乾作物維持成熟圖，番茄三次採收及重置狀態仍由原世界規則處理。

所有展示存檔都由第一階段副本布置，農園的 24 個成長樣本不是玩家自然進度。新角色、作物和動物是生成的 PNG 素材，來源提示詞與匯入方式見 `assets/life-art/generation-record.json`。其他地區、家具和系統不在本次美術改造範圍。

## 回歸命令

由專案根目錄執行。測試日誌另存，不寫入正式發行的測試日誌。

```powershell
$baseline = Get-Content -Raw work/life-art-phase2-core-baseline.json | ConvertFrom-Json
foreach ($entry in $baseline.files.PSObject.Properties) {
    $sha = (Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne $entry.Value) { throw "Core SHA-256 mismatch: $($entry.Name)" }
}

$godot = (Resolve-Path work/engine/Godot_v4.7.2-stable_win64_console.exe).Path
$logs = New-Item -ItemType Directory -Path work/life-art-tests -Force
$suites = 'world','life','regrowth','save_schema','village','building','festival','collections','build_catalog'
foreach ($suite in $suites) {
    & $godot --headless --path game --script "res://tests/test_$suite.gd" -- --profile=life-art-phase2-core *> (Join-Path $logs "test_$suite.log")
    if ($LASTEXITCODE -ne 0) { throw "Core regression failed: $suite" }
}

foreach ($suite in 'ui','village_visual_contract') {
    & $godot --headless --path game --script "res://tests/test_$suite.gd" -- --profile=life-art-phase2-village --village-art-preview *> (Join-Path $logs "test_stage1_$suite.log")
    if ($LASTEXITCODE -ne 0) { throw "Village preview regression failed: $suite" }
}
```
