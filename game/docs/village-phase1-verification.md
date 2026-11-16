# 村莊視覺預覽驗證

預覽使用 `--village-art-preview`。比對對象是 0.5 發行版。舊版封包、驗證紀錄和畫面在 `work/checkpoint-village-phase1/`，核心腳本 SHA-256 在 `work/village-phase1-core-baseline.json`。本紀錄涵蓋顯示與介面回歸，保留真人試玩與畫面接受度給使用者確認。

## 核心回歸結果

Godot 4.7.2 無畫面執行九套核心測試，661 項通過、0 項失敗。八個核心檔案的 SHA-256 與 0.5 基線相符。逐套日誌在 `work/village-phase1-tests/`，結構化結果在 `work/village-phase1-core-results.json`。

| 測試 | 通過 |
| --- | ---: |
| world | 64 |
| life | 45 |
| regrowth | 43 |
| save_schema | 69 |
| village | 48 |
| building | 24 |
| festival | 43 |
| collections | 81 |
| build_catalog | 244 |

## 0.5 畫面檢視重點

- 草地、土路及水岸主要由單色方格和重複點綴繪製。先確認預覽改善地表層次，且原本的路、水和通行邊界仍易辨識。
- 公告板、攤位、雞隻與建物仰賴輪廓和文字標籤識別。比較近遠視野，確認名稱、互動提示及角色仍能從新素材中分辨，並檢查遮擋與遮罩淡化。
- 原有左側標題、目標、背包和底部工具列佔據固定區域。調整後檢查 1280×800 與 1280×720，尤其是底列、長文字、提示、捲動和各面板的點擊範圍。
- 以同一份展示世界副本、相同位置、視野和窗尺寸擷取開關對照。另用新世界檢查初始標示和開局 HUD。對照圖應分別顯示近景、遠景、村莊地標和面板，並避開不同時間點造成的作物差異。

## 核心內容比對與回歸命令

由專案根目錄執行 PowerShell。使用測試專用設定檔和存檔。

```powershell
$baseline = Get-Content -Raw work/village-phase1-core-baseline.json | ConvertFrom-Json
foreach ($entry in $baseline.files.PSObject.Properties) {
    $actual = (Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) { throw "Core file changed: $($entry.Name)" }
}

$godot = (Resolve-Path work/engine/Godot_v4.7.2-stable_win64_console.exe).Path
foreach ($suite in 'test_ui','test_world_art','test_comfort','test_world','test_building',
                    'test_save_schema','test_life','test_regrowth','test_village',
                    'test_festival','test_collections','test_build_catalog') {
    & $godot --headless --path game --script "res://tests/$suite.gd" -- --profile=village-phase1-qa
    if ($LASTEXITCODE -ne 0) { throw "Regression failed: $suite" }
}

& $godot --headless --path game --script res://tests/test_ui.gd -- --profile=village-phase1-preview-qa --village-art-preview
if ($LASTEXITCODE -ne 0) { throw 'Preview UI regression failed' }
```

## 預覽手動檢查

1. 一般啟動與預覽各使用隔離存檔。確認旗標未開時仍顯示 0.5 介面，旗標開啟時載入預覽圖集。
2. 走過渡口、水岸與橋面。測近遠切換、角色轉向、門的進出及屋頂淡化。檢查畫面地標的位置對得上實際互動範圍。
3. 鋤地、播種、澆水、採收，放置木地板。確認動作落在游標所在格、提示可讀，扣料與工具狀態一致。拖曳施工時移到 HUD 放開，確認取消且不扣料。
4. 開地圖、故事手帳、生活圖鑑、設定和建造面板，檢查閉合、焦點、捲動及縮小窗後的邊界。保存退出後再進入，核對世界及角色狀態。
5. 若預覽用於多人，使用隔離伺服器驗證一般客戶端與預覽客戶端可同時進房，觀察同一建物和互動結果。
