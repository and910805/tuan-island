# 梳毛刷素材來源

- 工具：內建 image_gen（本機專案用圖，不是網路下載或第三方素材包）。
- 日期：2026-11-18。
- 檔案：grooming-brush.png，生成PNG原檔，保留透明背景，沒有改寫原圖或製作變體。
- 用法：羊卡32px圖示、場景20×20梳毛道具；Godot使用nearest取樣，整數座標往復。影像輸出本身不是原生32×32檔案；32px為提示詞中的邏輯像素設計目標，不能宣稱工具保證逐像素符合。
- 羊的瞇眼畫格：沿用livestock_scene_art.gd原有手工像素頭部，只在梳毛回應期間切換眼部像素。

## 完整生成提示詞

Create ONE production game sprite asset on a truly transparent background: a small handheld sheep wool grooming brush, NO hand, NO animal. Intended for a warm cozy 2D farming game whose native pixel grid is 32 pixels per tile. Show one wooden oval rectangular brush with a caramel wooden back, a small darker brown curved strap on top, and short soft cream bristles underneath. Three-quarter top-down view, oriented diagonally from lower-left to upper-right, matching a top-down pixel life simulation. Strict crisp pixel-art clusters: design on a logical 32x32 pixel grid then enlarge with nearest-neighbor square pixels, no antialiasing, no blur, no gradients, no realistic texture. Palette restricted to warm dark outline #3b2a25, dark wood #6e4a2a, caramel #a0703f, light wood #c98a52, golden highlight #e0b84a, cream #f4e8d2 and cream shadow #d8c6a8. Strong readable silhouette and a few carefully placed shading clusters, formal finished sprite, not a geometric placeholder. Center the brush within the square with a small transparent border, no lettering, no icons around it, no shadow on background, no floor, no border, no sprite sheet, only ONE isolated brush.

參數：transparent_background=true。
