#!/usr/bin/env python3
"""和風の BGM と効果音をプログラムで合成して assets/audio/ に WAV で書き出す。

三味線・琴（はじく弦は Karplus-Strong 法）、笛、太鼓、鐘、拍子木を作り、
陽音階（明るい）と都節音階（妖しい）で曲を組む。外部素材を使わないのでライセンスの心配がない。
使い方: python3 tools/make_audio.py  → そのあと godot --headless --import
BGM はループ再生するので、曲の終わりからはみ出した音は頭に回り込ませてつなぎ目を消している。
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(11)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name):
    """'A4' 'C#5' 'Bb3' → Hz"""
    n = NOTE[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        n += 1
        rest = rest[1:]
    elif rest[0] == "b":
        n -= 1
        rest = rest[1:]
    return 440.0 * 2 ** ((12 * (int(rest) + 1) + n - 69) / 12)


# ───────── 音色 ─────────

def pluck(f, dur, bright=0.5, decay=0.996, buzz=0.0):
    """Karplus-Strong のはじく弦。bright: 最初の明るさ、decay: 余韻、buzz: 三味線のさわり（ビリつき）"""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    # 最初のノイズを少しなめらかにすると柔らかい音になる
    for _ in range(int((1 - bright) * 4)):
        buf = (buf + np.roll(buf, 1)) / 2
    out = np.zeros(n)
    prev = 0.0
    for i in range(n):
        v = buf[i % p]
        out[i] = v
        nv = decay * 0.5 * (v + prev)
        prev = v
        buf[i % p] = nv
    if buzz:
        out = np.tanh(out * (1 + buzz * 3)) / np.tanh(1 + buzz * 3)
        out += rng.uniform(-1, 1, n) * buzz * 0.08 * np.exp(-np.arange(n) / SR * 25)
    fade = min(n, int(0.01 * SR))
    out[-fade:] *= np.linspace(1, 0, fade)
    return out


def shamisen(note, dur, vol=0.35):
    return pluck(freq(note), dur, bright=0.9, decay=0.993, buzz=0.35) * vol


def koto(note, dur, vol=0.3):
    return pluck(freq(note), dur, bright=0.6, decay=0.9975) * vol


def fue(note, dur, vol=0.2, vib=0.012):
    """篠笛：サイン波＋弱い倍音＋息の音、ゆっくり立ち上がってビブラート"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq(note) * (1 + vib * np.sin(2 * np.pi * 5.2 * t) * np.clip(t * 3 - 0.3, 0, 1))
    ph = np.cumsum(f) / SR
    x = np.sin(2 * np.pi * ph) + 0.25 * np.sin(4 * np.pi * ph) + 0.08 * np.sin(6 * np.pi * ph)
    breath = rng.uniform(-1, 1, n)
    breath = np.convolve(breath, np.ones(6) / 6, mode="same") * 0.18
    e = np.minimum(1, t / 0.06) * np.minimum(1, (dur - t) / 0.08)
    return (x + breath) * np.clip(e, 0, 1) * vol


def taiko(dur=0.6, vol=0.9, pitch=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = (55 + 90 * np.exp(-t * 18)) * pitch
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    hit = rng.uniform(-1, 1, n) * np.exp(-t * 60) * 0.35
    return (body + hit) * vol


def shime(vol=0.5):
    """締太鼓：高く短い"""
    n = int(0.15 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (330 + 120 * np.exp(-t * 50)) * t) * np.exp(-t * 30)
    return (body + rng.uniform(-1, 1, n) * np.exp(-t * 80) * 0.5) * vol


def kane(note="A5", dur=1.2, vol=0.35):
    """鐘（チャンチキ）：倍音がずれた金属音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq(note)
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d)
            for r, a, d in [(1, 1, 4), (2.76, 0.6, 6), (5.4, 0.4, 9), (8.9, 0.25, 14)])
    return x * vol * 0.5


def hyoshigi(vol=0.5):
    """拍子木：カン！"""
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 1850 * t) * 0.7 + np.sin(2 * np.pi * 2900 * t) * 0.3
    return x * np.exp(-t * 70) * vol


def paper(dur=0.12, vol=0.4, hp=True):
    """札をめくる・すべらせる音（ノイズ）"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = rng.uniform(-1, 1, n)
    if hp:
        x = x - np.convolve(x, np.ones(4) / 4, mode="same")
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return x * e * vol


# ───────── 組み立て ─────────

def add(buf, x, at, wrap=False):
    i = int(at * SR)
    n = len(x)
    if wrap:
        idx = (np.arange(n) + i) % len(buf)
        np.add.at(buf, idx, x)
    else:
        end = min(len(buf), i + n)
        if end > i:
            buf[i:end] += x[:end - i]


def save(name, x, peak=0.85):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    data = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {len(x) / SR:.1f}s")


def melody(buf, notes, beat, inst, start=0.0, wrap=True, **kw):
    """notes: [(音名 or None, 拍数), ...]"""
    t = start
    for nm, beats in notes:
        if nm:
            add(buf, inst(nm, beats * beat * 1.05, **kw), t, wrap)
        t += beats * beat
    return t


def drums(buf, pattern, beat, bars, wrap=True):
    """pattern: 1小節を16分割した文字列。D=太鼓 d=小さい太鼓 s=締太鼓 k=拍子木 b=鐘"""
    step = beat / 4
    for bar in range(bars):
        for i, ch in enumerate(pattern):
            at = (bar * 16 + i) * step
            if ch == "D":
                add(buf, taiko(0.7, 0.9), at, wrap)
            elif ch == "d":
                add(buf, taiko(0.4, 0.5, 1.3), at, wrap)
            elif ch == "s":
                add(buf, shime(0.45), at, wrap)
            elif ch == "k":
                add(buf, hyoshigi(0.35), at, wrap)
            elif ch == "b":
                add(buf, kane("E6", 0.4, 0.18), at, wrap)


# ───────── BGM ─────────

def bgm_title():
    """タイトル：陽音階のお祭り。118BPM・8小節"""
    bpm, bars = 118, 8
    beat = 60 / bpm
    buf = np.zeros(int(bars * 4 * beat * SR))
    # 陽音階 D E G A B
    mel = [("A4", 1), ("B4", 0.5), ("A4", 0.5), ("G4", 1), ("E4", 1),
           ("D4", 0.5), ("E4", 0.5), ("G4", 1), ("A4", 2),
           ("B4", 1), ("D5", 0.5), ("B4", 0.5), ("A4", 1), ("G4", 1),
           ("E4", 0.5), ("G4", 0.5), ("A4", 0.5), ("G4", 0.5), ("E4", 2),
           ("A4", 1), ("B4", 0.5), ("A4", 0.5), ("G4", 1), ("E4", 1),
           ("D4", 0.5), ("E4", 0.5), ("G4", 1), ("A4", 1), ("B4", 1),
           ("D5", 1), ("B4", 0.5), ("A4", 0.5), ("G4", 0.5), ("A4", 0.5), ("B4", 1),
           ("A4", 1), ("G4", 1), ("E4", 0.5), ("G4", 0.5), ("D4", 1)]
    melody(buf, mel, beat, fue, vol=0.22)
    # 三味線の伴奏（裏拍でチャカチャカ）
    roots = ["D3", "D3", "G3", "A3", "D3", "G3", "A3", "D3"]
    for b, r in enumerate(roots):
        for i in range(8):
            nm = r if i % 2 == 0 else ("A3" if r != "A3" else "E4")
            add(buf, shamisen(nm, beat * 0.5, 0.22 if i % 2 else 0.3), (b * 4 + i * 0.5) * beat, True)
    drums(buf, "D...k.d.D.d.k.s.", beat, bars)
    for b in range(bars):
        add(buf, kane("E6", 0.5, 0.12), (b * 4 + 1) * beat, True)
        add(buf, kane("E6", 0.5, 0.12), (b * 4 + 3) * beat, True)
    save("bgm_title", buf)


def bgm_den():
    """賭場（勝負中）：都節音階で妖しく、でも軽快。104BPM・16小節。考えながら聞くので控えめに"""
    bpm, bars = 104, 16
    beat = 60 / bpm
    buf = np.zeros(int(bars * 4 * beat * SR))
    # 都節 D Eb G A Bb
    ost = ["D3", "A3", "D4", "A3", "Eb4", "D4", "A3", "G3"]
    for b in range(bars):
        root_shift = ["D3", "D3", "G3", "D3"][b % 4]
        for i, nm in enumerate(ost):
            if root_shift == "G3" and nm in ("D3", "D4"):
                nm = "G3" if nm == "D3" else "G4"
            add(buf, shamisen(nm, beat * 0.5, 0.2), (b * 4 + i * 0.5) * beat, True)
    phrase_a = [("D5", 1.5), ("Eb5", 0.5), ("D5", 1), ("A4", 1), ("Bb4", 1.5), ("A4", 0.5), ("G4", 2),
                ("A4", 1), ("Bb4", 1), ("D5", 1), ("Eb5", 1), ("D5", 4)]
    phrase_b = [("G5", 1.5), ("Eb5", 0.5), ("D5", 1), ("Bb4", 1), ("A4", 1.5), ("G4", 0.5), ("A4", 2),
                ("Bb4", 1), ("A4", 0.5), ("G4", 0.5), ("Eb4", 1), ("D4", 1), ("D4", 4)]
    # 前半は琴、後半は笛が歌う
    melody(buf, phrase_a + phrase_b, beat, koto, start=0, vol=0.3)
    melody(buf, phrase_a + phrase_b, beat, fue, start=8 * 4 * beat, vol=0.16)
    melody(buf, [(None, 2), ("D6", 0.5), ("A5", 0.5), ("Eb5", 0.5), ("D5", 0.5)] * 4, beat, koto, start=4 * 4 * beat, vol=0.14)
    drums(buf, "D.......d...s.k.", beat, bars)
    save("bgm_den", buf)


def bgm_boss():
    """親分戦：速く激しい太鼓。138BPM・8小節"""
    bpm, bars = 138, 8
    beat = 60 / bpm
    buf = np.zeros(int(bars * 4 * beat * SR))
    riff = ["D3", "D3", "Eb3", "D3", "A2", "D3", "Bb2", "A2"]
    for b in range(bars):
        up = 5 if b % 4 == 2 else 0
        for i, nm in enumerate(riff):
            f = freq(nm) * 2 ** (up / 12)
            add(buf, pluck(f, beat * 0.5, 0.95, 0.99, 0.5) * 0.3, (b * 4 + i * 0.5) * beat, True)
    mel = [("D5", 0.5), ("Eb5", 0.5), ("D5", 1), ("A4", 1), ("Bb4", 1),
           ("A4", 0.5), ("G4", 0.5), ("Eb4", 1), ("D4", 2),
           ("G5", 1), ("Eb5", 0.5), ("D5", 0.5), ("Bb4", 1), ("A4", 1),
           ("Bb4", 0.5), ("A4", 0.5), ("G4", 0.5), ("Eb4", 0.5), ("D4", 2)]
    melody(buf, mel + mel, beat, fue, vol=0.2, vib=0.02)
    drums(buf, "D.dDs.D.D.dDs.ss", beat, bars)
    for b in range(0, bars, 2):
        add(buf, kane("D6", 1.0, 0.18), b * 4 * beat, True)
    save("bgm_boss", buf)


def bgm_shop():
    """夜市：のんびり琴と笛。84BPM・8小節"""
    bpm, bars = 84, 8
    beat = 60 / bpm
    buf = np.zeros(int(bars * 4 * beat * SR))
    arp = ["D4", "A4", "D5", "E5", "D5", "A4", "G4", "A4"]
    for b in range(bars):
        shift = [0, 0, 5, 7][b % 4]
        for i, nm in enumerate(arp):
            f = freq(nm) * 2 ** (shift / 12)
            add(buf, pluck(f, beat, 0.6, 0.9975) * 0.2, (b * 4 + i * 0.5) * beat, True)
    mel = [("A5", 2), ("B5", 1), ("A5", 1), ("E5", 3), (None, 1), ("D5", 1), ("E5", 1), ("G5", 1), ("E5", 1), ("D5", 4),
           ("E5", 2), ("G5", 1), ("A5", 1), ("B5", 2), ("A5", 2), ("G5", 1), ("E5", 1), ("D5", 2), ("D5", 4)]
    melody(buf, mel, beat, fue, vol=0.14)
    drums(buf, "k.......k...b...", beat, bars)
    save("bgm_shop", buf)


# ───────── ジングル ─────────

def jingle_win():
    beat = 60 / 150
    buf = np.zeros(int(3.0 * SR))
    for i, nm in enumerate(["D4", "E4", "G4", "A4", "B4", "D5"]):
        add(buf, shamisen(nm, 0.4, 0.3), i * beat * 0.25)
    add(buf, taiko(0.8, 0.9), 6 * beat * 0.25)
    add(buf, taiko(0.8, 0.9), 7 * beat * 0.25)
    add(buf, kane("D6", 1.5, 0.3), 8 * beat * 0.25)
    add(buf, fue("D5", 1.2, 0.2), 8 * beat * 0.25)
    add(buf, koto("A5", 1.5, 0.2), 8 * beat * 0.25)
    save("jingle_win", buf)


def jingle_lose():
    beat = 60 / 80
    buf = np.zeros(int(3.6 * SR))
    for i, nm in enumerate(["A4", "G4", "Eb4", "D4"]):
        add(buf, koto(nm, 1.2, 0.3), i * beat * 0.5)
    add(buf, fue("D4", 1.6, 0.18, 0.03), 4 * beat * 0.5)
    add(buf, taiko(1.2, 0.7, 0.8), 4 * beat * 0.5)
    save("jingle_lose", buf)


def jingle_clear():
    beat = 60 / 132
    buf = np.zeros(int(6.0 * SR))
    mel = [("D5", 0.5), ("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("B5", 1), ("A5", 0.5), ("B5", 0.5), ("D6", 3)]
    melody(buf, mel, beat, fue, wrap=False, vol=0.22)
    t = 0.0
    for nm, b in mel:
        add(buf, shamisen(nm.replace("6", "5").replace("5", "4"), 0.5, 0.25), t)
        t += b * beat
    for i in range(6):
        add(buf, taiko(0.6, 0.8), i * beat * 0.5)
    add(buf, kane("D6", 2.0, 0.3), 4 * beat)
    add(buf, kane("A5", 2.0, 0.2), 4.5 * beat)
    save("jingle_clear", buf)


# ───────── 効果音 ─────────

def main():
    bgm_title()
    bgm_den()
    bgm_boss()
    bgm_shop()
    jingle_win()
    jingle_lose()
    jingle_clear()
    save("sfx_select", koto("A5", 0.25, 0.4) + np.pad(paper(0.05, 0.2), (0, int(0.2 * SR))), 0.6)
    save("sfx_card", paper(0.1, 0.5), 0.5)
    save("sfx_discard", paper(0.22, 0.6, False), 0.5)
    shuffle = np.zeros(int(0.6 * SR))
    for i in range(8):
        add(shuffle, paper(0.06, 0.4), i * 0.06)
    save("sfx_shuffle", shuffle, 0.5)
    play = np.zeros(int(0.4 * SR))
    add(play, paper(0.18, 0.6, False), 0)
    add(play, hyoshigi(0.6), 0.16)
    save("sfx_play", play, 0.7)
    save("sfx_chip", koto("E5", 0.3, 0.5), 0.6)
    save("sfx_mult", shime(0.8), 0.7)
    xm = np.zeros(int(0.9 * SR))
    add(xm, taiko(0.6, 0.9, 1.2), 0)
    add(xm, kane("E6", 0.8, 0.4), 0.02)
    save("sfx_xmult", xm, 0.8)
    yk = np.zeros(int(1.4 * SR))
    for i, nm in enumerate(["D5", "E5", "G5", "A5", "B5", "D6"]):
        add(yk, shamisen(nm, 0.3, 0.3), i * 0.04)
    add(yk, kane("D6", 1.2, 0.4), 0.25)
    save("sfx_yaku", yk, 0.8)
    tot = np.zeros(int(1.2 * SR))
    add(tot, taiko(1.0, 1.0, 0.9), 0)
    add(tot, taiko(1.0, 0.8, 1.1), 0.12)
    save("sfx_total", tot, 0.85)
    coin = np.zeros(int(0.5 * SR))
    add(coin, kane("B6", 0.4, 0.4), 0)
    add(coin, kane("E7", 0.3, 0.3), 0.06)
    save("sfx_coin", coin, 0.55)
    buy = np.zeros(int(0.9 * SR))
    add(buy, kane("A5", 0.8, 0.35), 0)
    add(buy, kane("D6", 0.8, 0.35), 0.1)
    save("sfx_buy", buy, 0.6)
    save("sfx_click", hyoshigi(0.6), 0.5)
    boss = np.zeros(int(2.0 * SR))
    for i in range(8):
        add(boss, taiko(0.5, 0.4 + i * 0.07, 0.9), i * 0.09)
    add(boss, taiko(1.2, 1.0, 0.7), 0.8)
    add(boss, kane("D5", 1.2, 0.3), 0.8)
    save("sfx_boss", boss, 0.85)


if __name__ == "__main__":
    main()
