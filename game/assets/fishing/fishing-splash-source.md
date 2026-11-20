# 釣魚入水與起魚的像素水花

透明 PNG，96×64，六張 32×32。上排為浮標入水，下排為起魚。各列由左至右為初始、散開與消退。將每格 (16, 28) 對準浮標所在的水面位置，保留最近鄰取樣。

Windows 預覽以遊戲的釣魚事件播放，保留原有的咬鉤提示、音效、捕獲數值、存檔與取消動作。2026-11-20 起正式版 `scripts/fishing_art.gd` 的 `draw_splash_frame` 使用這張圖：上排在浮標入水與取消時播放，下排在起魚時播放，減少動態時不播放。

## 生成描述

Create a production transparent RGBA pixel-art sprite sheet of cozy top-down farming game fishing water effects, 3 columns by 2 rows, perfectly regular horizontal and vertical framing, generous empty transparent gutter around each of six independent objects. Water only. Designed for 32×32 output cells, readable clusters, hard 1px corners, lightweight hand-clustered anime pixel VFX and no smooth blur. Palette small: pale mint foam, off-white tips, a medium cyan, muted turquoise, chosen to stand out on a deep blue-green river. Top row left to right: bobber landing as a concise small white crown of water (without bobber), spreading low broken oval splash and detached drops, wide low broken ring with very few droplets. Bottom row: a fish-on-hook splash as a taller asymmetrical forked water burst with three brights, an expanded broken splash with droplets lifted high at outer edges, a low narrow foam trace with 2 drops at outer edges. Orient all in the same 3/4 top-down perspective. Keep each sprite centered in respective cell, relative real water contact line close to lower third of the subject. NO fish, float, rod, waves filling backgrounds, terrain, checkered background, texts, boxes, frame guides, shapes outside six cells. True alpha outside water.
