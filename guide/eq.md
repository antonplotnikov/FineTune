# Equalizer

Every app has its own EQ. Open it from the app row's EQ button.

## Graphic and Parametric

- **Graphic** — ten fixed bands (31 Hz – 16 kHz), ±18 dB in 0.1 dB steps. Double-click a slider to reset it. A response graph above the sliders shows the resulting curve.
- **Parametric** — up to ten bands with free frequency (20 Hz – 20 kHz), gain (±18 dB), Q (0.1 – 20) and filter type: Peak, Low Shelf, High Shelf, High Pass, Low Pass, Notch.

Switching to Parametric for the first time carries your graphic curve over.

### Editing the graph

| Action | Result |
| --- | --- |
| Drag a node | Change frequency and gain |
| Shift + drag | Gain only |
| Option + drag | Frequency only |
| Scroll over the graph | Q of the selected band |
| Double-click empty space | Add a band there |
| Right-click a node | Filter type, enable/disable, reset gain, delete |

Frequency, gain and Q can also be typed exactly under the graph.

## Preamp

The preamp lowers (or raises) the level of the whole curve. **Auto** sets it to cancel the curve's loudest boost, so boosted curves don't clip. A "May clip" warning appears when headroom is short.

## Analyzer

The **Analyzer** button draws a live spectrum of the app's output behind the curve (what you actually hear, after EQ). It only runs while the EQ panel is open.

## Presets

- Built-in presets are grouped by category. **Games** includes graphic presets (FPS Footsteps, Competitive, Immersive, MOBA / RPG, Voice Chat) and parametric ones (Footsteps Pro, Competitive Pro, Cinematic Pro, Voice Chat Pro, Gunfire Tamer) that ship with a matching preamp.
- Press **+** next to the preset picker to save your own curve (graphic or parametric).

## Editing tools

- **Undo / Redo** — step through your edits; a continuous slider drag counts as one step.
- **A/B** — keep the current curve as A and edit B, then flip between them to compare by ear.
- **Copy / Paste** — copy a curve and paste it onto another app (or a browser tab).

## Browser tabs

With the Chromium extension installed (see the Browser tab in Settings), each tab can have its own volume, mute and EQ, including parametric curves and preamp. The analyzer is not available for tabs.
