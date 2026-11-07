import AppKit
import WebKit

/// Injected into every model page (isolated content world). Reads state and types the question.
let coreScript = #"""
(() => {
if (window.__kurultay) return;
const visible = (e) => { if (!e) return false; const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
  return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
const first = (sels) => { for (const s of sels || []) { try { const els = [...document.querySelectorAll(s)].filter(visible);
  if (els.length) return els[els.length - 1]; } catch (_) {} } return null; };
const textOf = (e) => (e.innerText || e.textContent || '').replace(/ /g, ' ').trim();
const answers = (cfg) => {
  for (const s of cfg.answer || []) {
    let els = []; try { els = [...document.querySelectorAll(s)]; } catch (_) { continue; }
    if (cfg.answerExclude) els = els.filter(e => !e.closest(cfg.answerExclude));
    els = els.filter(e => !els.some(o => o !== e && o.contains(e)));
    if (els.length) return els;
  }
  return [];
};
const label = (b) => ((b.getAttribute('aria-label') || b.getAttribute('title') || b.getAttribute('data-testid') || '') + ' ' + textOf(b)).trim();
const genericStop = () => [...document.querySelectorAll('button,[role=button]')].find(b => visible(b) &&
  /(^|\s)(stop|durdur)(\s|$)|stop[- ](generating|response|streaming|button)|yanıtı durdur|cevabı durdur/i.test(label(b).slice(0, 80)));
const cls = (e) => String(e.className && e.className.baseVal !== undefined ? e.className.baseVal : (e.className || ''));
const thinkButton = (cfg) => {
  if (!cfg.think) return null;
  const re = new RegExp(cfg.think.match, 'i');
  return [...document.querySelectorAll('button,[role=button],[role=switch],[role=checkbox],div[class*=button]')]
    .filter(visible).find(e => re.test(label(e).slice(0, 60))) || null;
};
const thinkState = (cfg, b) => {
  if (!b) return cfg.think ? 'missing' : 'none';
  if (cfg.think.onClass) return cls(b).includes(cfg.think.onClass) ? 'on' : 'off';
  const a = b.getAttribute('aria-pressed') || b.getAttribute('aria-checked') || b.getAttribute('data-state');
  if (a !== null) return /true|on|checked|active/.test(a) ? 'on' : 'off';
  return 'unknown';
};
const isGuest = () => [...document.querySelectorAll('button,a,[role=button]')].some(b => {
  const t = (b.innerText || b.getAttribute('aria-label') || '').trim();
  return t.length > 0 && t.length < 25 && visible(b) && /^(log ?in|sign ?in|sign up|giriş yap|oturum aç|kaydol|kayıt ol)\b/i.test(t);
});
window.__kurultay = {
  state(cfg) {
    const els = answers(cfg);
    const last = els.length ? textOf(els[els.length - 1]) : '';
    const input = first(cfg.input);
    const stop = first(cfg.stop) || genericStop();
    const head = (document.body ? document.body.innerText : '').slice(0, 3000);
    const login = !input && /log ?in|sign ?in|giriş yap|oturum aç|continue with google|google ile/i.test(head);
    const guest = !login && isGuest();
    // a block that only shows the thinking header ("Thought Process", "Thinking…") is still working
    const onlyHeader = last.length < 60 && /^(thought process|thinking|thought for|düşün|reasoning|deep ?think)/i.test(last);
    return { count: els.length, last, busy: !!stop || onlyHeader, input: !!input, login, guest, url: location.href, title: document.title,
             think: thinkState(cfg, thinkButton(cfg)) };
  },
  ensureThink(cfg) {
    const b = thinkButton(cfg); const st = thinkState(cfg, b);
    if (st === 'off') { b.click(); return thinkState(cfg, b) === 'on' ? 'on' : 'clicked'; }
    return st;
  },
  prepare(cfg) {
    const input = first(cfg.input);
    if (!input) return { ok: false, error: 'noInput' };
    input.focus();
    if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
      const proto = input.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(input, '');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    } else {
      const sel = window.getSelection(); const range = document.createRange();
      range.selectNodeContents(input); sel.removeAllRanges(); sel.addRange(range);
      document.execCommand('delete', false, null);
    }
    return { ok: true };
  },
  typed(cfg) { const input = first(cfg.input); return input ? (input.value !== undefined && input.tagName !== 'DIV' ? input.value : textOf(input)).length : -1; },
  insert(cfg, text) {
    const input = first(cfg.input);
    if (!input) return { ok: false, error: 'noInput' };
    input.focus();
    if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
      const proto = input.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(input, text);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      document.execCommand('insertText', false, text);
      if (textOf(input).length === 0) {
        const dt = new DataTransfer(); dt.setData('text/plain', text);
        input.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      }
    }
    return { ok: true };
  },
  async submit(cfg) {
    await new Promise(r => setTimeout(r, 500));
    for (let i = 0; i < 12; i++) {
      const btn = first(cfg.send);
      if (btn && !btn.disabled && btn.getAttribute('aria-disabled') !== 'true') { btn.click(); return { ok: true, via: 'button' }; }
      await new Promise(r => setTimeout(r, 300));
    }
    // generic: an enabled send/submit button near the input
    const input = first(cfg.input);
    let box = input; for (let i = 0; i < 6 && box && box.parentElement; i++) box = box.parentElement;
    const near = [...(input && (input.closest('form') || box) || document).querySelectorAll('button,[role=button]')].filter(visible)
      .find(b => !b.disabled && b.getAttribute('aria-disabled') !== 'true' &&
        (/^(send|submit|gönder|ask|sor)|send message|send prompt|mesaj gönder/i.test(label(b)) || b.type === 'submit'));
    if (near) { near.click(); return { ok: true, via: 'near' }; }
    return { ok: true, via: 'enter' };
  },
  async send(cfg, text) {
    const p = this.prepare(cfg); if (!p.ok) return p;
    this.insert(cfg, text);
    const r = await this.submit(cfg);
    if (r.via === 'enter') {
      const input = first(cfg.input);
      const ev = (t) => input && input.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
      ev('keydown'); ev('keypress'); ev('keyup');
    }
    return r;
  }
};
})();
"""#

/// True when the page shows a sign-in button (a guest page, even if it has a text box).
let guestScript = #"""
(() => { const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  return [...document.querySelectorAll('button,a,[role=button]')].some(b => {
    const t = (b.innerText || b.getAttribute('aria-label') || '').trim();
    return t.length > 0 && t.length < 25 && vis(b) && /^(log ?in|sign ?in|sign up|giriş yap|oturum aç|kaydol|kayıt ol)\b/i.test(t); }); })()
"""#

/// Makes a page that sits behind other windows still behave as visible (some sites hide controls otherwise).
let visibleScript = #"""
try {
  Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
  Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
  document.hasFocus = () => true;
} catch (_) {}
"""#

struct PageState {
    var count = 0
    var last = ""
    var busy = false
    var input = false
    var login = false
    var guest = false
    var url = ""
    var title = ""
    var think = "none"

    init() {}
    init(_ d: [String: Any]) {
        count = d["count"] as? Int ?? 0
        last = d["last"] as? String ?? ""
        busy = d["busy"] as? Bool ?? false
        input = d["input"] as? Bool ?? false
        login = d["login"] as? Bool ?? false
        guest = d["guest"] as? Bool ?? false
        url = d["url"] as? String ?? ""
        title = d["title"] as? String ?? ""
        think = d["think"] as? String ?? "none"
    }
}

enum WebOutcome {
    case done(text: String, thinking: String, url: String)
    case timeout(text: String, thinking: String, url: String)
    case failed(reason: String)
}


/// One model = one live browser tab: a tab in the Kurultay Chrome (engine "chrome", default)
/// or an embedded WebKit view (engine "webkit"). The user signs in once; the session stays.
@MainActor
final class WebSeat: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var config: SeatConfig
    @Published var page = PageState()
    @Published var busyAsking = false
    @Published var engineError: String?
    let engine: String
    let webView: WKWebView?
    private var tab: ChromeTab?
    private var popups: [NSWindow] = []
    private var configJSON: [String: Any] = [:]

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    let index: Int

    init(config: SeatConfig, engine: String, index: Int = 0) {
        self.config = config
        self.index = index
        self.engine = engine
        if engine == "webkit" {
            let conf = WKWebViewConfiguration()
            conf.websiteDataStore = .default()
            conf.preferences.javaScriptCanOpenWindowsAutomatically = true
            if #available(macOS 14.0, *) { conf.preferences.inactiveSchedulingPolicy = .none }
            conf.userContentController.addUserScript(WKUserScript(source: coreScript, injectionTime: .atDocumentEnd,
                                                                  forMainFrameOnly: true, in: .defaultClient))
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: conf)
            wv.customUserAgent = Self.userAgent
            wv.allowsBackForwardNavigationGestures = true
            webView = wv
        } else {
            webView = nil
        }
        super.init()
        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        updateConfig(config)
        if let wv = webView, let u = URL(string: config.url) { wv.load(URLRequest(url: u)) }
        if engine == "chrome" { Task { _ = await connect() } }
    }

    func updateConfig(_ c: SeatConfig) {
        config = c
        if let d = try? JSONEncoder().encode(c), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { configJSON = o }
    }

    private var host: String { URL(string: config.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? config.id }

    // MARK: Chrome tab

    /// Same site: same host, or the same name under another ending (kimi.com → kimi.ai).
    private func sameSite(_ url: String) -> Bool {
        guard let h = URL(string: url)?.host?.lowercased().replacingOccurrences(of: "www.", with: "") else { return false }
        if h == host { return true }
        let a = h.split(separator: "."), b = host.split(separator: ".")
        return a.count == b.count && a.count >= 2 && Array(a.dropLast()) == Array(b.dropLast())
    }

    /// nil = the page does not answer (hung renderer), true = shows a sign-in button, false = signed in.
    private func signedOut(_ page: [String: Any]) async -> Bool? {
        guard let id = page["id"] as? String, let ws = (page["webSocketDebuggerUrl"] as? String).flatMap(URL.init) else { return nil }
        let t = ChromeTab(targetId: id, ws: ws)
        defer { t.close() }
        return (try? await t.evaluate(guestScript, timeout: 6)) as? Bool
    }

    /// Finds this seat's tab in the Kurultay Chrome, or opens one.
    /// Among this site's tabs it keeps the signed-in one and closes the copies, so a sign-in made in any
    /// window counts. A tab that does not answer is replaced.
    private func connect() async -> ChromeTab? {
        if let t = tab, !t.closed { return t }
        let chrome = ChromeHost.shared
        guard await chrome.ensureRunning() else { engineError = "Chrome açılamadı"; return nil }
        let key = "kurultay.win.\(config.id)"
        let stored = UserDefaults.standard.string(forKey: key)
        let pages = await chrome.pages()
        let mine = pages.filter { sameSite($0["url"] as? String ?? "") }
        var states: [(page: [String: Any], out: Bool?)] = []
        for p in mine { states.append((p, await signedOut(p))) }
        let live = states.filter { $0.out != nil }
        let pick = live.first { $0.out == false && $0.page["id"] as? String == stored }
            ?? live.first { $0.out == false }
            ?? live.first { $0.page["id"] as? String == stored }
            ?? live.first
        var target = pick?.page
        for s in states where (s.page["id"] as? String) != (target?["id"] as? String) {
            if let id = s.page["id"] as? String { await chrome.close(id) }   // copies and hung tabs; sign-in stays in the profile
        }
        if target == nil {
            if let id = await chrome.newWindow(config.url, index: index) {
                try? await Task.sleep(for: .milliseconds(600))
                target = await chrome.pages().first { $0["id"] as? String == id }
            }
            for p in pages where (p["url"] as? String) == "about:blank" {
                if let id = p["id"] as? String { await chrome.close(id) }
            }
        }
        guard let t = target, let id = t["id"] as? String, let ws = (t["webSocketDebuggerUrl"] as? String).flatMap(URL.init) else {
            engineError = "Chrome sekmesi açılamadı"; return nil
        }
        UserDefaults.standard.set(id, forKey: key)
        let ct = ChromeTab(targetId: id, ws: ws)
        _ = try? await ct.send("Page.enable")
        _ = try? await ct.send("Page.addScriptToEvaluateOnNewDocument", ["source": visibleScript + coreScript])
        _ = try? await ct.send("Emulation.setFocusEmulationEnabled", ["enabled": true])
        _ = try? await ct.evaluate(visibleScript)
        let url = t["url"] as? String ?? ""
        if URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") != host {
            await ct.navigate(config.url)            // the site moved (kimi.com → kimi.ai)
            try? await Task.sleep(for: .seconds(3))
        } else if pick?.out == true {
            _ = try? await ct.send("Page.reload")     // opened before the sign-in: a reload picks it up
            try? await Task.sleep(for: .seconds(3))
        }
        tab = ct
        engineError = nil
        return ct
    }

    /// Drops the remembered tab and chooses again (the user may have signed in in another window).
    func relink() async -> Bool {
        guard engine == "chrome" else { return true }
        tab?.close(); tab = nil
        return await connect() != nil
    }

    func show() async {
        if engine == "chrome", let t = await connect() { await ChromeHost.shared.activate(t.targetId) }
    }

    // MARK: JS bridge (same body for both engines)

    func run(_ body: String, _ args: [String: Any] = [:], timeout: Double = 60) async throws -> Any? {
        if let wv = webView {
            let has = (try? await wv.callAsyncJavaScript("return !!window.__kurultay", arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool
            if has != true { _ = try? await wv.evaluateJavaScript(coreScript, in: nil, contentWorld: .defaultClient) }
            return try await wv.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .defaultClient)
        }
        guard let t = await connect() else { throw ChromeTab.Failure(message: engineError ?? "Chrome yok") }
        let names = args.keys.sorted()
        let values = try names.map { k -> String in
            String(decoding: try JSONSerialization.data(withJSONObject: args[k]!, options: [.fragmentsAllowed]), as: UTF8.self)
        }
        let expr = "(async () => { if (!window.__kurultay) { \(coreScript) } return await (async (\(names.joined(separator: ","))) => { \(body) })(\(values.joined(separator: ","))); })()"
        do { return try await t.evaluate(expr, timeout: timeout) }
        catch { if t.closed { tab = nil }; throw error }
    }

    @discardableResult
    func refreshState() async -> PageState {
        let raw = try? await run("return window.__kurultay.state(cfg)", ["cfg": configJSON], timeout: 8)
        let s = (raw as? [String: Any]).map(PageState.init) ?? PageState()
        page = s
        return s
    }

    private func sleep(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    func load(_ url: String) async {
        if let wv = webView, let u = URL(string: url) { wv.load(URLRequest(url: u)) }
        else if let t = await connect() { await t.navigate(url) }
    }

    func reload() async {
        if let wv = webView { wv.reload() } else if let t = await connect() { _ = try? await t.send("Page.reload") }
    }

    func goBack() async {
        if let wv = webView { wv.goBack() } else { _ = try? await run("history.back(); return true") }
    }

    func loadNewChat() async {
        await load(config.newChatUrl ?? config.url)
        await sleep(3)
    }

    private func typeQuestion(_ text: String) async -> (ok: Bool, error: String?) {
        if engine == "chrome", let t = await connect() {
            let p = (try? await run("return window.__kurultay.prepare(cfg)", ["cfg": configJSON])) as? [String: Any]
            guard p?["ok"] as? Bool == true else { return (false, (p?["error"] as? String) ?? "yazı kutusu yok") }
            // real keyboard-level text: works for textareas, ProseMirror, Lexical, Quill alike
            do { try await t.insertText(text) } catch { return (false, error.localizedDescription) }
            if ((try? await run("return window.__kurultay.typed(cfg)", ["cfg": configJSON])) as? Int ?? 0) == 0 {
                _ = try? await run("return window.__kurultay.insert(cfg, text)", ["cfg": configJSON, "text": text])
            }
            // a site that silently cuts the question would answer a different question
            let typed = (try? await run("return window.__kurultay.typed(cfg)", ["cfg": configJSON])) as? Int ?? 0
            if typed > 0 && typed < text.count - 200 {
                _ = try? await run("return window.__kurultay.prepare(cfg)", ["cfg": configJSON])
                return (false, "site soruyu kesti: \(typed) / \(text.count) karakter; soruyu kısalt")
            }
            let r = (try? await run("return await window.__kurultay.submit(cfg)", ["cfg": configJSON])) as? [String: Any]
            if r?["via"] as? String == "enter" {
                await t.pressEnter()
            }
            return (true, nil)
        }
        let sent = (try? await run("return await window.__kurultay.send(cfg, text)", ["cfg": configJSON, "text": text])) as? [String: Any]
        return (sent?["ok"] as? Bool == true, sent?["error"] as? String)
    }

    /// Types the question, presses send and waits until the answer stops growing.
    func ask(_ text: String, newChat: Bool, resume: String?, timeout: TimeInterval, progress: @escaping (AnswerState, String) -> Void) async -> WebOutcome {
        busyAsking = true
        defer { busyAsking = false }
        if engine == "chrome", !(await relink()) { return .failed(reason: engineError ?? "Chrome yok") }
        if let m = config.maxChars, text.count > m {   // Council.runSeat shortens first; this is the last guard
            return .failed(reason: "soru çok uzun: \(text.count) karakter, \(config.name) en çok \(m) kabul ediyor")
        }
        if newChat { await loadNewChat() }
        else if let r = resume, r != page.url { await load(r); await sleep(3) }
        var s = await refreshState()
        let readyBy = Date().addingTimeInterval(25)
        while !s.input && Date() < readyBy { await sleep(1); s = await refreshState() }
        if !s.input || s.guest {   // still signed out: one reload, in case the sign-in was made elsewhere
            await reload(); await sleep(4)
            s = await refreshState()
            while !s.input && Date() < readyBy.addingTimeInterval(15) { await sleep(1); s = await refreshState() }
        }
        if !s.input { return .failed(reason: s.login || s.guest ? "giriş gerekli" : "yazı kutusu bulunamadı") }

        var thinking = (try? await run("return window.__kurultay.ensureThink(cfg)", ["cfg": configJSON])) as? String ?? "none"
        await sleep(0.4)
        let base = await refreshState()
        progress(.sending, "")
        let sent = await typeQuestion(text)
        guard sent.ok else { return .failed(reason: sent.error ?? "gönderilemedi") }

        let start = Date()
        var started = false
        var lastText = ""
        var stable = 0
        while Date().timeIntervalSince(start) < timeout {
            await sleep(1.5)
            let now = await refreshState()
            if now.think == "on" { thinking = "on" }
            if !started {
                started = now.count > base.count || (!now.last.isEmpty && now.last != base.last) || now.busy
                if !started && Date().timeIntervalSince(start) > 45 {
                    return .failed(reason: now.login ? "giriş gerekli" : "cevap başlamadı")
                }
                if started { progress(.thinking, "") }
                continue
            }
            let fresh = now.count > base.count || now.last != base.last
            let text = fresh ? now.last : ""
            if !text.isEmpty { progress(.writing, text) }
            if !now.busy && !text.isEmpty && text == lastText { stable += 1 } else { stable = 0 }
            lastText = text
            if stable >= 3 {
                Task { await AccountKeeper.backup() }
                return .done(text: text, thinking: thinking, url: now.url)
            }
        }
        return .timeout(text: lastText, thinking: thinking, url: page.url)
    }

    // MARK: WebKit popups (only for engine "webkit")

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let pop = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        pop.customUserAgent = Self.userAgent
        pop.uiDelegate = self
        let w = NSWindow(contentRect: pop.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "\(config.name) · giriş"
        w.contentView = pop
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        popups.append(w)
        return pop
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.removeAll { w in
            if w.contentView === webView { w.close(); return true }
            return false
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await refreshState() }
    }
}
