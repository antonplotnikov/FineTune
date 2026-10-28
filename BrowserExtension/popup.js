const $ = (id) => document.getElementById(id);

chrome.storage.local.get(["token", "port"]).then(({ token = "", port = 48731 }) => {
  $("token").value = token;
  $("port").value = port;
});

$("save").addEventListener("click", async () => {
  await chrome.storage.local.set({ token: $("token").value.trim(), port: Number($("port").value) || 48731 });
  $("status").textContent = "Saved. Connecting…";
});

// Opening this popup counts as an activeTab invocation for the current tab,
// which is what tabCapture requires.
async function grant() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const res = await chrome.runtime.sendMessage({ target: "background", type: "retry-capture", tabId: tab.id });
  $("status").textContent = res?.ok
    ? "Tab is now controlled by FineTune."
    : res?.noSettings
      ? "Change this tab's volume or EQ in FineTune first, then reopen this popup."
      : `Capture failed: ${res?.error || "unknown error"}`;
}
$("grant").addEventListener("click", grant);
// Opening the popup already grants activeTab, so capture right away instead of waiting for a second click.
grant();
