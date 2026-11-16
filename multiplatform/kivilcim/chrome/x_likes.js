// Kıvılcım on x.com.
// 2026-11-06: the posts you like are kept for the next daily issue; unliking takes them back.
// 2026-11-11 (Radar): the posts that pass on screen while you read are noted too — author, text, links, the counts X
// already shows, and whether you are on the "Following" tab — so Kıvılcım can pick the important ones from the people
// you follow. Nothing extra is requested from X: only what is already on the page is read. "X'i tara" in Kıvılcım opens
// x.com/home#kivilcim-scan: the Following tab is chosen and scrolled slowly for about a minute, once, like reading.
(() => {
  const clean = (t) => (t || "").replace(/\s+/g, " ").trim();

  function statusLink(article) {
    const time = article.querySelector("a[href*='/status/'] time");
    let href = time ? time.closest("a").href : "";
    if (!href && /\/status\/\d+/.test(location.pathname)) href = location.href;
    return href.match(/^(https:\/\/[^/]+\/([^/]+)\/status\/(\d+))/);
  }

  function post(button) {
    const article = button.closest("article");
    if (!article) return null;
    const m = statusLink(article);
    if (!m) return null;
    const author = clean(article.querySelector("[data-testid='User-Name']")?.innerText);
    const text = clean(article.querySelector("[data-testid='tweetText']")?.innerText);
    return { url: m[1].replace("twitter.com", "x.com"), status: m[3], author,
      text, title: `${author.split(" ")[0] || "X"}: ${text.slice(0, 90) || "(metinsiz post)"}` };
  }

  function tell(message) {
    // after the extension is reloaded, an old page's script has no way back: quietly do nothing
    try { chrome.runtime.sendMessage(message, () => void chrome.runtime.lastError); } catch (e) { /* see above */ }
  }

  // capture phase: X replaces the button right after the click
  document.addEventListener("click", (e) => {
    const like = e.target.closest?.("[data-testid='like']");
    const unlike = e.target.closest?.("[data-testid='unlike']");
    const p = (like || unlike) && post(like || unlike);
    if (!p) return;
    if (like) tell({ eylem: "x_like", like: p });
    else tell({ eylem: "x_unlike", status: p.status });
  }, true);

  // ───────── Radar: posts seen on screen

  /** "1.234", "1,2 B", "12K", "3,4 Mn" → number. X writes the full number in aria-label in most locales. */
  function count(el) {
    const label = el?.getAttribute("aria-label") || "";
    const m = label.match(/([\d.,]+)\s*(B|K|Mn|M|Bn)?/i);
    if (!m) return 0;
    let raw = m[1];
    const unit = (m[2] || "").toLowerCase();
    if (unit) raw = raw.replace(",", ".");
    else raw = raw.replace(/[.,]/g, "");
    let n = parseFloat(raw) || 0;
    if (unit === "k" || unit === "b") n *= 1000;          // "B" = bin in Turkish
    if (unit === "m" || unit === "mn") n *= 1e6;
    if (unit === "bn") n *= 1e9;
    return Math.round(n);
  }

  function onFollowingTab() {
    if (!/^\/home\/?$/.test(location.pathname)) return false;
    const tabs = [...document.querySelectorAll("[role='tab']")];
    const sel = tabs.find((t) => t.getAttribute("aria-selected") === "true");
    if (!sel) return false;
    return tabs.indexOf(sel) === 1 || /following|takip/i.test(sel.innerText);
  }

  function read(article) {
    const m = statusLink(article);
    if (!m) return null;
    if (article.querySelector("[data-testid='placementTracking']")) return null;   // ads
    const userName = clean(article.querySelector("[data-testid='User-Name']")?.innerText);
    const handle = (userName.match(/@([A-Za-z0-9_]+)/) || [])[1] || m[2];
    const text = clean(article.querySelector("[data-testid='tweetText']")?.innerText);
    const links = new Set();
    article.querySelectorAll("[data-testid='tweetText'] a[href^='https://t.co'], [data-testid='card.wrapper'] a[href]").forEach((a) => {
      const shown = clean(a.innerText).replace(/^https?:\/\//, "");
      if (/^[\w.-]+\.[a-z]{2,}(\/|$)/i.test(shown)) links.add(shown.split(" ")[0]);
    });
    const cardDomain = clean(article.querySelector("[data-testid='card.wrapper'] [dir='ltr'] span")?.innerText);
    if (/^[\w.-]+\.[a-z]{2,}$/i.test(cardDomain)) links.add(cardDomain);
    const image = article.querySelector("[data-testid='tweetPhoto'] img")?.src || "";
    return {
      status: m[3], url: m[1].replace("twitter.com", "x.com"),
      author: userName.split("@")[0].trim(), handle,
      text, links: [...links].slice(0, 4), image,
      replies: count(article.querySelector("[data-testid='reply']")),
      reposts: count(article.querySelector("[data-testid='retweet'], [data-testid='unretweet']")),
      likes: count(article.querySelector("[data-testid='like'], [data-testid='unlike']")),
      views: count(article.querySelector("a[href$='/analytics']")),
      posted: article.querySelector("time")?.getAttribute("datetime") || "",
      following: onFollowingTab(),
      seen: new Date().toISOString(),
    };
  }

  const sent = new Map();          // status → likes count when last sent
  let batch = [];
  const timers = new WeakMap();

  const watch = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        // on screen for a moment: it was really passed by, not flung past
        timers.set(e.target, setTimeout(() => {
          const p = read(e.target);
          if (!p) return;
          const last = sent.get(p.status);
          if (last !== undefined && p.likes <= last * 1.2 + 5) return;
          sent.set(p.status, p.likes);
          batch.push(p);
          if (batch.length >= 25) flush();
        }, 700));
      } else {
        clearTimeout(timers.get(e.target));
      }
    }
  }, { threshold: 0.6 });

  function flush() {
    if (!batch.length) return;
    const posts = batch;
    batch = [];
    tell({ eylem: "x_seen", posts });
  }
  setInterval(flush, 15000);
  addEventListener("pagehide", flush);
  document.addEventListener("visibilitychange", () => { if (document.hidden) flush(); });

  new MutationObserver(() => {
    document.querySelectorAll("article[data-testid='tweet']:not([data-kivilcim])").forEach((a) => {
      a.setAttribute("data-kivilcim", "1");
      watch.observe(a);
    });
  }).observe(document.documentElement, { childList: true, subtree: true });

  // ───────── "X'i tara": asked for from Kıvılcım, once, about a minute, at reading pace

  async function scan() {
    history.replaceState(null, "", location.pathname);   // a reload does not start it again
    const toast = document.createElement("div");
    toast.style.cssText = "position:fixed;z-index:99999;left:50%;bottom:28px;transform:translateX(-50%);padding:10px 16px;" +
      "border-radius:12px;background:#E2552B;color:#fff;font:600 14px -apple-system,system-ui;box-shadow:0 6px 24px #0004";
    document.body.appendChild(toast);
    const say = (s) => { toast.textContent = s; };
    say("Kıvılcım: Takip edilenler okunuyor…");
    for (let i = 0; i < 20 && !document.querySelector("[role='tab']"); i++) await new Promise((r) => setTimeout(r, 500));
    const tabs = [...document.querySelectorAll("[role='tab']")];
    const following = tabs.find((t) => /following|takip/i.test(t.innerText)) || tabs[1];
    if (following && following.getAttribute("aria-selected") !== "true") {
      following.click();
      await new Promise((r) => setTimeout(r, 2500));
    }
    const until = Date.now() + 70000;
    let stop = false;
    const cancel = () => { stop = true; };
    addEventListener("wheel", cancel, { once: true });
    addEventListener("keydown", cancel, { once: true });
    while (Date.now() < until && !stop) {
      window.scrollBy({ top: innerHeight * 0.7, behavior: "smooth" });
      say(`Kıvılcım: Takip edilenler okunuyor… ${Math.ceil((until - Date.now()) / 1000)} sn (durdurmak için kaydır)`);
      await new Promise((r) => setTimeout(r, 2600));
    }
    flush();
    say(stop ? "Kıvılcım: durdu. Okunanlar Akış › X'e geçti." : "Kıvılcım: bitti. Akış › X birkaç dakika içinde dolar.");
    setTimeout(() => toast.remove(), 5000);
  }
  if (location.hash === "#kivilcim-scan") setTimeout(scan, 1500);
})();
