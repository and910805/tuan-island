# 工具升級像素圖

銅、鐵、精密三種等級各有十字鎬、斧頭、鋤頭、灑水壺、釣竿、種子袋和鐮刀。21 張圖均由專案的 Python／Pillow 繪製程式以 32×32 像素和透明背景輸出。

原始繪製指令已整理至 `source/render-tool-icons.py`。執行時指定輸出目錄，便可在獨立目錄重建。與 r24 候選包對應的 21 張 PNG 已逐位元比對相同。

```powershell
python game/assets/ui-inventory/source/render-tool-icons.py work/tool-icon-rebuild
```
