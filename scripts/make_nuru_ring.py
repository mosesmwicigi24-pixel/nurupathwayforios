#!/usr/bin/env python3
"""Synthesise the ring of a Live guest invite: nuru_ring.caf and nuru_ring_once.caf.

The owner asked for calls to "ring and vibrate" (2026-09-28); there is no
calling feature, so the Live guest invite rings.
  - nuru_ring.caf (26 s) is the APNs sound of a `live_guest_invite` push
    (aps.sound "nuru_ring.caf"). iOS caps a notification sound at 30 s and
    falls back to the default sound when the file is missing, so it ships in
    the app bundle and stays under that cap.
  - nuru_ring_once.caf (one 1.2 s ring) is what the app's own full-screen
    invite plays, every 4 s — the same cadence as the push's file. A system
    sound can't be reliably cut off mid-play, so the app rings in single
    rings it can simply stop scheduling when the member answers.

The ring: a soft trill that alternates 440 and 480 Hz for 1.2 s, then 2.8 s
of quiet, seven times — 26 s in all. Everything is synthesised here from
sines (no samples, no borrowed audio):
  - the pitch glides between the two tones (a flattened sine, 10 alternations
    a second) with the phase carried through, so it trills without clicking;
  - a quiet 2nd and 3rd harmonic give it enough body to carry on a phone
    speaker, which barely reproduces 440 Hz on its own;
  - each ring fades in over 60 ms and out over 180 ms — soft edges, no snap.

Writes 16-bit mono WAVs to a temporary folder, then IMA4 CAFs with macOS's
afconvert (IMA4 is one of the formats iOS plays as a notification sound).

    python3 scripts/make_nuru_ring.py
    # → NuruMember/Resources/Sounds/nuru_ring.caf, nuru_ring_once.caf

Kept out of the app bundle: only NuruMember/ is a synchronized group.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

SAMPLE_RATE = 22_050          # plenty for 440–1440 Hz, and a small file
RINGS = 7                     # rings at 0, 4, … 24 s
RING_ON = 1.2                 # seconds of trill per ring
CYCLE = 4.0                   # ring + quiet (1.2 + 2.8) — the app's NuruRing.ringEvery
LENGTH = 26.0                 # the last ring ends at 25.2 s; iOS's cap is 30 s
LOW_HZ, HIGH_HZ = 440.0, 480.0
TRILL_HZ = 5.0                # full low→high→low cycles a second (10 alternations)
TRILL_SHAPE = 3.0             # how square the glide is (tanh drive)
ATTACK, RELEASE = 0.060, 0.180
HARMONICS = ((1, 1.0), (2, 0.30), (3, 0.08))
PEAK = 0.70                   # −3 dBFS: clear, never clipped

SOUNDS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "..", "NuruMember", "Resources", "Sounds")


def ring_envelope(t):
    """0→1 over the attack, 1→0 over the release — raised-cosine edges."""
    if t < ATTACK:
        return 0.5 - 0.5 * math.cos(math.pi * t / ATTACK)
    if t > RING_ON - RELEASE:
        return 0.5 - 0.5 * math.cos(math.pi * (RING_ON - t) / RELEASE)
    return 1.0


def ring_samples():
    """One ring, as floats in [-1, 1] before the peak scaling."""
    centre, swing = (LOW_HZ + HIGH_HZ) / 2, (HIGH_HZ - LOW_HZ) / 2
    norm = math.tanh(TRILL_SHAPE)
    total = sum(a for _, a in HARMONICS)
    phase, out = 0.0, []
    for i in range(int(RING_ON * SAMPLE_RATE)):
        t = i / SAMPLE_RATE
        glide = math.tanh(TRILL_SHAPE * math.sin(2 * math.pi * TRILL_HZ * t)) / norm
        phase += 2 * math.pi * (centre + swing * glide) / SAMPLE_RATE
        tone = sum(a * math.sin(k * phase) for k, a in HARMONICS) / total
        out.append(tone * ring_envelope(t))
    return out


def write_caf(name, frames, tmp):
    wav_path = os.path.join(tmp, name + ".wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(struct.pack("<%dh" % len(frames), *frames))
    out = os.path.normpath(os.path.join(SOUNDS, name + ".caf"))
    subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav_path, out], check=True)
    print("wrote %s (%.2f s, %d bytes)" % (out, len(frames) / SAMPLE_RATE, os.path.getsize(out)))


def main():
    ring = ring_samples()
    scale = PEAK / max(abs(s) for s in ring)
    one = [int(round(s * scale * 32767)) for s in ring]

    whole = [0] * int(LENGTH * SAMPLE_RATE)
    for n in range(RINGS):
        start = int(n * CYCLE * SAMPLE_RATE)
        whole[start:start + len(one)] = one

    with tempfile.TemporaryDirectory() as tmp:
        write_caf("nuru_ring", whole, tmp)
        write_caf("nuru_ring_once", one, tmp)


if __name__ == "__main__":
    sys.exit(main())
