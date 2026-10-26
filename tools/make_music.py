#!/usr/bin/env python3
"""和風の BGM とジングルを合成して assets/audio/ に WAV（ステレオ）で書き出す。外部素材なし。

2版目：「チープに聞こえる」を直すため、
  - ステレオで楽器ごとに左右に置き、ホールの残響（畳み込み）をかける
  - 三味線は撥(ばち)のアタックと胴の響き、琴は柔らかい爪の音、笛・尺八は息の音と音程のしゃくり
  - 笙(しょう)の和音と低音でハーモニーを厚くする
  - 少しだけ発音のタイミングと強さをばらつかせる（機械っぽさを消す）
  - 1曲16〜24小節で、Aメロ・Bメロの展開を持たせる
ループ再生するので、曲の終わりからはみ出した音と残響は頭に回り込ませる。

使い方: python3 tools/make_music.py → godot --headless --import
（効果音は tools/make_audio.py）
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name):
    n = NOTE[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        n += 1
        rest = rest[1:]
    elif rest[0] == "b":
        n -= 1
        rest = rest[1:]
    return 440.0 * 2 ** ((12 * (int(rest) + 1) + n - 69) / 12)


def tr(name, semis):
    """音名を半音ずらした周波数"""
    return freq(name) * 2 ** (semis / 12)


def env_adsr(n, a=0.005, d=0.1, s=0.7, r=0.05):
    t = np.arange(n) / SR
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((dur - t) / max(r, 1e-6), 0, 1)
    return e * rel


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR / 2 - 100)], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, fc, order=2):
    sos = signal.butter(order, min(fc, SR / 2 - 100), "lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc, "highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak(x, f0, q, gain):
    """f0 付近を持ち上げる（胴の響き）"""
    b, a = signal.iirpeak(f0, q, fs=SR)
    return x + gain * signal.lfilter(b, a, x)


# ───────── はじく弦（Karplus-Strong をフィルタで一気に計算） ─────────

def ks(f, dur, damp=0.996, bright=0.6, pick=0.2):
    n = int(dur * SR)
    D = max(2, int(SR / f - 0.5))
    exc = rng.uniform(-1, 1, D)
    # 明るさ：最初のノイズを丸める
    exc = signal.lfilter([1 - (1 - bright) * 0.9], [1, -(1 - bright) * 0.9], exc)
    # はじく位置：櫛形フィルタで倍音の抜けを作る
    k = max(1, int(D * pick))
    exc = exc - np.roll(exc, k)
    x = np.zeros(n)
    x[:min(D, n)] = exc[:min(D, n)]
    a = np.zeros(D + 2)
    a[0] = 1
    a[D] = -damp * 0.5
    a[D + 1] = -damp * 0.5
    y = signal.lfilter([1], a, x)
    return y / (np.max(np.abs(y)) + 1e-9)


def shamisen(f, dur, vel=1.0):
    """三味線：明るい弦＋さわり（ビリつき）＋撥の当たる音＋胴の響き"""
    n = int(dur * SR)
    y = ks(f, dur, 0.992, 0.95, 0.12)
    y2 = ks(f * 1.003, dur, 0.990, 0.9, 0.1) * 0.35  # さわりのうなり
    y = y + y2
    y = np.tanh(y * 1.8) / np.tanh(1.8)
    t = np.arange(n) / SR
    bachi = bandpass(rng.uniform(-1, 1, n), 1800, 5500) * np.exp(-t * 140) * 0.9
    thock = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 60) * 0.5
    y = y * np.exp(-t * 2.2) + bachi + thock
    y = peak(y, 520, 3, 0.6)
    y = peak(y, 1400, 4, 0.4)
    y *= env_adsr(n, 0.001, 9, 1, 0.03)
    return y * 0.5 * vel


def koto(f, dur, vel=1.0):
    """琴：柔らかい爪の音と長い余韻"""
    n = int(dur * SR)
    y = ks(f, dur, 0.9985, 0.55, 0.18)
    t = np.arange(n) / SR
    tsume = bandpass(rng.uniform(-1, 1, n), 2500, 7000) * np.exp(-t * 200) * 0.35
    y = lowpass(y, 5200) * np.exp(-t * 0.9) + tsume
    y = peak(y, 300, 2, 0.4)
    y *= env_adsr(n, 0.001, 9, 1, 0.08)
    return y * 0.45 * vel


def bass(f, dur, vel=1.0):
    """低音（太棹の三味線の低い弦のような丸い音）"""
    n = int(dur * SR)
    y = ks(f, dur, 0.996, 0.35, 0.3)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.5)
    y = lowpass(y * 0.7 + sub * 0.8, 900)
    y *= env_adsr(n, 0.002, 9, 1, 0.05)
    return y * 0.6 * vel


def wind(f, dur, vel=1.0, breath=0.12, vib=0.010, scoop=0.0, harm=(1, 0.3, 0.12, 0.05), chiff=0.4):
    """笛のなかま。scoop: 出だしの音程のしゃくり（半音の割合）"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib_e = np.clip((t - 0.25) * 2.5, 0, 1)
    bend = 1 - scoop * np.exp(-t * 14) * 0.06
    fr = f * bend * (1 + vib * np.sin(2 * np.pi * 5.3 * t + rng.uniform(0, 6)) * vib_e)
    ph = 2 * np.pi * np.cumsum(fr) / SR
    x = sum(a * np.sin((i + 1) * ph) for i, a in enumerate(harm))
    noise = rng.uniform(-1, 1, n)
    air = bandpass(noise, f * 0.8, f * 3.5) * breath * 3
    ch = bandpass(noise, f * 2, f * 6) * np.exp(-t * 40) * chiff
    a = min(0.06, dur * 0.3)
    e = env_adsr(n, a, 0.4, 0.85, min(0.12, dur * 0.3))
    # 長い音は少しふくらませる
    swell = 1 + 0.15 * np.sin(np.pi * np.clip(t / max(dur, 0.01), 0, 1))
    return (x + air + ch) * e * swell * 0.35 * vel


def fue(f, dur, vel=1.0):
    return wind(f, dur, vel, breath=0.10, vib=0.012, scoop=0.3, harm=(1, 0.35, 0.15, 0.06), chiff=0.5)


def shakuhachi(f, dur, vel=1.0):
    return wind(f, dur, vel, breath=0.32, vib=0.016, scoop=1.0, harm=(1, 0.2, 0.08), chiff=0.9)


def hichiriki(f, dur, vel=1.0):
    """篳篥：鼻にかかった太い音。音の頭で下からずり上がる（塩梅）"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    bend = 1 - 0.05 * np.exp(-t * 6)
    fr = f * bend * (1 + 0.006 * np.sin(2 * np.pi * 4.5 * t))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 14))
    y = bandpass(saw, 500, 3200) + 0.4 * lowpass(saw, 600)
    y = peak(y, 1100, 3, 0.8)
    y += bandpass(rng.uniform(-1, 1, n), f, f * 4) * 0.15
    y *= env_adsr(n, 0.05, 0.5, 0.9, 0.1)
    return y * 0.28 * vel


def sho(fs_list, dur, vel=1.0):
    """笙：いくつもの音を重ねたリードオルガンのような和音。ゆっくり立ち上がる"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f in fs_list:
        for det in (-0.6, 0.6):
            ph = 2 * np.pi * (f + det) * t + rng.uniform(0, 6)
            y += np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)
    y = lowpass(y, 3500)
    y *= env_adsr(n, min(0.5, dur * 0.3), 1, 1, min(0.6, dur * 0.3))
    return y * 0.05 * vel


# ───────── 打楽器 ─────────

def odaiko(vel=1.0):
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    f = 48 + 40 * np.exp(-t * 12)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.2)
    skin = lowpass(rng.uniform(-1, 1, n), 1200) * np.exp(-t * 35) * 0.6
    return np.tanh((body + skin) * 1.3) * vel


def nagado(vel=1.0):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    f = 95 + 70 * np.exp(-t * 25)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    skin = bandpass(rng.uniform(-1, 1, n), 200, 2500) * np.exp(-t * 50) * 0.5
    return (body + skin) * 0.8 * vel


def fuchi(vel=1.0):
    """太鼓のふち（カッ）"""
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    return bandpass(rng.uniform(-1, 1, n), 1500, 6000) * np.exp(-t * 90) * 0.6 * vel


def shime(vel=1.0):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (380 + 150 * np.exp(-t * 60)) * t) * np.exp(-t * 26)
    snap = bandpass(rng.uniform(-1, 1, n), 1500, 7000) * np.exp(-t * 70) * 0.6
    return (body + snap) * 0.5 * vel


def kane(vel=1.0, f=1800):
    """当たり鉦（チャンチキ）"""
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d)
            for r, a, d in [(1, 1, 9), (1.47, 0.6, 12), (2.09, 0.5, 15), (2.56, 0.35, 20)])
    x += bandpass(rng.uniform(-1, 1, n), 3000, 9000) * np.exp(-t * 80) * 0.5
    return x * 0.22 * vel


def bell(f=880, dur=2.5, vel=1.0):
    """お寺の鐘のような長い金属音"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d)
            for r, a, d in [(1, 1, 1.2), (2.0, 0.5, 2), (2.76, 0.45, 2.5), (5.4, 0.25, 4), (8.9, 0.12, 6)])
    return x * 0.18 * vel


def hyoshigi(vel=1.0):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 1850 * t) * 0.7 + np.sin(2 * np.pi * 2900 * t) * 0.3
    return x * np.exp(-t * 65) * 0.45 * vel


def suzu(vel=1.0):
    """神楽鈴：小さな鈴がシャラン"""
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for _ in range(9):
        f = rng.uniform(4200, 7800)
        d = int(rng.uniform(0, 0.06) * SR)
        x[d:] += np.sin(2 * np.pi * f * t[:n - d]) * np.exp(-t[:n - d] * rng.uniform(10, 18))
    return x * 0.06 * vel


# ───────── ミックス ─────────

class Song:
    def __init__(self, bpm, bars, beats_per_bar=4):
        self.beat = 60 / bpm
        self.n = int(bars * beats_per_bar * self.beat * SR)
        self.dry = np.zeros((2, self.n))
        self.send = np.zeros((2, self.n))

    def at(self, beats):
        return beats * self.beat

    def add(self, x, beats, pan=0.0, rev=0.25, vol=1.0, human=True):
        """x を beats 拍目に置く。pan: -1 左〜1 右、rev: 残響に送る量。はみ出しは頭に回り込む"""
        t = self.at(beats)
        if human:
            t += rng.normal(0, 0.006)
            vol *= rng.uniform(0.9, 1.05)
        i = int(t * SR) % self.n
        l = np.cos((pan + 1) * np.pi / 4) * vol
        r = np.sin((pan + 1) * np.pi / 4) * vol
        # 曲の長さを超える分は頭へ回す
        pos = 0
        while pos < len(x):
            j = (i + pos) % self.n
            m = min(len(x) - pos, self.n - j)
            seg = x[pos:pos + m]
            for ch, g in ((0, l), (1, r)):
                self.dry[ch, j:j + m] += seg * g
                self.send[ch, j:j + m] += seg * g * rev
            pos += m

    def line(self, inst, notes, start, pan=0.0, rev=0.3, vol=1.0, legato=1.05, semis=0):
        """notes: "D5:1 E5:.5 -:1 ..."（- は休み）"""
        b = start
        for tok in notes.split():
            nm, ln = tok.split(":")
            ln = float(ln)
            if nm != "-":
                self.add(inst(tr(nm, semis), ln * self.beat * legato + 0.05), b, pan, rev, vol)
            b += ln
        return b

    def drums(self, pattern, bars, start_bar=0, pan=0.0, rev=0.2, vol=1.0):
        """pattern: 1小節16文字。O 大太鼓 T 長胴 t 長胴(弱) f ふち s 締太鼓 k 鉦 h 拍子木 z 鈴"""
        for bar in range(start_bar, start_bar + bars):
            for i, ch in enumerate(pattern):
                b = bar * 4 + i / 4
                if ch == "O":
                    self.add(odaiko(), b, pan, rev * 1.3, vol)
                elif ch == "T":
                    self.add(nagado(), b, pan - 0.1, rev, vol)
                elif ch == "t":
                    self.add(nagado(0.5), b, pan - 0.1, rev, vol)
                elif ch == "f":
                    self.add(fuchi(), b, pan - 0.15, rev, vol)
                elif ch == "s":
                    self.add(shime(), b, pan + 0.3, rev, vol)
                elif ch == "S":
                    self.add(shime(1.4), b, pan + 0.3, rev, vol)
                elif ch == "k":
                    self.add(kane(), b, pan + 0.45, rev, vol)
                elif ch == "h":
                    self.add(hyoshigi(), b, pan - 0.4, rev, vol)
                elif ch == "z":
                    self.add(suzu(), b, pan + 0.5, rev * 1.5, vol)


def hall_ir(sec=2.2, rt60=1.8, bright=0.5):
    """ホールの残響の応答（左右で別のノイズ。高い音ほど早く消える）"""
    n = int(sec * SR)
    t = np.arange(n) / SR
    out = []
    for ch in range(2):
        lo = lowpass(rng.normal(0, 1, n), 1500) * np.exp(-6.9 * t / rt60)
        hi = highpass(rng.normal(0, 1, n), 1500) * np.exp(-6.9 * t / (rt60 * 0.45)) * bright
        ir = lo + hi
        ir[: int(0.012 * SR)] = 0  # 直接音のあとに少し間をあける
        # 初期反射
        for d, g in ((0.017, 0.5), (0.023, 0.35), (0.031, 0.3), (0.043, 0.22)):
            ir[int((d + ch * 0.003) * SR)] += g * 4
        out.append(ir / np.sqrt(np.sum(ir ** 2)))
    return out


def master(song, wet=0.35, rt60=1.8):
    n = song.n
    ir = hall_ir(min(rt60 + 0.6, n / SR - 0.1), rt60)
    mix = song.dry.copy()
    for ch in range(2):
        w = signal.fftconvolve(song.send[ch], ir[ch])
        # ループの頭に残響の尾を回り込ませる
        full = np.zeros(n)
        for k in range(0, len(w), n):
            seg = w[k:k + n]
            full[:len(seg)] += seg
        mix[ch] += full * wet * 1.3
    mix = np.array([highpass(m, 35) for m in mix])
    pk = np.max(np.abs(mix)) + 1e-9
    mix = mix / pk * 1.5
    mix = np.tanh(mix) / np.tanh(1.5)  # やわらかく頭を抑える
    return mix


def save(name, stereo, peak=0.9):
    x = stereo / (np.max(np.abs(stereo)) + 1e-9) * peak
    data = (x.T * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {x.shape[1] / SR:.1f}s")


def chords(song, inst_chords, start_bar, bars_each=1, pan=0.0, rev=0.5, vol=1.0):
    """笙の和音を1小節ずつ並べる。inst_chords: [[音名...], ...]"""
    for i, ch in enumerate(inst_chords):
        song.add(sho([freq(c) for c in ch], bars_each * 4 * song.beat + 0.3), (start_bar + i * bars_each) * 4,
                 pan, rev, vol, human=False)


def bassline(song, roots, start_bar, pattern=(0, 1.5, 2, 3), pan=0.0, vol=1.0, oct_jump=True):
    for i, r in enumerate(roots):
        for j, b in enumerate(pattern):
            nm = r
            if oct_jump and j == 2:
                nm = r[:-1] + str(int(r[-1]) + 1)
            song.add(bass(freq(nm), song.beat * 0.9), (start_bar + i) * 4 + b, pan, 0.1, vol)


# ───────── 曲 ─────────

def bgm_title():
    """タイトル：陽音階のお祭り（祭囃子）。124BPM・16小節（A8＋B8）"""
    s = Song(124, 16)
    a1 = "A5:1 B5:.5 A5:.5 G5:1 E5:1 D5:.5 E5:.5 G5:1 A5:2 B5:1 D6:.5 B5:.5 A5:1 G5:1 E5:.5 G5:.5 A5:.5 G5:.5 E5:2"
    a2 = "A5:1 B5:.5 A5:.5 G5:1 E5:1 D5:.5 E5:.5 G5:1 A5:1 B5:1 D6:1 B5:.5 A5:.5 G5:.5 A5:.5 B5:1 A5:1 G5:1 E5:.5 G5:.5 D5:1"
    b1 = "D6:1.5 E6:.5 D6:1 B5:1 A5:1.5 B5:.5 A5:1 G5:1 E5:.5 G5:.5 A5:1 B5:.5 A5:.5 G5:1 A5:4"
    b2 = "D6:1.5 E6:.5 D6:1 B5:1 A5:.5 B5:.5 D6:.5 E6:.5 D6:1 B5:1 A5:.5 G5:.5 E5:.5 G5:.5 A5:1 B5:1 D6:4"
    s.line(fue, a1 + " " + a2, 0, pan=0.15, rev=0.35, vol=1.0)
    s.line(fue, b1 + " " + b2, 32, pan=0.15, rev=0.35, vol=1.0)
    # B では三味線が同じ旋律を1オクターブ下で
    s.line(shamisen, b1 + " " + b2, 32, pan=-0.35, rev=0.2, vol=0.55, semis=-12, legato=0.7)
    roots = ["D3", "D3", "G2", "A2", "D3", "G2", "A2", "D3"] * 2
    bassline(s, roots, 0, vol=0.8)
    # 三味線の刻み（裏拍）
    for bar, r in enumerate(roots):
        for i in range(8):
            if i % 2 == 1:
                s.add(shamisen(tr(r, 12 + (7 if i % 4 == 3 else 0)), s.beat * 0.4), bar * 4 + i * 0.5, -0.4, 0.15, 0.5)
    s.drums("T..t..T.T.t.T...", 15)
    s.drums("T..t..T.T.t.TfTf", 1, 15)
    s.drums("s.ss.ss.s.ss.ss.", 16, vol=0.55)
    s.drums("k.kk.k.kk.kk.k.k", 16, vol=0.7)
    s.drums("O...............", 16, vol=0.8)
    save("bgm_title", master(s, 0.3, 1.6))


def bgm_den1():
    """一の宿 狸横丁：陽音階でのんびり。考えながら聞くので控えめ。100BPM・16小節"""
    s = Song(100, 16)
    roots = ["D3", "D3", "G2", "D3", "E3", "G2", "A2", "D3"] * 2
    bassline(s, roots, 0, pattern=(0, 1.5, 2.5), vol=0.7, oct_jump=False)
    # 三味線のゆるい刻み
    for bar, r in enumerate(roots):
        for b, d in ((1, 12), (2.5, 19), (3, 12)):
            s.add(shamisen(tr(r, d), s.beat * 0.5, 0.8), bar * 4 + b, -0.45, 0.2, 0.42)
    m1 = "A4:1.5 B4:.5 D5:1 B4:1 A4:1.5 G4:.5 E4:2 G4:1 A4:.5 B4:.5 A4:1 G4:1 E4:1 D4:.5 E4:.5 D4:2"
    m2 = "E5:1.5 D5:.5 B4:1 D5:1 E5:1 G5:1 E5:2 D5:1 B4:.5 A4:.5 B4:1 D5:1 A4:4"
    s.line(koto, m1 + " " + m2, 0, pan=0.3, rev=0.4, vol=0.9)
    # 後半は尺八が歌い、琴は合いの手
    s.line(shakuhachi, m1 + " " + m2, 32, pan=0.1, rev=0.45, vol=0.85)
    s.line(koto, "-:2 D6:.5 B5:.5 A5:.5 G5:.5 " * 8, 32, pan=0.5, rev=0.5, vol=0.35)
    chords(s, [["D4", "A4", "E5"], ["D4", "A4", "E5"], ["G3", "D4", "A4"], ["D4", "A4", "B4"],
               ["E4", "B4", "D5"], ["G3", "D4", "B4"], ["A3", "E4", "B4"], ["D4", "A4", "E5"]] * 2, 0, vol=0.6)
    s.drums("T.......t...f...", 16, vol=0.55)
    s.drums("............h...", 16, vol=0.6)
    save("bgm_den1", master(s, 0.35, 1.8))


def bgm_den2():
    """二の宿 猫又通り：都節音階で妖しく、しっとり。90BPM・16小節"""
    s = Song(90, 16)
    # 琴の分散和音（都節 D Eb G A Bb）
    arps = [["D4", "A4", "D5", "Eb5"], ["D4", "A4", "D5", "Eb5"], ["G3", "D4", "G4", "A4"], ["Bb3", "D4", "G4", "A4"],
            ["Eb4", "G4", "Bb4", "D5"], ["D4", "G4", "A4", "D5"], ["G3", "D4", "Eb4", "A4"], ["D4", "A4", "D5", "A4"]] * 2
    for bar, ar in enumerate(arps):
        for i in range(8):
            nm = ar[[0, 1, 2, 3, 2, 1, 2, 3][i]]
            s.add(koto(freq(nm), s.beat * 1.2, 0.7 if i else 0.9), bar * 4 + i * 0.5, -0.3 + 0.1 * (i % 3), 0.45, 0.55)
    m1 = "A4:2 Bb4:1 A4:1 G4:2 Eb4:1 D4:1 Eb4:1.5 G4:.5 A4:1 Bb4:1 A4:4"
    m2 = "D5:2 Eb5:1 D5:1 Bb4:2 A4:1 G4:1 A4:1 Bb4:.5 A4:.5 G4:1 Eb4:1 D4:4"
    s.line(shakuhachi, m1 + " " + m2 + " " + m1 + " " + m2, 0, pan=0.25, rev=0.55, vol=0.9)
    bassline(s, ["D2", "D2", "G2", "Bb2", "Eb2", "D2", "G2", "D2"] * 2, 0, pattern=(0, 2.5), vol=0.6, oct_jump=False)
    chords(s, [["D4", "A4", "Eb5"], ["G3", "D4", "A4"], ["Eb4", "Bb4", "D5"], ["D4", "G4", "A4"]] * 2, 0, 2, vol=0.5)
    s.drums("t...........f...", 16, vol=0.5)
    s.drums("........z.......", 16, vol=0.5)
    save("bgm_den2", master(s, 0.45, 2.2))


def bgm_den3():
    """三の宿 九尾御殿：雅楽ふうに荘厳。笙の和音・篳篥の旋律・大太鼓。80BPM・16小節"""
    s = Song(80, 16)
    ac = [["D4", "E4", "A4", "B4", "E5"], ["D4", "G4", "A4", "D5", "E5"], ["E4", "A4", "B4", "E5", "F#5"],
          ["D4", "E4", "A4", "B4", "E5"], ["G3", "D4", "E4", "A4", "D5"], ["A3", "E4", "B4", "E5"],
          ["D4", "E4", "A4", "B4", "E5"], ["D4", "A4", "D5", "E5"]] * 2
    chords(s, ac, 0, vol=1.0)
    m1 = "A4:2 B4:1 A4:1 E5:3 D5:1 B4:2 A4:1 B4:1 A4:4 D5:2 E5:1 D5:1 B4:2 A4:2 E4:1.5 G4:.5 A4:2 A4:4"
    m2 = "E5:2 F#5:1 E5:1 D5:2 B4:2 A4:1 B4:1 D5:2 E5:4 B4:2 A4:1 G4:1 E4:2 G4:2 A4:4 D4:4"
    s.line(hichiriki, m1 + " " + m2, 0, pan=-0.1, rev=0.5, vol=0.85)
    # 龍笛のかざり
    s.line(fue, "-:6 E6:.5 D6:.5 B5:1 -:8 " * 4, 0, pan=0.4, rev=0.6, vol=0.45)
    s.line(koto, "D4:1 A4:1 D5:1 E5:1 " * 16, 0, pan=0.35, rev=0.5, vol=0.4)
    bassline(s, ["D2", "D2", "E2", "D2", "G2", "A2", "D2", "D2"] * 2, 0, pattern=(0,), vol=0.6, oct_jump=False)
    s.drums("O.......s.s.ssss", 16, vol=0.7)
    s.drums("........T.......", 8, vol=0.5)
    for b in range(0, 16, 4):
        s.add(bell(freq("D5"), 3.0), b * 4, 0.3, 0.7, 0.6, human=False)
    save("bgm_den3", master(s, 0.5, 2.6))


def bgm_boss():
    """親分戦：速く熱い。津軽三味線ふうの刻みと太鼓の連打。140BPM・16小節"""
    s = Song(140, 16)
    riff = "D4:.5 D4:.5 Eb4:.5 D4:.5 A3:.5 D4:.5 Bb3:.5 A3:.5"
    for bar in range(16):
        semis = [0, 0, 5, 0, 0, 0, 7, 5][bar % 8]
        s.line(shamisen, riff, bar * 4, pan=-0.35, rev=0.15, vol=0.7, semis=semis, legato=0.8)
    m1 = "D5:.5 Eb5:.5 D5:1 A4:1 Bb4:1 A4:.5 G4:.5 Eb4:1 D4:2 G5:1 Eb5:.5 D5:.5 Bb4:1 A4:1 Bb4:.5 A4:.5 G4:.5 Eb4:.5 D4:2"
    m2 = "A5:1.5 Bb5:.5 A5:1 G5:1 Eb5:1 D5:1 Bb4:2 A4:.5 Bb4:.5 D5:.5 Eb5:.5 G5:1 Eb5:1 D5:4"
    s.line(fue, m1 + " " + m1, 0, pan=0.25, rev=0.3, vol=0.95)
    s.line(fue, m2 + " " + m2, 32, pan=0.25, rev=0.3, vol=0.95)
    s.line(shakuhachi, m2 + " " + m2, 32, pan=-0.05, rev=0.3, vol=0.5, semis=-12)
    bassline(s, ["D2", "D2", "G2", "D2", "D2", "D2", "A2", "G2"] * 2, 0, pattern=(0, 0.75, 1.5, 2, 2.75, 3.5), vol=0.7,
             oct_jump=False)
    s.drums("O..TO.T.O..TO.TT", 16, vol=0.85)
    s.drums("s.ssS.sss.ssS.sS", 16, vol=0.5)
    s.drums("k...k...k...k.k.", 16, 8, vol=0.6)
    save("bgm_boss", master(s, 0.25, 1.4))


def bgm_final():
    """最後の親分・玉藻：妖しく壮大。笙の和音の刻み、篳篥、太鼓の連打。148BPM・16小節"""
    s = Song(148, 16)
    stabs = [["D4", "Eb4", "A4", "D5"], ["D4", "G4", "A4", "Eb5"], ["Bb3", "Eb4", "G4", "D5"], ["A3", "D4", "Eb4", "A4"]]
    for bar in range(16):
        ch = stabs[(bar // 2) % 4]
        for b in (0, 1.5, 3):
            s.add(sho([freq(c) for c in ch], s.beat * 1.2), bar * 4 + b, 0.0, 0.4, 1.6, human=False)
    for bar in range(16):
        for i in range(16):
            nm = ["D4", "A4", "D5", "Eb5"][i % 4] if bar % 4 < 2 else ["G3", "D4", "G4", "A4"][i % 4]
            s.add(koto(freq(nm), s.beat * 0.4, 0.6), bar * 4 + i * 0.25, 0.45, 0.3, 0.35)
    m1 = "D5:2 Eb5:1 D5:1 A4:2 Bb4:1 A4:1 G4:1 A4:1 Bb4:1 D5:1 Eb5:4 G5:2 Eb5:1 D5:1 Bb4:2 A4:2 G4:1 Eb4:1 G4:1 A4:1 D4:4"
    s.line(hichiriki, m1 + " " + m1, 0, pan=-0.15, rev=0.4, vol=0.9)
    s.line(fue, "-:4 D6:.5 Eb6:.5 D6:1 A5:2 -:8 " * 4, 0, pan=0.35, rev=0.5, vol=0.5)
    bassline(s, ["D2", "D2", "Bb1", "A1"] * 4, 0, pattern=(0, 0.5, 1.5, 2, 3, 3.5), vol=0.8, oct_jump=False)
    s.drums("O.TTO.T.O.TTO.TT", 16, vol=0.9)
    s.drums("SsssSsssSsssSsss", 16, vol=0.35)
    s.drums("k.k.k.k.k.k.kkkk", 16, 12, vol=0.6)
    for b in range(0, 16, 8):
        s.add(bell(freq("D4"), 3.5), b * 4, 0.0, 0.8, 0.8, human=False)
    save("bgm_final", master(s, 0.3, 1.8))


def bgm_shop():
    """夜市：のんびり琴と笛、神楽鈴がシャラン。86BPM・16小節"""
    s = Song(86, 16)
    arp = ["D4", "A4", "D5", "E5", "D5", "A4", "G4", "A4"]
    for bar in range(16):
        shift = [0, 0, 5, 7, 0, 0, 5, 2][bar % 8]
        for i, nm in enumerate(arp):
            s.add(koto(tr(nm, shift), s.beat * 1.1, 0.7), bar * 4 + i * 0.5, -0.35, 0.45, 0.5)
    m = "A5:2 B5:1 A5:1 E5:3 -:1 D5:1 E5:1 G5:1 E5:1 D5:4 E5:2 G5:1 A5:1 B5:2 A5:2 G5:1 E5:1 D5:2 D5:4"
    s.line(fue, m + " " + m.replace("B5:2 A5:2", "D6:2 B5:2"), 0, pan=0.25, rev=0.5, vol=0.75)
    bassline(s, ["D2", "D2", "G2", "A2", "D2", "D2", "G2", "E2"] * 2, 0, pattern=(0, 2), vol=0.55, oct_jump=False)
    chords(s, [["D4", "A4", "E5"], ["D4", "A4", "E5"], ["G3", "D4", "A4"], ["A3", "E4", "B4"]] * 4, 0, vol=0.45)
    s.drums("h.......h...z...", 16, vol=0.6)
    save("bgm_shop", master(s, 0.45, 2.0))


# ───────── ジングル（ループしない） ─────────

def jingle(beats_len, bpm, build, wet=0.35, rt=1.8):
    s = Song(bpm, 1)
    s.n = int((beats_len * 60 / bpm + rt + 0.5) * SR)
    s.dry = np.zeros((2, s.n))
    s.send = np.zeros((2, s.n))
    build(s)
    out = master(s, wet, rt)
    # 頭に回り込んだ残響を消すため、末尾をフェードアウト
    fade = int(0.4 * SR)
    out[:, -fade:] *= np.linspace(1, 0, fade)
    return out


def jingle_win():
    def b(s):
        for i, nm in enumerate(["D5", "E5", "G5", "A5", "B5", "D6"]):
            s.add(shamisen(freq(nm), 0.5), i * 0.25, -0.2, 0.2, 0.8, human=False)
        s.add(nagado(), 1.5, 0, 0.3, 1, human=False)
        s.add(nagado(), 1.75, 0, 0.3, 1, human=False)
        s.add(odaiko(), 2, 0, 0.4, 1, human=False)
        s.add(kane(), 2, 0.4, 0.3, 1.2, human=False)
        s.add(fue(freq("D6"), 1.6), 2, 0.2, 0.4, 1, human=False)
        s.add(sho([freq(c) for c in ["D4", "A4", "E5"]], 2.0), 2, 0, 0.5, 1.5, human=False)
        s.add(suzu(), 2, 0.5, 0.5, 1.2, human=False)
    save("jingle_win", jingle(5, 150, b))


def jingle_lose():
    def b(s):
        for i, nm in enumerate(["A4", "G4", "Eb4", "D4"]):
            s.add(koto(freq(nm), 1.4), i * 0.5, -0.2, 0.5, 0.9, human=False)
        s.add(shakuhachi(freq("D4"), 2.0), 2, 0.2, 0.6, 0.9, human=False)
        s.add(odaiko(0.8), 2, 0, 0.5, 1, human=False)
        s.add(bell(freq("D4"), 2.5), 2, 0, 0.6, 0.7, human=False)
    save("jingle_lose", jingle(5, 80, b, 0.45, 2.2))


def jingle_clear():
    def b(s):
        mel = "D5:.5 E5:.5 G5:.5 A5:.5 B5:1 A5:.5 B5:.5 D6:3"
        s.line(fue, mel, 0, pan=0.2, rev=0.4, vol=1.0)
        s.line(shamisen, mel, 0, pan=-0.3, rev=0.25, vol=0.6, semis=-12, legato=0.7)
        for i in range(6):
            s.add(nagado(), i * 0.5, 0, 0.3, 0.9, human=False)
        s.add(odaiko(), 4, 0, 0.5, 1, human=False)
        s.add(bell(freq("D5"), 3.0), 4, 0.2, 0.6, 1, human=False)
        s.add(sho([freq(c) for c in ["D4", "E4", "A4", "B4", "E5"]], 3.0), 4, 0, 0.6, 1.4, human=False)
        s.add(suzu(), 4, 0.5, 0.6, 1.3, human=False)
        s.add(suzu(), 4.5, -0.5, 0.6, 1.0, human=False)
    save("jingle_clear", jingle(8, 132, b))


def main():
    bgm_title()
    bgm_den1()
    bgm_den2()
    bgm_den3()
    bgm_boss()
    bgm_final()
    bgm_shop()
    jingle_win()
    jingle_lose()
    jingle_clear()


if __name__ == "__main__":
    main()
