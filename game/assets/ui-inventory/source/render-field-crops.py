"""Render authored crops and matching seed bags to one 32px-slot atlas."""

import json
from pathlib import Path

from PIL import Image, ImageDraw


HERE = Path(__file__).resolve().parent
CROPS = ("cotton", "sweet_corn", "strawberry", "star_mushroom")
SEED_COLORS = ("#91a275", "#e6ac4e", "#c87770", "#8790b2")
WINTER_CROPS = ("cabbage", "cauliflower", "sugar_beet", "ginger")
GARDEN_CROPS = ("cucumber", "rice", "sweet_potato", "eggplant")
GARDEN_COLORS = ("#70a366", "#b88d52", "#b96570", "#8c76ae")
LATE_CROPS = ("watermelon", "mist_tea")
LATE_COLORS = ("#658c5f", "#6a9c9a")
MEALS = ("cucumber_salad", "eggplant_rice", "roasted_sweet_potato", "mist_tea_brew")


def crop_image(spec, size=24):
    rows = spec["rows"]
    palette = spec["palette"]
    assert len(rows) == size and all(len(row) == size for row in rows)
    cropped = Image.new("RGBA", (size, size))
    pixels = ImageDraw.Draw(cropped)
    for y, row in enumerate(rows):
        for x, symbol in enumerate(row):
            if symbol != ".":
                pixels.point((x, y), fill=palette[symbol])
    return cropped


def seed_bag(crop, accent):
    bag = Image.new("RGBA", (32, 32))
    art = ImageDraw.Draw(bag)
    art.polygon([(7, 2), (24, 2), (27, 5), (26, 10), (27, 26), (24, 29),
                 (7, 29), (4, 26), (5, 10), (4, 5)], fill="#563a2a")
    art.polygon([(7, 4), (24, 4), (25, 6), (24, 10), (25, 25), (23, 27),
                 (8, 27), (6, 25), (7, 10), (6, 6)], fill="#edd0a0")
    art.polygon([(8, 8), (23, 8), (23, 24), (21, 26), (9, 26), (7, 24)],
                fill="#fff0c7")
    art.line((8, 5, 23, 5), fill="#a98458")
    art.line((9, 6, 22, 6), fill=accent, width=2)
    art.line((7, 10, 8, 23), fill="#d7ac79")
    art.line((24, 10, 24, 24), fill="#c59667")
    bag.alpha_composite(crop.resize((16, 16), Image.Resampling.NEAREST), (8, 8))
    art.line((10, 25, 21, 25), fill=accent)
    art.point((13, 26), fill="#c69b67")
    art.point((18, 26), fill="#c69b67")
    return bag


def draw_crops_and_packets(atlas, source, crops, colors, start_y):
    art = json.loads((HERE / source).read_text(encoding="utf-8"))
    assert set(art) == set(crops)
    for index, (crop, accent) in enumerate(zip(crops, colors, strict=True)):
        image = crop_image(art[crop])
        atlas.alpha_composite(image, (32 * index + 4, start_y + 4))
        atlas.alpha_composite(seed_bag(image, accent), (32 * index, start_y + 32))


def main():
    winter_art = json.loads((HERE / "winter-crops.json").read_text(encoding="utf-8"))
    winter_items = (*WINTER_CROPS, *(f"{crop}_seed" for crop in WINTER_CROPS))
    assert set(winter_art) == set(winter_items)
    late_art = json.loads((HERE / "late-crops-meals.json").read_text(encoding="utf-8"))
    assert set(late_art) == set(LATE_CROPS + MEALS)
    atlas = Image.new("RGBA", (128, 256))
    draw_crops_and_packets(atlas, "field-crops.json", CROPS, SEED_COLORS, 0)
    for index, item in enumerate(winter_items):
        atlas.alpha_composite(crop_image(winter_art[item], size=32),
                             (32 * (index % 4), 64 + 32 * (index // 4)))
    draw_crops_and_packets(atlas, "garden-crops.json", GARDEN_CROPS, GARDEN_COLORS, 128)
    for index, (crop, accent) in enumerate(zip(LATE_CROPS, LATE_COLORS, strict=True)):
        image = crop_image(late_art[crop])
        atlas.alpha_composite(image, (32 * index + 4, 196))
        atlas.alpha_composite(seed_bag(image, accent), (64 + 32 * index, 192))
    for index, meal in enumerate(MEALS):
        atlas.alpha_composite(crop_image(late_art[meal]), (32 * index + 4, 228))
    atlas.save(HERE.parent / "field-crops.png", optimize=True)


if __name__ == "__main__":
    main()
