// Runs inside the page (chrome.scripting.executeScript). Returns what is worth keeping from it:
// the selection, the readable text and, on known sites, structured content (a model conversation, an X post, a GitHub file).
// Must be self-contained: no outer variables.
function kivilcimCapture() {
  const host = location.hostname.replace(/^www\./, "");
  const clean = (t) => (t || "").replace(/ /g, " ").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  const out = {
    url: location.href,
    baslik: document.title,
    secili: clean(String(window.getSelection ? window.getSelection() : "")),
    metin: "",
    sohbet: [],
    tur_ipucu: "",
  };

  // ── AI conversations: keep the whole exchange, in order (this is what makes it last)
  const LLM = {
    "chatgpt.com": () => [...document.querySelectorAll("[data-message-author-role]")].map((e) => ({
      rol: e.getAttribute("data-message-author-role") === "user" ? "user" : "assistant", metin: e.innerText })),
    "chat.openai.com": () => LLM["chatgpt.com"](),
    "claude.ai": () => [...document.querySelectorAll('[data-testid="user-message"], .font-claude-response, .font-claude-message')]
      .filter((e) => !e.parentElement.closest('[data-testid="user-message"], .font-claude-response, .font-claude-message'))
      .map((e) => ({ rol: e.matches('[data-testid="user-message"]') ? "user" : "assistant", metin: e.innerText })),
    "gemini.google.com": () => [...document.querySelectorAll("user-query, model-response")].map((e) => ({
      rol: e.tagName.toLowerCase() === "user-query" ? "user" : "assistant", metin: e.innerText })),
    "aistudio.google.com": () => [...document.querySelectorAll("ms-chat-turn")].map((e) => ({
      rol: /user/i.test(e.className + (e.querySelector("[data-turn-role]")?.getAttribute("data-turn-role") || "")) ? "user" : "assistant",
      metin: e.innerText })),
    "grok.com": () => [...document.querySelectorAll("[class*='message-bubble']")].map((e) => ({
      rol: e.closest("[class*='items-end']") ? "user" : "assistant", metin: e.innerText })),
    "perplexity.ai": () => {
      const r = [];
      document.querySelectorAll("h1, [class*='prose']").forEach((e) => {
        r.push({ rol: e.tagName === "H1" ? "user" : "assistant", metin: e.innerText });
      });
      return r;
    },
    "chat.deepseek.com": () => [...document.querySelectorAll(".ds-markdown, [class*='fbb737a4']")].map((e) => ({
      rol: e.classList.contains("ds-markdown") ? "assistant" : "user", metin: e.innerText })),
    "chat.mistral.ai": () => [...document.querySelectorAll("[data-message-author-role]")].map((e) => ({
      rol: e.getAttribute("data-message-author-role") === "user" ? "user" : "assistant", metin: e.innerText })),
  };
  const isGrokOnX = (host === "x.com" || host === "twitter.com") && location.pathname.startsWith("/i/grok");
  if (LLM[host] || isGrokOnX) {
    out.tur_ipucu = "llm";
    try {
      out.sohbet = (LLM[host] ? LLM[host]() : []).map((m) => ({ rol: m.rol, metin: clean(m.metin) })).filter((m) => m.metin);
    } catch (e) { out.sohbet = []; }
    if (!out.sohbet.length) out.metin = clean((document.querySelector("main") || document.body).innerText).slice(0, 400000);
    const ilk = out.sohbet.find((m) => m.rol === "user");
    if (ilk && (!document.title || /^(ChatGPT|Claude|Gemini|Grok|Perplexity|DeepSeek)$/i.test(document.title.trim())))
      out.baslik = ilk.metin.slice(0, 80);
    return out;
  }

  // ── X: the post on a status page (or the one the selection sits in)
  if (host === "x.com" || host === "twitter.com") {
    out.tur_ipucu = "x";
    const sel = window.getSelection && window.getSelection().anchorNode;
    const art = (sel && sel.parentElement && sel.parentElement.closest("article")) || document.querySelector("article[data-testid='tweet']");
    if (art) {
      const yazar = clean(art.querySelector("[data-testid='User-Name']")?.innerText || "").replace(/\n/g, " ");
      const metin = clean(art.querySelector("[data-testid='tweetText']")?.innerText || art.innerText);
      out.metin = (yazar ? yazar + "\n\n" : "") + metin;
      const link = art.querySelector("a[href*='/status/'] time")?.closest("a");
      if (link && !/\/status\//.test(location.pathname)) out.url = link.href;
      out.baslik = (yazar.split(" ")[0] || "X") + ": " + metin.replace(/\s+/g, " ").slice(0, 70);
    }
    return out;
  }

  // ── GitHub: a file page carries its text in a read-only textarea (works for private repos too)
  if (host === "github.com") {
    out.tur_ipucu = "github";
    const kod = document.querySelector("#read-only-cursor-text-area");
    const satirlar = [...document.querySelectorAll(".react-file-line")].map((e) => e.innerText.replace(/\n$/, ""));
    if (kod && kod.value) out.metin = kod.value.slice(0, 400000);
    else if (satirlar.length) out.metin = satirlar.join("\n").slice(0, 400000);
    else {
      const readme = document.querySelector("article.markdown-body");
      if (readme) out.metin = clean(readme.innerText).slice(0, 200000);
    }
    return out;
  }

  // ── anything else: the readable part of the page
  const kok = document.querySelector("article") || document.querySelector("main") || document.querySelector("[role='main']") || document.body;
  out.metin = clean(kok.innerText).slice(0, 300000);
  const og = document.querySelector("meta[property='og:title']")?.content;
  if (og) out.baslik = og;
  const ogType = document.querySelector("meta[property='og:type']")?.content || "";
  if (/book/i.test(ogType)) out.tur_ipucu = "kitap";
  else if (/article/i.test(ogType) && document.querySelector("meta[property='article:section'], meta[name='news_keywords']")) out.tur_ipucu = "haber";
  return out;
}
kivilcimCapture();
