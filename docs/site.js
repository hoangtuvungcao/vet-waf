// Vet-WAF docs — shared behaviour: i18n (EN/VI), nav, copy, 3D tilt, reveal.
// Each page defines window.VETWAF_I18N = { en: {...}, vi: {...} } before this
// script; the shared chrome strings below are merged in automatically.
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  var CHROME = {
    en: {
      'nav.docs': 'Docs', 'nav.home': 'Home',
      'doc.quickstart': 'Quick start', 'doc.kernel': 'Kernel patching',
      'doc.frang': 'Frang rules', 'doc.config': 'Configuration',
      'doc.trouble': 'Troubleshooting',
      'doc.onthispage': 'On this page',
      'footer.legal': 'Vet-WAF is free software under <b>GPLv2</b> — engine, tooling and this site — derived from Tempesta FW. &copy; 2026 Vet-WAF.'
    },
    vi: {
      'nav.docs': 'Tài liệu', 'nav.home': 'Trang chủ',
      'doc.quickstart': 'Bắt đầu nhanh', 'doc.kernel': 'Vá nhân Linux',
      'doc.frang': 'Luật Frang', 'doc.config': 'Cấu hình',
      'doc.trouble': 'Xử lý sự cố',
      'doc.onthispage': 'Trong trang này',
      'footer.legal': 'Vet-WAF là phần mềm tự do theo giấy phép <b>GPLv2</b> — engine, công cụ và cả website này — bắt nguồn từ Tempesta FW. &copy; 2026 Vet-WAF.'
    }
  };

  var PAGE = window.VETWAF_I18N || { en: {}, vi: {} };
  var I18N = { en: {}, vi: {} };
  ['en', 'vi'].forEach(function (l) {
    var k;
    for (k in CHROME[l]) I18N[l][k] = CHROME[l][k];
    for (k in (PAGE[l] || {})) I18N[l][k] = PAGE[l][k];
  });

  function applyLang(lang) {
    if (!I18N[lang]) lang = 'en';
    var dict = I18N[lang];
    document.documentElement.setAttribute('lang', lang);
    document.documentElement.setAttribute('data-lang', lang);

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var k = el.getAttribute('data-i18n');
      if (!(k in dict)) return;
      if (el.tagName === 'META') el.setAttribute('content', dict[k]);
      else el.textContent = dict[k];
    });
    document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
      var k = el.getAttribute('data-i18n-html');
      if (k in dict) el.innerHTML = dict[k];
    });
    document.querySelectorAll('[data-lang-set]').forEach(function (b) {
      b.setAttribute('aria-pressed',
        b.getAttribute('data-lang-set') === lang ? 'true' : 'false');
    });
    try { localStorage.setItem('vetwaf-lang', lang); } catch (e) {}
  }

  var saved = 'en';
  try { saved = localStorage.getItem('vetwaf-lang') || 'en'; } catch (e) {}
  applyLang(saved);

  document.querySelectorAll('[data-lang-set]').forEach(function (b) {
    b.addEventListener('click', function () {
      applyLang(b.getAttribute('data-lang-set'));
    });
  });

  /* ---------------- mobile nav ---------------- */
  var toggle = document.getElementById('navToggle');
  var links = document.getElementById('navLinks');
  if (toggle && links) {
    toggle.addEventListener('click', function () {
      var open = links.classList.toggle('open');
      toggle.classList.toggle('open', open);
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    links.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        links.classList.remove('open');
        toggle.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* ---------------- copy-to-clipboard ---------------- */
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var block = btn.closest('.code');
      var code = block ? block.querySelector('code') : null;
      if (!code) return;
      var text = code.innerText;
      var done = function () {
        var lang = document.documentElement.getAttribute('data-lang') || 'en';
        var old = btn.textContent;
        btn.textContent = lang === 'vi' ? 'Đã chép!' : 'Copied!';
        setTimeout(function () { btn.textContent = old; }, 1600);
      };
      function fallback() {
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(fallback);
      } else { fallback(); }
    });
  });

  /* ---------------- 3D pointer tilt ---------------- */
  var reduce = window.matchMedia
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var fine = window.matchMedia && window.matchMedia('(pointer: fine)').matches;
  if (!reduce && fine) {
    document.querySelectorAll('.tilt').forEach(function (card) {
      var glare = document.createElement('div');
      glare.className = 'card__glare';
      card.appendChild(glare);
      card.addEventListener('mousemove', function (e) {
        var r = card.getBoundingClientRect();
        var px = (e.clientX - r.left) / r.width;
        var py = (e.clientY - r.top) / r.height;
        card.style.transform = 'perspective(800px) rotateX('
          + ((0.5 - py) * 8).toFixed(2) + 'deg) rotateY('
          + ((px - 0.5) * 10).toFixed(2) + 'deg) translateY(-4px)';
        glare.style.setProperty('--mx', (px * 100).toFixed(1) + '%');
        glare.style.setProperty('--my', (py * 100).toFixed(1) + '%');
      });
      card.addEventListener('mouseleave', function () {
        card.style.transform = '';
      });
    });
  }

  /* ---------------- reveal on scroll ---------------- */
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          en.target.classList.add('in');
          io.unobserve(en.target);
        }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('.card, .section__head, .note-box')
      .forEach(function (el) { el.classList.add('reveal'); io.observe(el); });
  }
})();
