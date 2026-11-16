# 手推播種機圖集

原稿由內建 ImageGen 產生，保存在 source/atlas.png。完整提示詞見 source/prompt.txt。使用 Godot 4.7.2 執行 work/generate_seeder_atlas.gd，於 -- 後提供原稿及輸出路徑。

正式圖集為 128×64。四欄依序為上、左、下、右，兩列分別為靜止和播種。各方向的兩幀共用裁切框與最近鄰縮放，腳點為格內 (16,30)。
