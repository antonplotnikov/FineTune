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

## Game profiles

Open **Settings → Games**. A profile bundles an EQ curve with dynamics and spatial settings and applies
them automatically when a game starts producing audio.

1. Choose **New Profile** and pick a template (Competitive FPS, Cinematic, Voice Chat, Night Mode or Blank).
2. Under **Apps**, add your game (launch it first so it appears in the list).
3. Adjust the **Sound** section, or use **Capture from a running app** to copy the exact settings
   you tuned in the menu bar.

Options:

- **Apply automatically** — re-applies on every launch. Switch it off to apply only with **Apply now**.
  A profile is applied once per launch, so tweaks you make while playing are kept until the next launch.
- **Use for detected games** — also covers any app whose bundle declares the App Store category *Games*,
  unless that app has a profile of its own.
- **Don't change** leaves that part of the app's own settings alone.

Profiles overwrite the app's saved EQ and dynamics/spatial settings when they apply.
