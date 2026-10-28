// Offscreen document: one Web Audio graph per captured tab.
//   MediaStreamSource → 10× peaking BiquadFilter → Gain → destination
// Frequencies and Q match FineTune's EQSettings.frequencies / BiquadMath.graphicEQQ.

const FREQUENCIES = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const Q = 1.4;
const RAMP_SECONDS = 0.03;

const ctx = new AudioContext();
/** @type {Map<number, {stream: MediaStream, source: MediaStreamAudioSourceNode, filters: BiquadFilterNode[], gain: GainNode}>} */
const graphs = new Map();

async function start(tabId, streamId) {
  stop(tabId);
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { mandatory: { chromeMediaSource: "tab", chromeMediaSourceId: streamId } },
    video: false,
  });
  const source = ctx.createMediaStreamSource(stream);
  const filters = FREQUENCIES.map((frequency) => {
    const f = ctx.createBiquadFilter();
    f.type = "peaking";
    f.frequency.value = frequency;
    f.Q.value = Q;
    f.gain.value = 0;
    return f;
  });
  const gain = ctx.createGain();
  let node = source;
  for (const f of filters) { node.connect(f); node = f; }
  node.connect(gain);
  gain.connect(ctx.destination);
  graphs.set(tabId, { stream, source, filters, gain });
  if (ctx.state === "suspended") await ctx.resume();
}

// Web Audio's Q on highpass/lowpass is in dB of resonance; FineTune's Q is the RBJ linear Q.
function qValue(type, q) {
  return type === "highpass" || type === "lowpass" ? 20 * Math.log10(Math.max(q, 0.01)) : q;
}

function apply(tabId, { volume, muted, eq, bands, preamp = 0 }) {
  const g = graphs.get(tabId);
  if (!g) return;
  const now = ctx.currentTime;
  g.gain.gain.setTargetAtTime(muted ? 0 : volume * Math.pow(10, preamp / 20), now, RAMP_SECONDS);
  g.filters.forEach((f, i) => {
    const band = bands?.[i];
    if (!band) {
      f.gain.setTargetAtTime(eq[i] ?? 0, now, RAMP_SECONDS);
      return;
    }
    // Disabled bands become a flat peaking filter (0 dB = passthrough).
    const type = band.enabled ? band.type : "peaking";
    if (f.type !== type) f.type = type;
    f.frequency.setTargetAtTime(band.frequency, now, RAMP_SECONDS);
    f.Q.setTargetAtTime(qValue(type, band.q), now, RAMP_SECONDS);
    f.gain.setTargetAtTime(band.enabled ? band.gain : 0, now, RAMP_SECONDS);
  });
}

function stop(tabId) {
  const g = graphs.get(tabId);
  if (!g) return;
  g.source.disconnect();
  g.gain.disconnect();
  g.stream.getTracks().forEach((t) => t.stop());
  graphs.delete(tabId);
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== "offscreen") return;
  if (msg.type === "start") start(msg.tabId, msg.streamId).then(() => sendResponse({ ok: true }), (e) => sendResponse({ ok: false, error: String(e) }));
  else if (msg.type === "apply") apply(msg.tabId, msg);
  else if (msg.type === "stop") stop(msg.tabId);
  return msg.type === "start";
});
