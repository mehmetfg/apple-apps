// Safari only: hands the page's text to the share extension (Chrome on iPhone shares just the link; the Mac fetches it).
var Sayfa = function() {};
Sayfa.prototype = {
  run: function(a) {
    var kok = document.querySelector("article") || document.querySelector("main") || document.body;
    a.completionFunction({
      url: location.href,
      baslik: (document.querySelector("meta[property='og:title']") || {}).content || document.title,
      secili: String(window.getSelection ? window.getSelection() : ""),
      metin: (kok.innerText || "").slice(0, 300000)
    });
  },
  finalize: function(a) {}
};
var ExtensionPreprocessingJS = new Sayfa;
