/* ============================================================
   Vet-WAF site — fx.js
   Progressive enhancement shared by every page. Additive only:
   scroll-progress bar, back-to-top button, and a "scrolled" state
   on the nav. Does NOT duplicate main.js / site.js (nav toggle,
   copy, tilt, reveal). Dependency-free, idempotent, and fully
   gated behind prefers-reduced-motion where motion is involved.
   Loaded with `defer` so it never blocks first paint.
   ============================================================ */
(function () {
  "use strict";
  if (window.__vetwafFx) return;           // idempotent guard
  window.__vetwafFx = true;

  var reduce = false;
  try {
    reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch (e) {}

  function onReady(fn) {
    if (document.readyState === "loading")
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    else fn();
  }

  onReady(function () {
    var doc = document.documentElement;
    var nav = document.querySelector(".nav");

    // --- scroll-progress bar ---------------------------------
    var bar = document.querySelector(".scroll-progress");
    if (!bar) {
      bar = document.createElement("div");
      bar.className = "scroll-progress";
      bar.setAttribute("aria-hidden", "true");
      document.body.appendChild(bar);
    }

    // --- back-to-top button ----------------------------------
    var toTop = document.querySelector(".to-top");
    if (!toTop) {
      toTop = document.createElement("button");
      toTop.className = "to-top";
      toTop.type = "button";
      toTop.setAttribute("aria-label", "Back to top");
      toTop.innerHTML =
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<path d="M12 19V5M5 12l7-7 7 7"/></svg>';
      document.body.appendChild(toTop);
    }
    toTop.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
    });

    // --- shared scroll handler (rAF-throttled) ---------------
    var ticking = false;
    function update() {
      ticking = false;
      var st = window.pageYOffset || doc.scrollTop || 0;
      var h = doc.scrollHeight - doc.clientHeight;
      var p = h > 0 ? st / h : 0;
      if (p < 0) p = 0; else if (p > 1) p = 1;
      bar.style.transform = "scaleX(" + p + ")";
      if (nav) nav.classList.toggle("scrolled", st > 8);
      toTop.classList.toggle("show", st > 600);
    }
    function onScroll() {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(update);
      }
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    update();
  });
})();
