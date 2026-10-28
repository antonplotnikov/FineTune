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
- **Binaural (HRTF)** — see below.
- **Crossfeed** — feeds a softened, slightly delayed copy of each side to the other ear, like speakers do.
  This reduces listening fatigue on headphones and makes hard-panned games sound more natural.
- **Room** — short early reflections for a sense of space.
- Presets: **Wide Stage**, **Headphone Crossfeed**, **Virtual Surround**, **Arena**, plus the binaural presets below.

Spatial processing works on stereo output. It is best on headphones; on speakers prefer Width only.

### Binaural (HRTF)

Binaural mode renders your stereo mix on **two virtual speakers** in front of you, using measured
head-related impulse responses. Each ear hears both speakers the way a real head would filter them
— with the right delay (about 0.27 ms between the ears at 30°), level difference and tonal shaping from
head and ear — so the sound appears to come from outside your head instead of from inside it.

- **Speakers** sets the angle of each virtual speaker (10°–110°; 30° is the classic stereo triangle,
  wider gives a bigger stage). The measurements are on a 5° grid.
- **Binaural** blends between the original (0%) and the full rendering (100%).
- It replaces **Crossfeed** while on. **Width** is applied first and **Room** after.
- Presets: **Binaural Studio (30°)**, **Binaural Wide (55°)**, **Binaural Game** (45° plus a little room).

Details and limits:

- **Headphones only.** On speakers it adds nothing but colouring.
- The data comes from a standard dummy head (MIT KEMAR), not your own ears, so the effect varies from
  person to person; front/back and height cues are the weakest part of any generic HRTF.
- It works on **stereo** audio. A 5.1/7.1 game mixed down by macOS is rendered from its stereo mixdown,
  not as separate surround speakers.
- The responses are resampled to your output device's sample rate automatically. Cost is small
  (a few percent of one CPU core).

Credit: HRTF measurements of a KEMAR dummy-head microphone by Bill Gardner and Keith Martin,
MIT Media Lab (1994), <https://sound.media.mit.edu/resources/KEMAR.html>. The data is provided free
with no restrictions on use, provided the authors are cited.

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
