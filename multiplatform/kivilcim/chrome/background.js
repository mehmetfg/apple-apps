// Kıvılcım · Dikkat — service worker: right-click menu, quick-save shortcut, the link to the Mac helper, the badge.
const HOST = "com.fatihgocgun.kivilcim";

function newId() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}-chrome-` +
    Math.random().toString(16).slice(2, 6);
}

function localIso(d = new Date()) {
  const off = -d.getTimezoneOffset();
  const p = (n) => String(Math.floor(Math.abs(n))).padStart(2, "0");
  return new Date(d.getTime() + off * 60000).toISOString().slice(0, 19) + (off >= 0 ? "+" : "-") + p(off / 60) + ":" + p(off % 60);
}

function send(msg) {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendNativeMessage(HOST, msg, (r) => {
        if (chrome.runtime.lastError) resolve({ ok: false, hata: chrome.runtime.lastError.message });
        else resolve(r || { ok: false, hata: "boş cevap" });
      });
    } catch (e) { resolve({ ok: false, hata: String(e) }); }
  });
}

async function capture(tabId) {
  try {
    const [r] = await chrome.scripting.executeScript({ target: { tabId }, files: ["capture.js"] });
    return r && r.result ? r.result : null;
  } catch (e) { return null; }   // chrome:// pages, the Web Store, PDFs in the viewer
}

async function save(isaret, ses) {
  const r = await send({ eylem: "kaydet", isaret, ses });
  if (r.ok) {
    flash("✓", "#2e9d5b");
    refreshBadge();
  } else {
    flash("!", "#c0392b");
    chrome.notifications.create({ type: "basic", iconUrl: "ikon128.png", title: "Kıvılcım kaydedemedi",
      message: (r.hata || "") + "\nYardımcı kurulu mu? chrome/host/kur.sh" });
  }
  return r;
}

function flash(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  setTimeout(refreshBadge, 2500);
}

async function refreshBadge() {
  const r = await send({ eylem: "durum" });
  const n = r.ok ? (r.simdi || []).length : 0;
  chrome.action.setBadgeBackgroundColor({ color: "#e8833a" });
  chrome.action.setBadgeText({ text: n ? String(n) : "" });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "sayfa", title: "Kıvılcım'a işaretle", contexts: ["page", "frame"] });
    chrome.contextMenus.create({ id: "secim", title: "Seçimi Kıvılcım'a işaretle", contexts: ["selection"] });
    chrome.contextMenus.create({ id: "baglanti", title: "Bağlantıyı Kıvılcım'a işaretle", contexts: ["link"] });
    chrome.contextMenus.create({ id: "notlu", title: "Notla / sesle işaretle…", contexts: ["page", "selection", "link"] });
  });
  refreshBadge();
});
chrome.runtime.onStartup.addListener(refreshBadge);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === "notlu") { chrome.action.openPopup?.(); return; }
  let d;
  if (info.menuItemId === "baglanti") {
    d = { url: info.linkUrl, baslik: info.selectionText || "", secili: "", metin: "" };
  } else {
    d = (await capture(tab.id)) || { url: tab.url, baslik: tab.title, metin: "" };
    if (info.selectionText && !d.secili) d.secili = info.selectionText;
  }
  await save({ ...d, id: newId(), zaman: localIso(), cihaz: "chrome", kaynak: "chrome-menu", not: "" });
});

chrome.commands.onCommand.addListener(async (cmd, tab) => {
  if (cmd !== "hizli" || !tab) return;
  const d = (await capture(tab.id)) || { url: tab.url, baslik: tab.title, metin: "" };
  await save({ ...d, id: newId(), zaman: localIso(), cihaz: "chrome", kaynak: "chrome-kisayol", not: "" });
});

// the popup asks the worker to save (so a closing popup does not cut the native call short)
chrome.runtime.onMessage.addListener((m, _s, reply) => {
  if (m && m.eylem === "kaydet") { save(m.isaret, m.ses).then(reply); return true; }
  if (m && m.eylem === "durum") { send({ eylem: "durum" }).then(reply); return true; }
  if (m && m.eylem === "ac") { send({ eylem: "ac", yol: m.yol }).then(reply); return true; }
  if (m && m.eylem === "yakala") { capture(m.tabId).then(reply); return true; }
  // a like on X: kept for tomorrow's daily feed, silently (no badge, no notification)
  if (m && m.eylem === "x_like") { send({ eylem: "x_like", like: { ...m.like, time: localIso() } }).then(reply); return true; }
  if (m && m.eylem === "x_unlike") { send({ eylem: "x_unlike", status: m.status }).then(reply); return true; }
  return false;
});

self.kivilcim = { newId, localIso };
