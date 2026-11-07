// Kıvılcım daily feed (2026-11-06): the X timeline is not fetched; only the posts you like are kept for the next issue.
// Reads nothing else on the page: the post under the heart you pressed, nothing more. Unliking takes it back.
(() => {
  const clean = (t) => (t || "").replace(/\s+/g, " ").trim();

  function post(button) {
    const article = button.closest("article");
    if (!article) return null;
    const time = article.querySelector("a[href*='/status/'] time");
    let href = time ? time.closest("a").href : "";
    if (!href && /\/status\/\d+/.test(location.pathname)) href = location.href;
    const m = href.match(/^(https:\/\/[^/]+\/[^/]+\/status\/(\d+))/);
    if (!m) return null;
    const author = clean(article.querySelector("[data-testid='User-Name']")?.innerText);
    const text = clean(article.querySelector("[data-testid='tweetText']")?.innerText);
    return { url: m[1].replace("twitter.com", "x.com"), status: m[2], author,
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
})();
