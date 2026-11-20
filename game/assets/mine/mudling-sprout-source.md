# 泥團寶角色素材

透明 PNG，畫布 64×64，四張 32×32。由左至右、由上至下是待機、壓低蓄力、跳起與放鬆。單格繪製的腳點是 (16, 30)，可用最近鄰放大。跳起的位移由遊戲繪製層處理。場景預覽用了獨立的繪製節點，現有側洞事件尚未使用新圖。

## 生成描述

Create the original Mudling (泥團寶) for a cozy Taiwanese farm life simulator. Deliver a transparent RGBA pixel-art 2x2 sprite sheet, perfectly even cell quadrants with generous transparent gutters; no text, mockups, ground, crop marks, panels, backdrop or extra sprite. Same character in each quadrant, identical direction, centered independently and with same foot baseline. Design: cute single bean-shaped ball of warm terracotta-colored mud, a little soft ochre speckling, petite dark eyes, a clearly visible two-leaf green sprout with gently off-center stalk on its head, warm rich umber outline, one small gold highlight on each brighter leaf. Front 3/4 view, cozy, read clearly at 32 pixels, deliberate blocky 1-3 pixel clusters on intended 32x32 grid, no anti-aliased glossy gradient. Natural muted tones as in hand-crafted Taiwanese rural pixel RPG. Top-left ordinary idle content, top-right crouches alert with forked leaves swept backward, bottom-left lifted long body and determined face (no motion effects or shadow), bottom-right relaxed pleased with eyes closed after receiving food, no prop. Each subject wholly inside its respective cell, similar scale. True alpha background entirely transparent.

## Windows 遊戲畫面驗收

第 1 層側洞地圖，1280×800。動態預覽以 20 FPS 擷取 64 張遊戲畫面，沿用現有 1.5 秒蓄力長度，跳起後有落地陰影。預覽在測試用繪製層播放，尚未接到玩家按鍵或房間同步。正式接入可沿用側洞事件送出的蓄力和收尾狀態，減少動態設定時須保留姿勢差異供玩家辨識。
