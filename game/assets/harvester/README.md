# 手推收割機圖集

內建 ImageGen 原稿與逐字提示詞存於 source/。用 Godot 4.7.2 執行 work/generate_harvester_atlas.gd，於 -- 後提供原稿和輸出 PNG 路徑。

128×96 圖集使用 32×32 格位，四欄依序上、左、下、右。首列靜止，後兩列作業。各方向共用裁切框，最近鄰縮放，腳點 (16,30)。
