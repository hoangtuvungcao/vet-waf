<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Verifying your browser — Vet-WAF</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%237c6ffd' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M12 3l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z'/%3E%3Cpath d='M9.5 12l1.8 1.8L15 10'/%3E%3C/svg%3E">
<style>
  :root{color-scheme:dark}
  html,body{height:100%}
  body{margin:0;background:#0b1020;color:#e8ecf6;
    font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;
    display:flex;align-items:center;justify-content:center;text-align:center;padding:24px}
  .box{max-width:460px}
  .mark{width:64px;height:64px;margin:0 auto 22px;display:block;
    filter:drop-shadow(0 8px 20px rgba(124,111,253,.5))}
  .brand{font-weight:800;font-size:22px;letter-spacing:-.5px;margin-bottom:6px}
  .brand span{background:linear-gradient(120deg,#a78bfa,#38bdf8);
    -webkit-background-clip:text;background-clip:text;color:transparent}
  h2{font-size:18px;font-weight:600;margin:14px 0 6px;color:#e8ecf6}
  p{color:#9aa3bd;font-size:14.5px;margin:6px 0}
  .spin{width:34px;height:34px;margin:22px auto 0;border-radius:50%;
    border:3px solid rgba(124,111,253,.25);border-top-color:#7c6ffd;
    animation:spin 900ms linear infinite}
  @keyframes spin{to{transform:rotate(360deg)}}
  @media(prefers-reduced-motion:reduce){.spin{animation:none}}
</style>
</head>
<body>
  <div class="box">
    <svg class="mark" viewBox="0 0 24 24" fill="none" stroke="#7c6ffd" stroke-width="1.7"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M12 3l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/>
      <path d="M9.5 12l1.8 1.8L15 10"/>
    </svg>
    <div class="brand">Vet<span>-WAF</span></div>
    <h2>Verifying your browser, please wait a moment…</h2>
    <p>This automated check protects the site from bots and DDoS attacks.</p>
    <p>Please make sure your browser has JavaScript enabled.</p>
    <div class="spin" aria-hidden="true"></div>
    <p style="margin-top:20px;font-size:12.5px">
      Protected by
      <a href="https://hoangtuvungcao.github.io/vet-waf/" style="color:#8ec5ff;text-decoration:none">Vet-WAF</a>
    </p>
  </div>
  <script>[% INCLUDE js_challenge.js.tpl %]</script>
</body>
</html>
