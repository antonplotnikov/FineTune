// FineTune Tab Audio — service worker.
// Keeps a WebSocket to the FineTune app, reports tabs, and drives per-tab audio graphs
// living in the offscreen document.

const DEFAULT_PORT = 48731;
const FLAT_EQ = new Array(10).fill(0);

/** @type {WebSocket | null} */
let socket = null;
let reconnectTimer = null;
/** tabId → {volume, muted, eq} last requested by FineTune */
const desired = new Map();
/** tabIds currently routed through the offscreen graph */
const captured = new Set();

function isDefault(s) {
  const flatBands = !s.bands || s.bands.every(
    (b) => !b.enabled || ((b.type === "peaking" || b.type === "lowshelf" || b.type === "highshelf") && Math.abs(b.gain) < 0.01));
  return s.volume >= 0.999 && !s.muted && Math.abs(s.preamp) < 0.01 && s.eq.every((g) => Math.abs(g) < 0.01) && flatBands;
}

async function getConfig() {
  const { token = "", port = DEFAULT_PORT } = await chrome.storage.local.get(["token", "port"]);
  return { token, port };
}

async function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) return;
  const { token, port } = await getConfig();
  if (!token) return scheduleReconnect();

  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  socket = ws;
  ws.onopen = () => {
    ws.send(JSON.stringify({ type: "hello", token }));
    reportTabs();
  };
  ws.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    if (msg.type === "set") applySettings(msg.tabId, msg);
  };
  ws.onclose = () => {
    if (socket === ws) socket = null;
    scheduleReconnect();
  };
  ws.onerror = () => ws.close();
}

function scheduleReconnect() {
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connect, 3000);
}

async function reportTabs() {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  const tabs = await chrome.tabs.query({});
  const payload = tabs
    .filter((t) => t.id !== undefined && t.url && /^https?:/.test(t.url))
    .map((t) => ({
      id: t.id,
      title: t.title || "",
      host: new URL(t.url).hostname,
      favIconUrl: t.favIconUrl || "",
      audible: Boolean(t.audible) || captured.has(t.id),
    }));
  socket.send(JSON.stringify({ type: "tabs", tabs: payload }));
}

// --- Audio graph control ---------------------------------------------------

async function ensureOffscreen() {
  if (await chrome.offscreen.hasDocument()) return;
  await chrome.offscreen.createDocument({
    url: "offscreen.html",
    reasons: ["USER_MEDIA"],
    justification: "Process tab audio with Web Audio for per-tab volume and EQ.",
  });
}

async function applySettings(tabId, msg) {
  const settings = {
    volume: Math.max(0, Math.min(1, Number(msg.volume))),
    muted: Boolean(msg.muted),
    eq: Array.isArray(msg.eq) && msg.eq.length === 10 ? msg.eq.map(Number) : FLAT_EQ,
    bands: Array.isArray(msg.bands) ? msg.bands : null,
    preamp: Number(msg.preamp) || 0,
  };
  desired.set(tabId, settings);

  if (isDefault(settings)) {
    await release(tabId);
    return;
  }
  if (!captured.has(tabId)) {
    const ok = await capture(tabId);
    if (!ok) return;
  }
  chrome.runtime.sendMessage({ target: "offscreen", type: "apply", tabId, ...settings });
}

async function capture(tabId) {
  try {
    await ensureOffscreen();
    // Requires the extension to have been invoked on this tab (activeTab) at least once.
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tabId });
    await chrome.runtime.sendMessage({ target: "offscreen", type: "start", tabId, streamId });
    captured.add(tabId);
    chrome.action.setBadgeText({ tabId, text: "" });
    return true;
  } catch (err) {
    // No capture permission yet: ask the user to click the toolbar icon on that tab.
    chrome.action.setBadgeText({ tabId, text: "!" }).catch(() => {});
    chrome.action.setBadgeBackgroundColor({ tabId, color: "#d93025" }).catch(() => {});
    return false;
  }
}

async function release(tabId) {
  if (!captured.delete(tabId)) return;
  chrome.runtime.sendMessage({ target: "offscreen", type: "stop", tabId });
}

// --- Events ----------------------------------------------------------------

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.audible !== undefined || change.title || change.url || change.status === "complete") {
    // A navigation tears down the capture stream; forget it so it is re-established lazily.
    if (change.url) captured.delete(tabId);
    reportTabs();
  }
});
chrome.tabs.onRemoved.addListener((tabId) => {
  captured.delete(tabId);
  desired.delete(tabId);
  chrome.runtime.sendMessage({ target: "offscreen", type: "stop", tabId }).catch(() => {});
  reportTabs();
});
chrome.tabs.onCreated.addListener(reportTabs);

chrome.storage.onChanged.addListener(() => {
  if (socket) socket.close();
  connect();
});

// Popup asks to (re)capture the active tab after the user clicked the toolbar icon.
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target === "background" && msg.type === "retry-capture") {
    const settings = desired.get(msg.tabId);
    if (settings) applySettings(msg.tabId, { ...settings }).then(() => sendResponse({ ok: captured.has(msg.tabId) }));
    else sendResponse({ ok: false });
    return true;
  }
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
// Service workers sleep; an alarm keeps the socket alive and retried.
chrome.alarms?.create?.("keepalive", { periodInMinutes: 0.5 });
connect();
setInterval(() => socket?.readyState === WebSocket.OPEN && reportTabs(), 20000);
