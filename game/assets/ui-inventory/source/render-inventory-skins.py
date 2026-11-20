"""Rebuild the original inventory and HUD nine-slice textures."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def draw_slot_and_paper(output: Path) -> None:
    paper = Image.new("RGBA", (16, 16), "#f4e4be")
    draw = ImageDraw.Draw(paper)
    draw.rectangle((0, 0, 15, 15), outline="#d3b47d")
    draw.rectangle((1, 1, 14, 14), outline="#faedcf")
    for x, y in [(4, 4), (8, 5), (6, 8), (11, 10), (4, 11)]:
        draw.point((x, y), fill="#ebd8ad")
    paper.save(output / "paper.png")

    slot = Image.new("RGBA", (16, 16), "#dbc193")
    draw = ImageDraw.Draw(slot)
    draw.rectangle((0, 0, 15, 15), outline="#77543a")
    draw.line((1, 1, 14, 1, 14, 13), fill="#edd7aa")
    draw.line((2, 14, 13, 14), fill="#77543a")
    for x, y in [(5, 6), (9, 9), (10, 5), (6, 11)]:
        draw.point((x, y), fill="#edd7aa")
    slot.save(output / "normal.png")

    focus = Image.new("RGBA", (16, 16))
    draw = ImageDraw.Draw(focus)
    draw.rectangle((0, 0, 15, 15), outline="#36492f")
    draw.rectangle((1, 1, 14, 14), outline="#fff3bf")
    focus.save(output / "focus.png")


def draw_button_states(output: Path) -> None:
    for name, fill, edge, light in [
        ("button_normal", "#e8d2a7", "#79583b", "#f6e6c0"),
        ("button_hover", "#f1deaf", "#89633e", "#fff1cc"),
        ("button_pressed", "#466447", "#304a35", "#6b855b"),
    ]:
        button = Image.new("RGBA", (16, 16), fill)
        pen = ImageDraw.Draw(button)
        pen.rectangle((0, 0, 15, 15), outline=edge)
        pen.line((1, 13, 1, 1, 14, 1), fill=light)
        pen.line((2, 14, 14, 14, 14, 2), fill=edge)
        button.save(output / f"{name}.png")


def draw_slot_states(output: Path) -> None:
    for name, fill, edge, rim in [
        ("hover", "#dee5b8", "#6c7950", "#f5efce"),
        ("selected", "#476347", "#344b36", "#f6df98"),
        ("pressed", "#537353", "#344b36", "#ffedab"),
    ]:
        slot = Image.new("RGBA", (16, 16), fill)
        draw = ImageDraw.Draw(slot)
        draw.rectangle((0, 0, 15, 15), outline=edge)
        draw.rectangle((1, 1, 14, 14), outline=rim)
        slot.save(output / f"{name}.png")


def draw_frame(output: Path) -> None:
    PAPER = "#f7e7c4"

    # The 16px source becomes a 32px sheet with an 8px nine-slice margin.
    # Keep all wood inside its four-pixel source border.
    frame = Image.new("RGBA", (16, 16), PAPER)
    draw = ImageDraw.Draw(frame)
    draw.rectangle((0, 0, 15, 15), outline="#60452e")
    draw.rectangle((1, 1, 14, 14), outline="#d1a565")
    draw.rectangle((2, 2, 13, 13), outline="#ac7743")
    draw.rectangle((3, 3, 12, 12), outline="#815a37")
    for x, y in [(2, 2), (12, 2), (2, 12), (12, 12)]:
        draw.rectangle((x, y, x + 1, y + 1), fill="#5c4433")
        draw.point((x, y), fill="#e7c78a")
    for x, y in [(6, 2), (8, 13), (2, 7), (13, 8)]:
        draw.point((x, y), fill="#95653e")

    texture = frame.resize((32, 32), Image.Resampling.NEAREST)
    draw = ImageDraw.Draw(texture)
    for x, y in [(0, 0), (31, 0), (0, 31), (31, 31)]:
        draw.point((x, y), fill=(0, 0, 0, 0))

    assert set(texture.crop((8, 8, 24, 24)).getdata()) == {(247, 231, 196, 255)}
    texture.save(output / "frame.png")


def draw_hud_panels(output: Path) -> None:
    p = output
    for name, palette in {
        "hud_badge": ("#49362f", "#b57263", "#f4c5ab", "#fff0dd"),
        "hud_wood": ("#402e26", "#85503a", "#cf9566", "#ae7150"),
        "life_paper": ("#49362f", "#b57263", "#f2cbb1", "#fcebd2"),
    }.items():
        im = Image.new("RGBA", (20, 20))
        d = ImageDraw.Draw(im)
        for i, color in enumerate(palette):
            a = i * 2
            b = 19 - a
            cut = max(1, 3 - i)
            d.polygon(
                [
                    (a + cut, a),
                    (b - cut, a),
                    (b, a + cut),
                    (b, b - cut),
                    (b - cut, b),
                    (a + cut, b),
                    (a, b - cut),
                    (a, a + cut),
                ],
                fill=color,
            )
        im.save(p / (name + ".png"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output
    output.mkdir(parents=True, exist_ok=True)
    draw_slot_and_paper(output)
    draw_button_states(output)
    draw_slot_states(output)
    draw_frame(output)
    draw_hud_panels(output)


if __name__ == "__main__":
    main()
