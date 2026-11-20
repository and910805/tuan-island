"""Rebuild the 32 px tool icons from their original pixel drawings."""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def draw_copper_pick(folder: Path) -> None:
    art = Image.new('RGBA', (32, 32))
    pen = ImageDraw.Draw(art)
    outline = '#342735'
    # Step the diagonal handle and curve the head around its central socket.
    pen.polygon([(4,25),(6,25),(6,23),(8,23),(8,21),(10,21),(10,19),(12,19),(12,17),(14,17),(14,15),(16,15),(16,12),(20,13),(22,16),(20,18),(18,18),(18,20),(16,20),(16,22),(14,22),(14,24),(12,24),(12,26),(10,26),(10,28),(8,28),(8,29),(5,29),(4,28)],fill=outline)
    pen.polygon([(5,26),(7,26),(7,24),(9,24),(9,22),(11,22),(11,20),(13,20),(13,18),(15,18),(15,16),(17,14),(20,16),(17,18),(17,20),(15,20),(15,22),(13,22),(13,24),(11,24),(11,26),(9,26),(9,28),(6,28),(5,27)],fill='#a15a46')
    pen.line([(6,26),(17,15)], fill='#e5a665', width=1)
    pen.polygon([(6,4),(11,3),(16,3),(16,4),(20,4),(20,5),(23,5),(23,7),(25,7),(25,9),(27,9),(27,12),(28,12),(28,16),(29,16),(29,21),(27,22),(25,20),(25,17),(24,17),(24,14),(22,14),(22,12),(20,12),(20,10),(17,10),(17,9),(13,9),(13,8),(8,8),(8,7),(6,7)],fill=outline)
    pen.polygon([(8,5),(12,4),(16,4),(16,5),(20,5),(20,6),(22,6),(22,8),(24,8),(24,10),(26,10),(26,13),(27,13),(27,17),(28,17),(28,20),(27,20),(26,18),(26,16),(25,16),(25,13),(23,13),(23,11),(21,11),(21,9),(18,9),(18,8),(13,8),(13,7),(9,7),(8,6)],fill='#b45e45')
    pen.line([(9,5),(16,5),(16,6),(20,6),(20,7),(22,7),(22,9),(24,9),(24,11),(26,11),(26,14),(27,14),(27,18)],fill='#eeac71',width=1)
    pen.line([(12,6),(16,6),(16,7),(19,7),(19,8)],fill='#ffd7a0',width=1)
    pen.line([(23,10),(23,11),(25,11),(25,13),(26,13),(26,15)],fill='#70b2a2',width=1)
    pen.polygon([(14,12),(17,9),(20,10),(22,13),(20,16),(17,16),(15,15)],fill=outline)
    pen.polygon([(15,12),(17,10),(19,10),(21,13),(19,15),(17,15),(16,14)],fill='#784e48')
    pen.line([(16,12),(17,11),(18,11),(19,12)],fill='#e6ae78',width=1)
    pen.point((18,13),fill='#fff1b7')
    art.save(folder / 'copper-pick.png')


def draw_advanced_picks(folder: Path) -> None:
    for filename, metal, shade, rim, pale, grip, stitch, socket, jewel, bright in [
        ('iron-pick.png','#7f91a6','#4d5975','#b1beca','#eaf3ef','#64433e','#d29369','#b78648','#d4a760','#fff2c5'),
        ('precision-pick.png','#587e95','#394661','#9bd1cf','#e9ffed','#52445e','#9f8291','#bf9667','#7ad4be','#f8ffe0'),
    ]:
        canvas = Image.new('RGBA', (32,32))
        draw = ImageDraw.Draw(canvas)
        outline = '#2c2633'
        draw.polygon([(4,26),(7,23),(12,18),(16,14),(18,12),(22,15),(21,18),(17,20),(12,25),(8,29),(5,29)], fill=outline)
        draw.polygon([(5,26),(8,23),(13,18),(17,14),(19,14),(20,15),(20,17),(16,20),(11,25),(7,28),(6,28)], fill=grip)
        draw.line([(6,26),(18,14)], fill=stitch, width=2)
        draw.line([(7,24),(9,26)],fill=outline,width=1)
        draw.line([(9,22),(11,24)],fill=outline,width=1)
        draw.polygon([(4,7),(6,4),(11,3),(16,3),(17,4),(22,4),(25,6),(27,9),(29,13),(29,19),(27,22),(25,20),(24,16),(22,13),(20,11),(16,10),(11,8),(7,8),(5,9)],fill=outline)
        draw.polygon([(6,7),(7,5),(12,4),(16,4),(17,5),(22,5),(24,7),(26,9),(28,13),(28,18),(27,20),(26,19),(25,16),(23,13),(20,10),(16,9),(11,7),(7,7)],fill=metal)
        draw.line([(7,6),(12,5),(16,5),(17,6),(22,6),(25,9),(27,13),(27,16)],fill=rim,width=1)
        draw.line([(8,5),(12,4),(15,4),(16,5),(18,5)],fill=pale,width=1)
        draw.line([(20,9),(23,11),(26,16),(27,19)],fill=shade,width=1)
        draw.polygon([(12,10),(17,8),(21,10),(23,14),(20,17),(16,16),(13,14)],fill=outline)
        draw.polygon([(14,11),(17,9),(20,11),(21,14),(20,15),(16,15),(14,13)],fill=socket)
        draw.polygon([(16,12),(17,10),(19,11),(20,13),(18,15),(16,14)],fill=jewel)
        draw.line([(16,12),(17,11),(18,11)],fill=bright,width=1)
        if filename == 'precision-pick.png':
            draw.line([(9,7),(11,6),(13,6)],fill=jewel,width=1)
            draw.point((24,9),fill=bright)
            draw.line([(25,11),(26,13)],fill=jewel,width=1)
            draw.polygon([(4,27),(6,26),(8,27),(7,29),(5,29)],fill=socket)
            draw.point((5,27),fill=bright)
        canvas.save(folder / filename)


def draw_axes(folder: Path) -> None:
    styles = (
        ('copper', '#be704f', '#854746', '#efad75', '#ffe0a8', '#845044', '#d69765'),
        ('iron', '#8297b0', '#52627b', '#bccad7', '#f1f6eb', '#704a46', '#b87d5b'),
        ('precision', '#508596', '#3a536c', '#87c9c8', '#e3ffef', '#594764', '#a47a8b'),
    )
    for name, blade, shadow, rim, edge, wood, grip in styles:
        image = Image.new('RGBA', (32, 32))
        pen = ImageDraw.Draw(image)
        dark = '#302638'
        pen.polygon([(3,26),(6,22),(11,17),(15,13),(18,9),(21,8),(24,11),(24,14),(19,18),(14,23),(10,28),(7,30),(4,29)], fill=dark)
        pen.polygon([(4,26),(7,23),(12,18),(16,14),(19,10),(21,10),(23,12),(23,13),(18,17),(13,22),(9,27),(6,29),(5,28)], fill=wood)
        pen.line([(6,26),(19,13)],fill=grip,width=2)
        pen.line([(6,24),(8,26)],fill=dark,width=1)
        pen.line([(8,22),(10,24)],fill=dark,width=1)
        pen.polygon([(12,5),(14,3),(18,3),(21,5),(24,5),(26,4),(28,3),(30,4),(30,9),(29,13),(27,16),(24,18),(20,18),(17,15),(16,12),(13,11),(11,9)],fill=dark)
        pen.polygon([(12,8),(14,4),(18,4),(21,6),(25,6),(28,4),(29,5),(29,9),(28,13),(26,16),(24,17),(20,17),(17,14),(17,11),(14,10)],fill=blade)
        pen.line([(13,8),(15,5),(18,5),(21,7),(24,7),(26,6)],fill=rim,width=1)
        pen.line([(16,11),(18,14),(20,16),(23,16),(26,14)],fill=shadow,width=1)
        pen.line([(28,5),(28,9),(27,12),(26,14),(24,16)],fill=edge,width=1)
        pen.polygon([(15,8),(17,7),(20,9),(21,11),(19,13),(17,12),(15,10)],fill=dark)
        pen.polygon([(16,8),(18,8),(20,10),(19,12),(17,11),(16,10)],fill=grip)
        pen.point((18,9),fill=edge)
        if name == 'precision':
            pen.polygon([(20,10),(22,8),(25,9),(25,11),(23,13),(21,13)],fill='#31536a')
            pen.polygon([(21,10),(22,9),(24,9),(24,11),(23,12),(22,12)],fill='#83d9bc')
            pen.point((22,10),fill=edge)
            pen.polygon([(4,26),(6,25),(8,26),(7,28),(5,29),(4,28)],fill='#d6a572')
        image.save(folder / f'{name}-axe.png')


def draw_hoes(folder: Path) -> None:
    for name, metal, shade, hi, wood, trim, binding in (
        ('copper','#bd704d','#814748','#f9c489','#744637','#c08255','#e3a66b'),
        ('iron','#8599ac','#4f6078','#edf4e9','#654843','#b58061','#dfad71'),
        ('precision','#5b8997','#364e67','#b9fff0','#53425e','#99717e','#7fdac0'),
    ):
        art=Image.new('RGBA',(32,32))
        pen=ImageDraw.Draw(art)
        ink='#2e2737'
        pen.polygon([(4,27),(6,23),(9,20),(13,16),(17,12),(20,9),(23,8),(25,10),(25,13),(22,16),(18,19),(14,23),(10,27),(8,30),(5,30)],fill=ink)
        pen.polygon([(5,27),(7,24),(11,20),(14,17),(18,13),(21,10),(23,9),(24,11),(24,12),(21,15),(17,19),(13,23),(9,27),(7,29),(6,29)],fill=wood)
        pen.line([(7,26),(21,12)],fill=trim,width=2)
        pen.line([(7,24),(9,26)],fill=ink,width=1)
        pen.line([(9,22),(11,24)],fill=ink,width=1)
        pen.polygon([(16,5),(18,3),(23,3),(25,5),(27,7),(28,11),(29,14),(29,18),(27,20),(23,20),(21,18),(21,15),(19,13),(18,10),(16,8)],fill=ink)
        pen.polygon([(17,6),(19,4),(23,4),(25,6),(26,8),(27,11),(28,15),(28,17),(26,19),(23,19),(22,17),(22,14),(20,12),(19,9),(17,8)],fill=metal)
        pen.line([(18,6),(20,5),(22,5),(24,7),(25,9)],fill=shade,width=1)
        pen.line([(18,5),(20,4),(22,4),(24,6),(26,8),(27,11),(28,15),(28,17)],fill=hi,width=1)
        pen.line([(23,18),(24,19),(26,19),(27,18)],fill=hi,width=1)
        pen.polygon([(18,9),(20,8),(22,10),(22,12),(20,14),(18,13),(17,11)],fill=ink)
        pen.polygon([(18,11),(20,9),(21,10),(21,12),(20,13),(18,12)],fill=binding)
        pen.point((20,10),fill=hi)
        if name=='precision':
            pen.line([(24,14),(26,15),(25,17)],fill=binding,width=1)
            pen.point((25,15),fill='#ebfff4')
        art.save(folder/f'{name}-hoe.png')


def draw_watering_cans(folder: Path) -> None:
    for name,base,shadow,light,rim in (
        ('copper','#bc7451','#844c49','#ebb379','#ffe2ae'),
        ('iron','#8296a8','#50617a','#b5c6cf','#edf4e9'),
        ('precision','#538b99','#3c546b','#87c2c1','#e0fff0'),
    ):
        image=Image.new('RGBA',(32,32)); pen=ImageDraw.Draw(image); ink='#332737'
        pen.polygon([(7,12),(7,7),(10,4),(17,4),(20,6),(21,9),(23,9),(26,6),(29,6),(30,8),(30,11),(28,13),(25,13),(23,16),(22,23),(20,27),(9,28),(5,25),(4,19),(2,17),(2,13),(4,11)],fill=ink)
        pen.polygon([(8,12),(8,8),(11,5),(17,5),(19,7),(20,10),(18,11),(17,8),(15,7),(12,7),(10,9),(10,12)],fill=light)
        pen.polygon([(6,13),(9,10),(18,10),(21,12),(22,12),(26,8),(29,7),(29,10),(27,12),(24,12),(21,16),(21,22),(19,26),(10,27),(6,24),(5,20),(3,17),(3,14),(5,12)],fill=base)
        pen.polygon([(6,15),(9,13),(17,13),(20,15),(20,21),(18,25),(11,26),(7,24),(6,21)],fill=shadow)
        pen.polygon([(7,16),(10,14),(17,14),(19,16),(19,21),(17,24),(11,25),(8,23),(7,20)],fill=base)
        pen.line([(8,17),(9,16),(12,16),(14,15),(17,15)],fill=light,width=1)
        pen.line([(9,18),(11,17),(13,17)],fill=rim,width=1)
        pen.line([(21,13),(24,11),(27,9)],fill=light,width=1)
        pen.line([(25,9),(27,7),(29,7),(29,9)],fill=rim,width=1)
        if name=='precision':
            pen.polygon([(12,20),(14,18),(16,20),(14,23)],fill='#77d1ae')
            pen.point((14,19),fill=rim)
        image.save(folder/f'{name}-can.png')


def draw_rods(folder: Path) -> None:
    for name, rod, glow, hardware, float_color in (
        ('copper','#b66a4d','#f0b473','#d99261','#d46e58'),
        ('iron','#7a8fa6','#e2efed','#9bb2c5','#6a91c1'),
        ('precision','#557d93','#c1fbeb','#8cd4c2','#77d1a7'),
    ):
        tile=Image.new('RGBA',(32,32)); pen=ImageDraw.Draw(tile)
        ink='#2c2836'
        pen.line([(7,26),(11,21),(15,17),(20,11),(23,7),(26,5),(28,6)],fill=ink,width=5)
        pen.line([(7,26),(11,21),(15,17),(20,11),(23,7),(26,5),(28,6)],fill=rod,width=3)
        pen.line([(7,25),(11,20),(15,16),(20,10),(23,6),(26,4),(28,5)],fill=glow,width=1)
        pen.polygon([(4,27),(6,24),(8,22),(10,22),(12,24),(10,28),(8,30),(5,30)],fill=ink)
        pen.polygon([(5,28),(7,25),(9,23),(10,24),(9,27),(7,29),(6,29)],fill='#b48560')
        pen.line([(6,26),(8,28)],fill='#62463d',width=1)
        pen.line([(8,24),(10,26)],fill='#62463d',width=1)
        pen.polygon([(10,20),(13,19),(16,21),(16,24),(13,26),(10,24)],fill=ink)
        pen.polygon([(11,21),(13,20),(15,22),(14,24),(12,24),(11,23)],fill=hardware)
        pen.point((13,21),fill=glow)
        pen.line([(28,6),(27,11),(25,15),(24,19),(24,24)],fill='#b6c7bf',width=1)
        pen.polygon([(24,22),(26,24),(26,27),(24,29),(22,27),(22,24)],fill=ink)
        pen.polygon([(24,23),(25,25),(25,27),(23,27),(23,25)],fill=float_color)
        pen.point((24,24),fill='#fff1cb')
        if name=='precision':
            pen.point((20,10),fill='#f6ffe1'); pen.point((21,9),fill=hardware)
        tile.save(folder/f'{name}-rod.png')


def draw_seed_pouches(folder: Path) -> None:
    for name, fabric, shadow, fold, clasp, highlight in (
        ('copper','#c48b67','#855042','#e3b178','#d88855','#ffe1aa'),
        ('iron','#8b9eaa','#59687a','#bbc7c5','#8cabc4','#f0f7e9'),
        ('precision','#588f8b','#3f5267','#8bbab0','#94d7b4','#eaffdf'),
    ):
        image=Image.new('RGBA',(32,32)); pen=ImageDraw.Draw(image); ink='#342838'
        pen.polygon([(8,9),(6,5),(8,3),(12,4),(15,2),(18,4),(23,3),(25,6),(23,10),(25,12),(25,15),(28,21),(28,26),(25,29),(20,30),(11,30),(6,28),(4,25),(4,20),(7,15),(7,12)],fill=ink)
        pen.polygon([(9,9),(7,5),(9,4),(13,6),(15,3),(18,6),(22,4),(24,6),(22,9),(23,12),(24,15),(27,21),(27,25),(24,28),(20,29),(11,29),(7,27),(5,25),(5,20),(8,15),(8,12)],fill=fabric)
        pen.polygon([(5,22),(8,25),(12,27),(20,27),(25,25),(27,22),(27,25),(24,28),(20,29),(11,29),(7,27),(5,25)],fill=shadow)
        pen.line([(8,19),(9,16),(11,14),(12,13)],fill=fold,width=1)
        pen.line([(8,20),(8,23),(10,25),(12,25)],fill=fold,width=1)
        pen.line([(8,10),(12,9),(19,9),(23,10)],fill=ink,width=2)
        pen.line([(8,10),(12,10),(19,10),(23,11)],fill=clasp,width=1)
        pen.polygon([(13,9),(17,8),(20,10),(20,13),(17,15),(14,14),(12,12)],fill=ink)
        pen.polygon([(14,10),(17,9),(19,10),(19,12),(17,14),(14,13),(13,12)],fill=clasp)
        pen.point((16,10),fill=highlight)
        pen.polygon([(15,23),(15,20),(18,18),(20,19),(19,22),(17,23)],fill='#536852')
        pen.line([(16,23),(19,19)],fill='#a7ca88',width=1)
        if name=='precision':
            pen.point((10,16),fill=highlight); pen.point((22,24),fill=clasp)
        image.save(folder/f'{name}-seed-pouch.png')


def draw_sickles(folder: Path) -> None:
    for name, base, shadow, light, rim in (
        ('copper','#bc7451','#87464c','#e4a576','#ffe1a8'),
        ('iron','#8299af','#4f6078','#b7cad3','#eef6ef'),
        ('precision','#548b9a','#394f69','#88cbc8','#e7fff0'),
    ):
        image=Image.new('RGBA',(32,32)); pen=ImageDraw.Draw(image); ink='#312637'
        pen.polygon([(4,27),(6,22),(9,18),(12,15),(15,15),(18,18),(14,23),(11,27),(8,30),(5,29)],fill=ink)
        pen.polygon([(5,27),(7,23),(10,19),(13,16),(15,17),(16,18),(13,22),(10,26),(7,29)],fill='#875744')
        pen.line([(6,26),(12,19),(14,17)],fill='#dea66f',width=2)
        pen.line([(7,23),(9,25)],fill='#523f3e',width=1)
        pen.line([(9,21),(11,23)],fill='#523f3e',width=1)
        pen.polygon([(12,15),(15,14),(19,14),(22,12),(24,9),(24,6),(22,4),(19,4),(17,5),(17,3),(20,1),(25,1),(29,4),(30,8),(29,13),(27,17),(23,20),(18,21),(14,20),(12,17)],fill=ink)
        pen.polygon([(13,16),(15,15),(19,15),(22,13),(24,11),(25,8),(25,6),(23,3),(20,3),(19,3),(21,2),(25,2),(28,4),(29,8),(28,13),(26,17),(23,19),(18,20),(15,19),(13,17)],fill=base)
        pen.line([(15,18),(18,19),(23,18),(26,16),(28,11),(28,8)],fill=shadow,width=1)
        pen.line([(16,15),(19,15),(22,13),(24,11),(25,8),(25,6),(23,3),(21,3)],fill=light,width=1)
        pen.line([(23,12),(24,10),(25,8),(25,6)],fill=rim,width=1)
        pen.rectangle((13,16,15,18),fill='#7c5a54')
        pen.point((14,16),fill=rim)
        if name=='precision':
            pen.point((22,15),fill='#76d4b7'); pen.point((24,13),fill=rim)
        image.save(folder/f'{name}-sickle.png')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output
    output.mkdir(parents=True, exist_ok=True)
    draw_copper_pick(output)
    draw_advanced_picks(output)
    draw_axes(output)
    draw_hoes(output)
    draw_watering_cans(output)
    draw_rods(output)
    draw_seed_pouches(output)
    draw_sickles(output)


if __name__ == "__main__":
    main()
