// Kıvılcım · Dikkat — the popup: what will be kept, your note, your voice, and the "look now" list from Claude.
const $ = (id) => document.getElementById(id);
const TUR = { x: "X postu", github: "GitHub", llm: "Yapay zekâ sohbeti", haber: "Haber", makale: "Makale",
  kitap: "Kitap", video: "Video", metin: "Metin" };
const LLM_HOSTS = ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "aistudio.google.com", "grok.com",
  "perplexity.ai", "chat.deepseek.com", "copilot.microsoft.com", "chat.mistral.ai", "notebooklm.google.com"];

let veri = null, tab = null, kaydedici = null, parcalar = [], sesBlob = null, baslangic = 0, sayac = null;

function turTahmin(d) {
  if (d.tur_ipucu) return d.tur_ipucu;
  let h = "";
  try { h = new URL(d.url).hostname.replace(/^www\./, ""); } catch (e) {}
  if (LLM_HOSTS.includes(h)) return "llm";
  if (h === "x.com" || h === "twitter.com") return "x";
  if (h.endsWith("github.com")) return "github";
  if (/youtube\.com|youtu\.be|vimeo\.com/.test(h)) return "video";
  if (/\.pdf($|\?)/i.test(d.url) || /arxiv|medium|substack|doi\.org|plato\.stanford/.test(h)) return "makale";
  return "metin";
}

function msg(m) { return new Promise((r) => chrome.runtime.sendMessage(m, r)); }

async function yukle() {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  veri = (await msg({ eylem: "yakala", tabId: tab.id })) || { url: tab.url, baslik: tab.title, metin: "", secili: "" };
  const tur = turTahmin(veri);
  $("tur").textContent = TUR[tur] || "Metin";
  $("baslik").value = veri.baslik || tab.title || "";
  try { $("site").textContent = new URL(veri.url).hostname.replace(/^www\./, "") + new URL(veri.url).pathname; } catch (e) {}
  if (veri.secili) { $("secili").hidden = false; $("secili").textContent = veri.secili; }
  const n = (veri.sohbet || []).length;
  const k = (veri.metin || "").split(/\s+/).filter(Boolean).length;
  $("ozet").textContent = n ? `Sohbetin tamamı kaydedilecek: ${n} mesaj` :
    k ? `Sayfanın metni kaydedilecek: ${k.toLocaleString("tr-TR")} kelime` : "Bağlantı kaydedilecek, metni Mac'te çekilir";
  $("not").focus();
  const d = await msg({ eylem: "durum" });
  if (d && d.ok && d.simdi && d.simdi.length) {
    $("simdi").hidden = false;
    for (const s of d.simdi) {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = s.url || "#"; a.textContent = s.baslik; a.target = "_blank";
      li.appendChild(a);
      if (s.neden) { const sm = document.createElement("small"); sm.textContent = s.neden; li.appendChild(sm); }
      $("liste").appendChild(li);
    }
  } else if (d && !d.ok) {
    $("durum").className = "durum kotu";
    $("durum").textContent = "Mac yardımcısı yanıt vermiyor: chrome/host/kur.sh";
  }
}

async function mikrofon() {
  if (kaydedici && kaydedici.state === "recording") { kaydedici.stop(); return; }
  let akis;
  try { akis = await navigator.mediaDevices.getUserMedia({ audio: true }); }
  catch (e) { chrome.tabs.create({ url: chrome.runtime.getURL("mic.html") }); return; }
  parcalar = []; sesBlob = null;
  const tip = MediaRecorder.isTypeSupported("audio/mp4") ? "audio/mp4" : "audio/webm;codecs=opus";
  kaydedici = new MediaRecorder(akis, { mimeType: tip });
  kaydedici.ondataavailable = (e) => e.data.size && parcalar.push(e.data);
  kaydedici.onstop = () => {
    akis.getTracks().forEach((t) => t.stop());
    clearInterval(sayac);
    sesBlob = new Blob(parcalar, { type: tip });
    $("dinle").src = URL.createObjectURL(sesBlob); $("dinle").hidden = false;
    $("mik").classList.remove("kayitta"); $("mik").textContent = "🎙 Yeniden kaydet";
  };
  kaydedici.start(1000);
  baslangic = Date.now();
  $("mik").classList.add("kayitta"); $("mik").textContent = "■ Bitir";
  sayac = setInterval(() => {
    const s = Math.round((Date.now() - baslangic) / 1000);
    $("sure").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }, 500);
}

function b64(blob) {
  return new Promise((r) => { const f = new FileReader(); f.onload = () => r(String(f.result).split(",")[1]); f.readAsDataURL(blob); });
}

async function kaydet() {
  if (kaydedici && kaydedici.state === "recording") { kaydedici.stop(); await new Promise((r) => setTimeout(r, 300)); }
  $("kaydet").disabled = true;
  $("durum").className = "durum"; $("durum").textContent = "Kaydediliyor…";
  const p = (n) => String(n).padStart(2, "0");
  const d = new Date();
  const id = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}-chrome-` +
    Math.random().toString(16).slice(2, 6);
  const off = -d.getTimezoneOffset();
  const zaman = new Date(d.getTime() + off * 60000).toISOString().slice(0, 19) + (off >= 0 ? "+" : "-") +
    p(Math.floor(Math.abs(off) / 60)) + ":" + p(Math.abs(off) % 60);
  const isaret = { ...veri, id, zaman, cihaz: "chrome", kaynak: "chrome", baslik: $("baslik").value.trim(),
    not: $("not").value.trim(), tur_ipucu: veri.tur_ipucu || turTahmin(veri) };
  const ses = sesBlob ? { veri: await b64(sesBlob), tip: sesBlob.type } : null;
  const r = await msg({ eylem: "kaydet", isaret, ses });
  if (r && r.ok) {
    $("durum").className = "durum iyi"; $("durum").textContent = "İşaretlendi ✓";
    setTimeout(() => window.close(), 700);
  } else {
    $("kaydet").disabled = false;
    $("durum").className = "durum kotu"; $("durum").textContent = "Kaydedilemedi: " + ((r && r.hata) || "?");
  }
}

$("mik").addEventListener("click", mikrofon);
$("kaydet").addEventListener("click", kaydet);
document.addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) kaydet(); });
yukle();
