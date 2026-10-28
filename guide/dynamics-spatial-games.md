# Dynamics, Spatial Audio and Game Profiles

Open an app's EQ panel and use the **EQ / Dynamics / Spatial** tabs. Everything here is per app and
applies after the EQ.

## Dynamics (compressor + limiter)

- **Compressor** — Threshold, Ratio, Attack, Release, Knee and Makeup gain. It is stereo-linked, so the
  image doesn't shift when a loud sound hits one side. The **GR** meter shows how much it is reducing
  the level right now.
- **Limiter** — a look-ahead limiter with a Ceiling and Release. It sees peaks about 0.7 ms before they
  reach the output, so the ceiling holds even for sudden explosions. It adds that small delay only while enabled.
- Presets: **Gentle Leveler**, **Game Night** (quiet footsteps stay audible, loud explosions get squashed),
  **Voice Leveler**, **Limiter Only**, **Hard Limit**.

FineTune's existing soft limiter stays in place as the last safety stage.

## Spatial

- **Width** — 0% is mono, 100% is unchanged, 200% is twice as wide.
- **Crossfeed** — feeds a softened, slightly delayed copy of each side to the other ear, like speakers do.
  This reduces listening fatigue on headphones and makes hard-panned games sound more natural.
- **Room** — short early reflections for a sense of space.
- Presets: **Wide Stage**, **Headphone Crossfeed**, **Virtual Surround**, **Arena**.

Spatial processing works on stereo output. It is best on headphones; on speakers prefer Width only.
