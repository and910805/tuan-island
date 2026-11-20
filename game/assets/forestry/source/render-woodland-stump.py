"""Rebuild the 32 px woodland stump from its original drawing."""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def render(output: Path) -> None:
    image=Image.new('RGBA',(32,32))
    pen=ImageDraw.Draw(image)
    pen.polygon([(3,23),(8,21),(22,21),(29,23),(29,26),(25,28),(8,28),(3,26)],fill='#55744880')
    pen.polygon([(7,23),(8,20),(11,19),(10,17),(10,11),(12,8),(16,7),(22,8),(24,10),(24,18),(27,20),(28,23),(26,25),(21,24),(18,26),(12,25),(6,26),(5,24)],fill='#40302c')
    pen.polygon([(8,23),(10,21),(13,20),(12,17),(12,11),(14,9),(18,8),(22,9),(23,11),(23,18),(25,20),(27,22),(26,24),(21,23),(18,25),(13,24),(8,25),(6,24)],fill='#886044')
    pen.line([(13,15),(13,19),(11,21),(10,23)],fill='#ba8556',width=1)
    pen.line([(16,15),(15,20),(15,23)],fill='#b18154',width=1)
    pen.line([(19,15),(20,19),(21,22)],fill='#573c36',width=1)
    pen.line([(22,14),(22,18),(24,20),(25,22)],fill='#b58354',width=1)
    pen.polygon([(10,11),(12,8),(16,7),(21,7),(24,10),(24,13),(21,15),(16,16),(12,14)],fill='#503832')
    pen.polygon([(11,11),(13,9),(17,8),(21,8),(23,10),(23,12),(21,14),(16,15),(13,14),(11,12)],fill='#d7a86f')
    pen.line([(12,11),(14,9),(19,9),(22,10)],fill='#f2ca8a',width=1)
    pen.line([(14,12),(15,11),(19,10),(21,11),(21,12),(19,13),(16,13),(15,12)],fill='#ad7850',width=1)
    pen.point((18,12),fill='#855a43')
    pen.line([(7,24),(8,23),(10,23)],fill='#77974a',width=1)
    pen.line([(23,24),(25,24),(26,23)],fill='#739149',width=1)
    image.save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output
    output.parent.mkdir(parents=True, exist_ok=True)
    render(output)
