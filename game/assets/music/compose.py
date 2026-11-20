"""Render the original 糰糰島 soundtrack. Requires NumPy and FFmpeg on PATH."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess

import numpy as np


RATE = 24000
BARS = 16
MUSIC = Path(__file__).resolve().parent
MAJOR = (0, 2, 4, 5, 7, 9, 11)
MINOR = (0, 2, 3, 5, 7, 8, 10)
DORIAN = (0, 2, 3, 5, 7, 9, 10)
MIXOLYDIAN = (0, 2, 4, 5, 7, 9, 10)

# Key, scale, tempo, lead, backing instrument, chord roots, two-measure motif.
SCORES = {
    "title": (65, MAJOR, 76, "piano", "harp", (0, 3, 5, 4), (0, 2, 4, 5, 4, 2, 1, 0)),
    "festival_epilogue": (65, MAJOR, 66, "mallet", "harp", (0, 5, 3, 4), (0, 2, 4, None, 5, 4, 2, 0)),
    "story_bridge": (62, MAJOR, 91, "mallet", "harp", (0, 3, 4, 0), (0, 2, 4, 7, 6, 5, 4, 0)),
    "story_picnic": (65, MAJOR, 110, "guitar", "mallet", (0, 4, 3, 0), (2, 4, 5, 4, 2, None, 1, 0)),
    "story_kitchen": (60, MAJOR, 90, "piano", "harp", (0, 5, 3, 0), (4, 2, 0, 2, 3, 4, 2, 0)),
    "story_hoist": (57, DORIAN, 94, "mallet", "piano", (0, 3, 4, 0), (0, 1, 3, 5, 7, 6, 4, 0)),
    "story_boat": (67, MIXOLYDIAN, 96, "reed", "guitar", (0, 6, 3, 0), (0, 4, 7, 9, 8, 6, 4, 0)),
    "home": (62, MIXOLYDIAN, 92, "mallet", "harp", (0, 3, 0, 4), (0, 2, 4, None, 5, 4, 1, 2)),
    "home_night": (62, MAJOR, 69, "piano", "harp", (0, 5, 3, 0), (4, None, 2, 0, 2, None, -1, 0)),
    "home_forest": (64, DORIAN, 79, "harp", "guitar", (0, 3, 5, 0), (0, 1, 3, 4, None, 5, 3, 2)),
    "home_river": (67, MAJOR, 88, "reed", "harp", (0, 4, 1, 3), (5, 4, 2, 1, 2, None, 4, 6)),
    "home_coast": (65, MIXOLYDIAN, 74, "guitar", "pad", (0, 6, 3, 4), (4, None, 3, 2, 0, 2, 3, None)),
    "home_courtyard": (60, MIXOLYDIAN, 71, "harp", "guitar", (0, 6, 3, 0), (2, 4, None, 5, 3, 1, None, 0)),
    "home_south_shore": (66, DORIAN, 65, "reed", "pad", (0, 3, 6, 0), (4, 5, None, 3, 2, None, 1, 0)),
    "home_star_shore": (68, MAJOR, 77, "mallet", "harp", (0, 3, 1, 4), (4, None, 7, 6, 3, 5, 2, None)),
    "home_market": (72, MAJOR, 109, "mallet", "piano", (0, 1, 4, 3), (0, 4, 3, 2, 4, 5, 6, 4)),
    "house_interior": (60, MAJOR, 72, "piano", "guitar", (0, 5, 3, 0), (2, None, 4, 2, 1, 0, -2, 0)),
    "greenhouse_interior": (67, MAJOR, 89, "harp", "mallet", (0, 2, 3, 4), (4, 6, 7, None, 5, 4, 2, 4)),
    "island_voyage": (62, MIXOLYDIAN, 81, "reed", "guitar", (0, 6, 3, 4), (0, 2, 5, 4, None, 2, 1, 0)),
    "lanyang": (67, MAJOR, 86, "reed", "piano", (0, 3, 1, 4), (4, 2, 0, 1, 2, 5, 4, None)),
    "jinguashi": (62, DORIAN, 77, "guitar", "mallet", (0, 5, 3, 4), (0, None, -1, 2, 4, 2, 1, -2)),
    "toucheng": (60, MAJOR, 103, "guitar", "piano", (0, 4, 5, 3), (2, 4, 2, 4, 7, 6, 4, None)),
    "ruifang": (65, MIXOLYDIAN, 98, "mallet", "guitar", (0, 5, 3, 4), (0, 0, 3, 4, None, 2, 4, 5)),
    "jiufen": (63, MINOR, 80, "piano", "guitar", (0, 2, 3, 4), (4, 5, 7, 5, 3, 2, None, 0)),
    "maokong": (64, DORIAN, 83, "reed", "harp", (0, 3, 2, 4), (2, None, 4, 2, 1, 0, -2, 1)),
    "maokong_tea_house": (65, MAJOR, 69, "mallet", "guitar", (0, 2, 3, 0), (4, None, 2, 1, 0, 2, None, 4)),
    "yingge": (66, MAJOR, 94, "mallet", "piano", (0, 1, 3, 4), (2, 0, 2, 5, 4, None, 2, 0)),
    "yingge_pottery_workshop": (63, MIXOLYDIAN, 86, "mallet", "harp", (0, 3, 6, 0), (1, 4, 2, None, 3, 5, 2, 0)),
    "tianwei": (69, MAJOR, 100, "guitar", "harp", (0, 3, 5, 1), (0, 1, 2, 4, 5, 4, 2, 5)),
    "beimen": (60, MIXOLYDIAN, 72, "reed", "mallet", (0, 6, 3, 0), (4, None, 3, 0, -1, None, 1, 0)),
    "beimen_salt_pans": (69, DORIAN, 84, "mallet", "harp", (0, 1, 6, 0), (0, 2, None, 4, 5, 4, 2, None)),
    "jiaoxi": (61, MAJOR, 68, "piano", "harp", (0, 3, 1, 5), (2, 4, None, 4, 1, None, 0, 2)),
    "warm_springs_interior": (65, DORIAN, 66, "guitar", "mallet", (0, 3, 2, 0), (4, None, 3, 1, 2, None, -1, 0)),
    "bamboo_grove": (62, MINOR, 75, "reed", "guitar", (0, 3, 6, 4), (0, 2, None, 1, 4, 3, 2, None)),
    "star_garden": (68, MAJOR, 70, "harp", "piano", (0, 5, 3, 4), (4, 7, 6, None, 2, 4, 7, 5)),
}

CAVE_MOTIFS = (
    (0, 2, 1, None, 4, 2, 0, -1), (2, 0, -2, 0, 1, None, 3, 2),
    (4, None, 3, 2, 1, 0, 2, None), (0, 4, 5, 4, 2, None, 1, 3),
    (2, 3, 2, 0, None, -3, -1, 0), (1, 4, None, 2, 0, 4, 2, 1),
    (0, None, 2, -1, -3, -1, 1, None), (4, 6, 5, None, 3, 2, 0, 4),
    (2, -1, None, 1, 5, 3, 1, 2), (1, 0, -2, 2, None, 4, 5, 3),
    (5, 3, None, 4, 2, 3, 0, None), (0, 1, -2, None, 3, 1, -1, 0),
    (4, None, 0, -1, 2, -2, 1, 3), (2, 4, 7, 5, None, 4, 1, 3),
    (0, 2, 4, None, 5, 7, 4, 2),
)
for floor, motif in enumerate(CAVE_MOTIFS, 1):
    section = min(2, (floor - 1) // 5)
    SCORES[f"mine_{floor}"] = (
        (57, 60, 55, 62, 59)[(floor - 1) % 5],
        (DORIAN, MINOR, MIXOLYDIAN)[section],
        (76, 73, 70, 79, 68)[(floor - 1) % 5] - section * 3,
        ("mallet", "piano", "harp")[section],
        ("pad", "harp", "pad")[section],
        ((0, 3, 0, 4), (0, 5, 6, 3), (0, 2, 5, 4), (0, 1, 3, 4), (0, 6, 3, 0))[(floor - 1) % 5],
        motif,
    )


def synth(name, pitch, duration):
    time = np.arange(round(duration * RATE)) / RATE
    phase = 2 * np.pi * 440 * 2 ** ((pitch - 69) / 12) * time
    if name == "pad":
        wave = np.sin(phase) + 0.26 * np.sin(phase * 1.006) + 0.12 * np.sin(phase * 2)
        attack, decay = 0.28, 0.48
    elif name == "reed":
        phase += 0.045 * np.sin(time * 31)
        wave = np.sin(phase) + 0.20 * np.sin(phase * 2) + 0.10 * np.sin(phase * 3)
        attack, decay = 0.09, 0.52
    elif name == "mallet":
        wave = np.sin(phase) + 0.22 * np.sin(phase * 3.98) * np.exp(-11 * time)
        attack, decay = 0.014, 3.8
    elif name == "guitar":
        wave = np.sin(phase) + 0.32 * np.sin(phase * 2) * np.exp(-2.6 * time) + 0.13 * np.sin(phase * 3)
        attack, decay = 0.016, 2.9
    elif name == "harp":
        wave = np.sin(phase) + 0.32 * np.sin(phase * 2) + 0.14 * np.sin(phase * 3) * np.exp(-6 * time)
        attack, decay = 0.02, 3.0
    else:
        wave = np.sin(phase) + 0.26 * np.sin(phase * 2.004) + 0.13 * np.sin(phase * 3.007) * np.exp(-4 * time)
        attack, decay = 0.019, 2.4
    release = min(duration * 0.46, 0.42)
    envelope = np.minimum(1, time / attack) * np.minimum(1, (duration - time) / release)
    return wave * envelope * np.exp(-decay * time)


def render(item):
    scene, (key, scale, tempo, lead, backing, progression, motif) = item
    beat = 60 / tempo
    short = scene.startswith("story_")
    bars = 4 if short else BARS
    song = np.zeros((round(bars * 4 * beat * RATE), 2), dtype=np.float32)

    def instrument(tick, degree, beats, gain, pan, voice, octave=0):
        pitch = key + scale[degree % 7] + 12 * (degree // 7 + octave)
        note = synth(voice, pitch, beats * beat) * gain
        start = round(tick * beat * RATE)
        stereo = np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
        signal = note[:, None] * stereo
        end = min(start + len(signal), len(song))
        song[start:end] += signal[: end - start]
        song[: len(signal) - (end - start)] += signal[end - start :]

    for bar in range(bars):
        tick = bar * 4
        root = progression[bar % 4]
        if bar >= 12:
            root = (progression[0], progression[1], progression[3], progression[0])[bar % 4]
        instrument(tick, root, 2.7, 0.15, -0.14, "pad", -2)
        instrument(tick + 2.6, root + 4, 1.38, 0.068, -0.18, "piano", -2)
        notes = (0, 4, 2, 6) if bar % 4 in (0, 3) else (2, 4, 7, 4)
        for step, degree in enumerate(notes):
            instrument(tick + (0.12, 0.90, 2.14, 3.08)[step], root + degree, 1.56, 0.073, 0.37 if step % 2 else -0.38, backing, -1)
        if bar in (7, 11):
            continue
        for index, offset in enumerate((0.10, 1.24, 2.15, 3.1)):
            degree = motif[(bar % 2) * 4 + index]
            if degree is None:
                continue
            if 4 <= bar < 8:
                degree += (0, 1, 0, -1)[index]
            elif 8 <= bar < 12:
                degree = 4 - degree + (bar % 2)
            elif bar == bars - 1 and index >= 1:
                degree = (2, 1, 0)[index - 1]
            instrument(tick + offset, degree, 1.24 if index < 3 else 1.38, 0.17 if index in (0, 2) else 0.125, 0.1, lead)
            if bar >= 8 and index == 2:
                instrument(tick + offset + 0.27, degree + 4, 0.92, 0.047, -0.43, backing)
    # Circular reflections keep release tails intact at the loop boundary.
    song += np.roll(song[:, ::-1], int(0.11 * RATE), axis=0) * 0.12
    song += np.roll(song, int(0.21 * RATE), axis=0) * 0.066
    if short:
        tail = RATE // 2
        song[-tail:] *= np.linspace(1.0, 0.0, tail)[:, None]
        song[:tail] *= np.linspace(0.0, 1.0, tail)[:, None]
    peak = np.max(np.abs(song))
    samples = (song * (0.50 / peak) * 32767).astype("<i2")
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "2",
         "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "3", str(MUSIC / f"{scene}.ogg")],
        input=samples.tobytes(), check=True,
    )
    return scene


if __name__ == "__main__":
    import sys

    scenes = sys.argv[1:] or SCORES
    with ThreadPoolExecutor(max_workers=4) as pool:
        for scene_id in pool.map(render, ((scene, SCORES[scene]) for scene in scenes)):
            print(scene_id, flush=True)
