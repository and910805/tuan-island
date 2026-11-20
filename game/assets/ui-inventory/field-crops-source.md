# 棉花、甜玉米、草莓、星菇

`field-crops.png` 為《糰糰島》新增的道具像素圖。第一排從左到右是棉花、甜玉米、草莓、星菇。第二排是對應的種子包。每格 32×32，透明背景。種子包沿用島上紙袋色系，以作物縮圖和封口色辨識品種。

圖稿由 Claude Code Sonnet 5.5 依本專案既有道具和成熟作物造型繪製為原創 24×24 像素矩陣。Codex 配置種子紙袋並檢查實機顯示。未引用外部圖檔。道具與種子沿用既有 ID。

可用 Python 及 Pillow 執行 `source/render-field-crops.py` 重建 PNG。逐像素圖稿位於 `source/field-crops.json`。角色世界中的成長圖仍取自原作物圖集。

PNG SHA-256 `2629fefabf707ecbdca30b7a5e8b528a7b93c15970b22e56d279f2a416241074`。
