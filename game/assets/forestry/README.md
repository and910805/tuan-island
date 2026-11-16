# 林務工作站圖集

原稿由內建 ImageGen 產生，保存在 source/atlas.png。生成指令見 source/prompt.txt。使用 Godot 4.7.2 執行 work/generate_forestry_atlas.gd，於 -- 後依序傳入原稿路徑、圖集輸出路徑與 ui-inventory/items.png 路徑，即可重建 atlas.png。

| 素材 | Rect2 x, y, w, h |
| --- | --- |
| forester_kit | 0, 0, 32, 32 |
| 工作站 | 32, 0, 32, 48 |
| 木屑 | 66, 0, 12, 12 |
| 地塊葉片 | 66, 12, 12, 12 |

工作站以格左上往上偏移 16 像素繪製，腳底對齊格內 y30。木屑只顯示在啟用的設備完成循環後 1.5 秒內，減少動態時位置固定。葉片置於作業格右下，不蓋住中央樹苗。

樹苗圖來自 ui-inventory/items.png 的樹苗圖格。早期和較高的樹苗分別在 (0,48,32,32) 與 (32,48,32,32)。
