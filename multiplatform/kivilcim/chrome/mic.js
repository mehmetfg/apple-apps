navigator.mediaDevices.getUserMedia({ audio: true }).then((s) => {
  s.getTracks().forEach((t) => t.stop());
  document.getElementById("d").textContent = "İzin verildi ✓ Bu sekmeyi kapatabilirsin.";
}).catch((e) => { document.getElementById("d").textContent = "İzin verilmedi: " + e.message; });
