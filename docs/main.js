// Vet-WAF site — i18n (EN/VI), 3D tilt, nav toggle, copy button, reveal-on-scroll
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  /* ---------------- i18n dictionary ---------------- */
  var I18N = {
    en: {
      'meta.description': 'Vet-WAF is an open-source, kernel-level hybrid of a web accelerator and a multi-layer firewall: an HTTPS load balancer, DDoS mitigation system, and web application firewall built into the Linux TCP/IP stack.',
      'nav.features': 'Features', 'nav.security': 'Security', 'nav.performance': 'Performance',
      'nav.deploy': 'Deploy', 'nav.quickstart': 'Quick start', 'nav.support': 'Support', 'nav.wiki': 'Wiki',
      'nav.docs': 'Docs',
      'docs.title': 'Documentation',
      'docs.sub': 'Five guides, in the order you will need them — from a first build to tuning a live edge node under attack.',
      'docs.d1t': 'Quick start', 'docs.d1s': 'Build, configure, and verify Vet-WAF is passing live traffic.',
      'docs.d2t': 'Kernel patching', 'docs.d2s': 'Patch, build, and boot Linux 6.12.12 — with a safe recovery path.',
      'docs.d3t': 'Frang rules', 'docs.d3s': 'Every anti-DDoS directive: floods, slowloris, malformed HTTP, scanners.',
      'docs.d4t': 'Configuration', 'docs.d4s': 'Full reference: listeners, TLS, backends, failover, routing, cache.',
      'docs.d5t': 'Troubleshooting', 'docs.d5s': 'Map each symptom to its cause — and read dmesg first.',
      'hero.badge': 'Open-source · GPLv2 · Linux kernel module',
      'hero.title1': 'The kernel-level', 'hero.title2': 'web firewall & accelerator',
      'hero.lead': '<strong>Vet-WAF</strong> is an all-in-one, high-performance solution for web content delivery and advanced protection against DDoS and web attacks — a drop-in replacement for your whole frontend: HTTPS load balancer, web accelerator, DDoS mitigation, and WAF, built directly into the Linux TCP/IP stack.',
      'hero.cta1': 'Get started', 'hero.cta2': 'View on GitHub',
      'hero.stat1': 'HTTP req/s', 'hero.stat2': 'faster than Nginx/HAProxy',
      'hero.stat3': 'lower TLS latency', 'hero.stat4': 'multi-layer defense',
      'features.title': 'One engine, the whole frontend',
      'features.sub': 'Vet-WAF fuses a web accelerator and a multi-layer firewall into a single kernel-space core — no context switches, no user-space copy overhead.',
      'feat.waf.h': 'Web Application Firewall',
      'feat.waf.p': 'Inspect and filter HTTP/HTTPS at wire speed. Block injections, bad bots, and abusive clients with rule-based and rate-limiting policies (Frang).',
      'feat.lb.h': 'HTTPS Load Balancer',
      'feat.lb.p': 'Terminate TLS and balance traffic across upstreams with hash, ratio, and predictive schedulers — all inside the kernel data path.',
      'feat.acc.h': 'Web Accelerator',
      'feat.acc.p': 'A built-in, RAM-resident HTTP cache serves hot content in microseconds and shields origins from load spikes.',
      'feat.ddos.h': 'DDoS Mitigation',
      'feat.ddos.p': 'Absorb volumetric and application-layer floods early in the stack, with seamless integration into Linux iptables / nftables.',
      'feat.tls.h': 'Kernel-native TLS',
      'feat.tls.p': 'Vet-WAF TLS runs the handshake in-kernel — 40–80% faster than Nginx/OpenSSL, with optional constant-time crypto.',
      'feat.obs.h': 'Observability',
      'feat.obs.p': 'Structured access logging to ClickHouse, live perfstat via procfs, and APM-grade latency percentiles out of the box.',
      'sec.title': 'Defense in depth, from L3 to L7',
      'sec.sub': 'Vet-WAF blocks attacks at the earliest possible point in the stack. The Frang module enforces rate and structural limits per client before a request ever reaches your origin.',
      'sec.rate.h': 'Rate & connection limits',
      'sec.rate.p': 'Per-client caps on request rate/burst, TCP connection rate/burst, and concurrent connections stop floods and slow-loris attacks cold.',
      'sec.struct.h': 'Structural request validation',
      'sec.struct.p': 'Bound header count, header length, body length and URI length; restrict HTTP methods and allowed character sets to shrink the attack surface.',
      'sec.js.h': 'JavaScript challenge',
      'sec.js.p': 'A sticky-cookie JS challenge separates real browsers from bots without a third-party captcha — fully self-hosted in the kernel.',
      'sec.drop.h': 'Early drop & blocklists',
      'sec.drop.p': 'Malicious clients are dropped (not just refused), and IP/JA5 fingerprint rules integrate with iptables/nftables for volumetric defense.',
      'sec.note': 'Anti-DDoS tip: the shipped config is secure-by-default. Tune the Frang limits to your real traffic — start strict, then relax only what your legitimate clients need.',
      'perf.title': 'Built for the fast path',
      'perf.sub': 'Because Vet-WAF lives inside the Linux TCP/IP stack, it avoids the socket-API and kernel-bypass overhead that caps traditional proxies.',
      'perf.p1': '<b>Zero-copy data path.</b> Requests are parsed and routed without leaving kernel space.',
      'perf.p2': '<b>Small kernel footprint.</b> The patch is only a few thousand lines against the Linux tree.',
      'perf.p3': '<b>SIMD everywhere.</b> AVX2-accelerated HTTP parsing, hashing, and string ops.',
      'perf.p4': '<b>Predictable latency.</b> No GC, no user/kernel round-trips on the hot path.',
      'arch.title': 'How it works',
      'arch.sub': 'Vet-WAF is a set of loosely-coupled Linux kernel modules that sit between the NIC and your origin servers.',
      'arch.clients': 'Clients', 'arch.core': 'WAF · LB · Cache · TLS · DDoS — in kernel',
      'arch.upstreams': 'Upstreams', 'arch.origin': 'your app / origin servers',
      'arch.note': 'Module names keep the upstream kernel-ABI identifiers for binary compatibility with the patched Linux image.',
      'qs.title': 'Quick start',
      'qs.sub': 'Build from source against a Vet-WAF-patched Linux 6.12.12 kernel, then start the service.',
      'qs.hint': 'A minimal config lives in <code>etc/vet_waf.conf</code>. The systemd unit is <code>vet-waf.service</code>. Vet-WAF needs the patched kernel from <code>linux-6.12.12.patch</code> — see the deploy guide below.',
      'code.copy': 'Copy',
      'dep.title': 'Deploy guide: reverse-proxy in front of a backend',
      'dep.sub': 'Put Vet-WAF on your edge server and proxy protected traffic to your origin. Follow the steps in order — the kernel step is mandatory.',
      'dep.s1.h': 'Install the patched kernel',
      'dep.s1.p': 'Vet-WAF is a kernel module and requires the patched <b>Linux 6.12.12</b>. Build it with <code>make bindeb-pkg LOCALVERSION=-tfw</code>, or use <code>make modules_install && make install</code>. <b>Reboot into the new kernel</b> before continuing.',
      'dep.s2.h': 'Point Vet-WAF at your backend',
      'dep.s2.p': 'In <code>/etc/vet_waf/vet_waf.conf</code>, set <code>server &lt;backend-ip&gt;:80;</code> inside the <code>srv_group</code>. The shipped config uses <code>https://example.com/</code> as a placeholder — replace it with your origin.',
      'dep.s3.h': 'Free the ports & start the service',
      'dep.s3.p': 'Stop any existing proxy holding <code>:80/:443</code>, then <code>systemctl enable --now vet-waf</code>. Verify with <code>curl -I http://your-edge-ip/</code> and <code>cat /proc/vet_waf/perfstat</code>.',
      'dep.pitfalls.h': "Pitfalls we hit (so you don't have to)",
      'dep.pit1': '<b>Stock kernels won\'t load the module.</b> A default Ubuntu 5.15 kernel is missing the Vet-WAF patch — you must build and boot 6.12.12-tfw first.',
      'dep.pit2': '<b><code>bindeb-pkg</code> needs <code>debhelper</code>.</b> If packaging fails with <code>Unmet build dependencies: debhelper-compat</code>, install <code>debhelper</code> or fall back to <code>make modules_install && make install</code>.',
      'dep.pit3': '<b>Port already in use.</b> Another WAF/proxy on <code>:80</code> blocks startup — stop and disable it before enabling <code>vet-waf</code>.',
      'dep.pit4': '<b>Disable module signing.</b> Turn off <code>MODULE_SIG</code>, <code>SYSTEM_TRUSTED_KEYS</code> and <code>DEBUG_INFO_BTF</code> in the kernel config, or the out-of-tree build fails.',
      'nav.cluster': 'Cluster',
      'clu.title': 'Two-node cluster: synchronised policy & automatic ejection',
      'clu.sub': 'Run Vet-WAF on two edge nodes behind one hostname. Policy is replicated from a single author, each node watches the other, and a node that stops protecting traffic is taken out of rotation automatically. The tooling lives in <code>scripts/cluster/</code>.',
      'clu.c1.h': 'Author &amp; replica, not peer-to-peer',
      'clu.c1.p': 'One node authors policy; the other pulls. <code>waf-sync.sh</code> refuses to push from a replica, because two writable copies is exactly how split-brain rulesets happen. Every change is a git commit in <code>/etc/vet_waf/cluster</code> — <code>git log</code> is the audit trail and <code>git revert</code> is the rollback. rsync is the fallback transport.',
      'clu.c2.h': 'Validated before it reaches either node',
      'clu.c2.p': 'The validator mirrors the kernel\'s own rule grammar from <code>fw/http_tbl.c</code>: the match field must be one of <code>uri</code>, <code>host</code>, <code>hdr</code>, <code>mark</code>, <code>method</code>, <code>cookie</code>, and every rule must terminate. A ruleset that the kernel would reject is stopped before the push, not after — including a bare default rule, which would silently shadow everything below it.',
      'clu.c3.h': 'Health checks that catch a useless node',
      'clu.c3.p': 'A TCP check only proves the socket answers. <code>waf-health.sh</code> additionally requires <code>state=start</code>, live origin connections in <code>/proc/vet_waf/perfstat</code>, and a real proxied request. haproxy runs it as an <code>agent-check</code> alongside the HTTP check and ejects after 3 consecutive failures, readmitting only after 2 successes.',
      'clu.c4.h': 'Management ports the peer can reach, and nobody else',
      'clu.c4.p': '<code>waf-firewall.sh</code> leaves <code>80/443</code> public and restricts <code>22</code>, <code>8081</code> and <code>8404</code> to the peer plus any admin addresses you name. <code>--apply</code> arms a timed rollback so a mistake on a remote VPS cannot lock you out; <code>--commit</code> keeps the ruleset once you have confirmed you still have access.',
      'clu.tradeoff.h': 'The tradeoff, stated plainly',
      'clu.t1': '<b>haproxy and Vet-WAF cannot share port 80.</b> The fronting layout puts haproxy on <code>:80/:443</code> and moves Vet-WAF to <code>:8080</code>, so requests cross a user-space proxy before reaching the kernel-space WAF. That gives back part of the performance that makes Vet-WAF worth running.',
      'clu.t2': '<b>Take this layout for automatic ejection.</b> If you want the throughput instead, run Vet-WAF directly on <code>:80</code> on both nodes, publish both A records, and withdraw the record of a failed node at the DNS layer.',
      'clu.t3': '<b>Source addresses are not an <code>http_chain</code> field.</b> There is no <code>ip ==</code> match. Blacklisted sources are tagged in nftables and matched in policy as <code>mark == 16</code>; <code>waf-firewall.sh --blockip</code> manages that set for you.',
      'clu.t4': '<b>Policy is three fixed files, not a directory.</b> <code>!include</code> expands with <code>find</code>, which returns directory order, and <code>http_chain</code> is first-match-wins — a rule directory can evaluate differently on each node while looking identical.',
      'cfg.title': 'Simple, secure-by-default config',
      'cfg.sub': 'A newcomer-friendly starting point: one listener, one backend, hardened Frang limits. Everything else is optional.',
      'cfg.hint': 'Full reference lives in the <a href="https://github.com/hoangtuvungcao/vet-waf/wiki" target="_blank" rel="noopener">project wiki</a>. Start strict and relax only what your real clients need.',
      'sup.title': 'Support & contact',
      'sup.sub': 'Vet-WAF is free and open-source. If it helps you, a donation keeps development going.',
      'sup.contact.h': 'Contact', 'sup.contact.p': 'Questions, bugs, or security reports:',
      'sup.donate.h': 'Donate', 'sup.donate.p': 'Support Vet-WAF via PayPal:',
      'cta.title': 'Ready to put the firewall in the kernel?',
      'cta.sub': 'Star the project, read the source, and build your own high-performance secure frontend.',
      'cta.btn1': 'Star on GitHub', 'cta.btn2': 'Read the quick start',
      'footer.legal': 'Vet-WAF is free software licensed under <b>GPLv2</b> — engine, tooling, and this website — derived from Tempesta FW. © 2026 Vet-WAF.'
    },
    vi: {
      'meta.description': 'Vet-WAF là giải pháp mã nguồn mở cấp nhân (kernel) kết hợp trình tăng tốc web và tường lửa đa lớp: bộ cân bằng tải HTTPS, hệ thống chống DDoS và tường lửa ứng dụng web, tích hợp thẳng vào ngăn xếp TCP/IP của Linux.',
      'nav.features': 'Tính năng', 'nav.security': 'Bảo mật', 'nav.performance': 'Hiệu năng',
      'nav.deploy': 'Triển khai', 'nav.quickstart': 'Bắt đầu', 'nav.support': 'Hỗ trợ', 'nav.wiki': 'Wiki',
      'nav.docs': 'Tài liệu',
      'docs.title': 'Tài liệu hướng dẫn',
      'docs.sub': 'Năm hướng dẫn, xếp theo đúng thứ tự bạn sẽ cần — từ lần biên dịch đầu tiên đến việc tinh chỉnh một node biên đang bị tấn công.',
      'docs.d1t': 'Bắt đầu nhanh', 'docs.d1s': 'Biên dịch, cấu hình và kiểm chứng Vet-WAF đang xử lý lưu lượng thật.',
      'docs.d2t': 'Vá nhân Linux', 'docs.d2s': 'Vá, biên dịch và khởi động Linux 6.12.12 — kèm đường lui an toàn.',
      'docs.d3t': 'Luật Frang', 'docs.d3s': 'Toàn bộ chỉ thị chống DDoS: lũ request, slowloris, HTTP méo dạng, máy quét.',
      'docs.d4t': 'Cấu hình', 'docs.d4s': 'Tra cứu đầy đủ: cổng lắng nghe, TLS, backend, dự phòng, định tuyến, bộ đệm.',
      'docs.d5t': 'Xử lý sự cố', 'docs.d5s': 'Ánh xạ từng triệu chứng tới nguyên nhân — và hãy đọc dmesg trước tiên.',
      'hero.badge': 'Mã nguồn mở · GPLv2 · Mô-đun nhân Linux',
      'hero.title1': 'Tường lửa & tăng tốc web', 'hero.title2': 'ngay trong nhân Linux',
      'hero.lead': '<strong>Vet-WAF</strong> là giải pháp hiệu năng cao, tất-cả-trong-một để phân phối nội dung web và bảo vệ nâng cao trước tấn công DDoS và tấn công web — thay thế trọn bộ frontend của bạn: cân bằng tải HTTPS, tăng tốc web, chống DDoS và WAF, tích hợp thẳng vào ngăn xếp TCP/IP của Linux.',
      'hero.cta1': 'Bắt đầu', 'hero.cta2': 'Xem trên GitHub',
      'hero.stat1': 'yêu cầu HTTP/giây', 'hero.stat2': 'nhanh hơn Nginx/HAProxy',
      'hero.stat3': 'độ trễ TLS thấp hơn', 'hero.stat4': 'phòng thủ đa lớp',
      'features.title': 'Một engine, trọn bộ frontend',
      'features.sub': 'Vet-WAF hợp nhất trình tăng tốc web và tường lửa đa lớp vào một lõi duy nhất trong không gian nhân — không chuyển ngữ cảnh, không tốn chi phí sao chép ở không gian người dùng.',
      'feat.waf.h': 'Tường lửa ứng dụng web (WAF)',
      'feat.waf.p': 'Kiểm tra và lọc HTTP/HTTPS ở tốc độ đường truyền. Chặn tấn công tiêm nhiễm, bot xấu và client lạm dụng bằng chính sách theo luật và giới hạn tần suất (Frang).',
      'feat.lb.h': 'Cân bằng tải HTTPS',
      'feat.lb.p': 'Kết thúc TLS và cân bằng lưu lượng tới các máy chủ đích bằng bộ lập lịch hash, tỉ lệ và dự đoán — tất cả ngay trong đường dữ liệu của nhân.',
      'feat.acc.h': 'Tăng tốc web',
      'feat.acc.p': 'Bộ đệm HTTP thường trú trong RAM phục vụ nội dung nóng trong vài micro giây và che chắn máy chủ gốc khỏi các đợt tải đột biến.',
      'feat.ddos.h': 'Chống DDoS',
      'feat.ddos.p': 'Hấp thụ các đợt lũ tấn công thể tích và tầng ứng dụng ngay từ sớm trong ngăn xếp, tích hợp liền mạch với iptables / nftables của Linux.',
      'feat.tls.h': 'TLS cấp nhân',
      'feat.tls.p': 'TLS của Vet-WAF thực hiện bắt tay ngay trong nhân — nhanh hơn Nginx/OpenSSL 40–80%, tùy chọn mã hóa thời gian hằng.',
      'feat.obs.h': 'Khả năng quan sát',
      'feat.obs.p': 'Ghi log truy cập có cấu trúc vào ClickHouse, perfstat trực tiếp qua procfs, và phân vị độ trễ cấp APM có sẵn ngay từ đầu.',
      'sec.title': 'Phòng thủ theo chiều sâu, từ L3 đến L7',
      'sec.sub': 'Vet-WAF chặn tấn công tại điểm sớm nhất có thể trong ngăn xếp. Mô-đun Frang áp đặt giới hạn tần suất và cấu trúc cho từng client trước khi yêu cầu chạm tới máy chủ gốc.',
      'sec.rate.h': 'Giới hạn tần suất & kết nối',
      'sec.rate.p': 'Giới hạn theo từng client về tần suất/đợt bùng yêu cầu, tần suất/đợt bùng kết nối TCP và số kết nối đồng thời — chặn đứng tấn công lũ và slow-loris.',
      'sec.struct.h': 'Kiểm tra cấu trúc yêu cầu',
      'sec.struct.p': 'Giới hạn số header, độ dài header, độ dài thân và độ dài URI; hạn chế phương thức HTTP và bộ ký tự cho phép để thu hẹp bề mặt tấn công.',
      'sec.js.h': 'Thử thách JavaScript',
      'sec.js.p': 'Thử thách JS bằng cookie cố định phân biệt trình duyệt thật với bot mà không cần captcha bên thứ ba — tự lưu trữ hoàn toàn trong nhân.',
      'sec.drop.h': 'Loại bỏ sớm & danh sách chặn',
      'sec.drop.p': 'Client độc hại bị loại bỏ (không chỉ từ chối), và luật theo IP/dấu vân tay JA5 tích hợp với iptables/nftables để phòng thủ thể tích.',
      'sec.note': 'Mẹo chống DDoS: cấu hình đi kèm đã bảo mật mặc định. Hãy tinh chỉnh giới hạn Frang theo lưu lượng thật — bắt đầu chặt chẽ, rồi chỉ nới lỏng những gì client hợp lệ cần.',
      'perf.title': 'Thiết kế cho đường đi nhanh',
      'perf.sub': 'Vì Vet-WAF nằm bên trong ngăn xếp TCP/IP của Linux, nó tránh được chi phí socket-API và kernel-bypass vốn giới hạn các proxy truyền thống.',
      'perf.p1': '<b>Đường dữ liệu không sao chép.</b> Yêu cầu được phân tích và định tuyến mà không rời khỏi không gian nhân.',
      'perf.p2': '<b>Dấu chân nhân nhỏ gọn.</b> Bản vá chỉ vài nghìn dòng so với cây mã nguồn Linux.',
      'perf.p3': '<b>SIMD ở khắp nơi.</b> Phân tích HTTP, băm và xử lý chuỗi tăng tốc bằng AVX2.',
      'perf.p4': '<b>Độ trễ ổn định.</b> Không GC, không vòng lặp qua lại user/kernel trên đường đi nóng.',
      'arch.title': 'Cách hoạt động',
      'arch.sub': 'Vet-WAF là tập hợp các mô-đun nhân Linux ghép lỏng, nằm giữa card mạng và máy chủ gốc của bạn.',
      'arch.clients': 'Client', 'arch.core': 'WAF · LB · Cache · TLS · DDoS — trong nhân',
      'arch.upstreams': 'Máy chủ đích', 'arch.origin': 'ứng dụng / máy chủ gốc của bạn',
      'arch.note': 'Tên mô-đun giữ nguyên định danh ABI nhân của thượng nguồn để tương thích nhị phân với ảnh Linux đã vá.',
      'qs.title': 'Bắt đầu nhanh',
      'qs.sub': 'Biên dịch từ mã nguồn với nhân Linux 6.12.12 đã vá Vet-WAF, rồi khởi động dịch vụ.',
      'qs.hint': 'Cấu hình tối thiểu nằm ở <code>etc/vet_waf.conf</code>. Đơn vị systemd là <code>vet-waf.service</code>. Vet-WAF cần nhân đã vá từ <code>linux-6.12.12.patch</code> — xem hướng dẫn triển khai bên dưới.',
      'code.copy': 'Chép',
      'dep.title': 'Hướng dẫn triển khai: reverse-proxy trước một backend',
      'dep.sub': 'Đặt Vet-WAF trên máy chủ biên và chuyển tiếp lưu lượng đã bảo vệ tới máy chủ gốc. Làm theo thứ tự — bước cài nhân là bắt buộc.',
      'dep.s1.h': 'Cài nhân đã vá',
      'dep.s1.p': 'Vet-WAF là mô-đun nhân và cần <b>Linux 6.12.12</b> đã vá. Biên dịch bằng <code>make bindeb-pkg LOCALVERSION=-tfw</code>, hoặc dùng <code>make modules_install && make install</code>. <b>Khởi động lại vào nhân mới</b> trước khi tiếp tục.',
      'dep.s2.h': 'Trỏ Vet-WAF tới backend của bạn',
      'dep.s2.p': 'Trong <code>/etc/vet_waf/vet_waf.conf</code>, đặt <code>server &lt;ip-backend&gt;:80;</code> bên trong <code>srv_group</code>. Cấu hình đi kèm dùng <code>https://example.com/</code> làm placeholder — hãy thay bằng máy chủ gốc của bạn.',
      'dep.s3.h': 'Giải phóng cổng & khởi động dịch vụ',
      'dep.s3.p': 'Dừng mọi proxy đang giữ <code>:80/:443</code>, rồi <code>systemctl enable --now vet-waf</code>. Kiểm tra bằng <code>curl -I http://ip-bien-cua-ban/</code> và <code>cat /proc/vet_waf/perfstat</code>.',
      'dep.pitfalls.h': 'Những vướng mắc chúng tôi gặp (để bạn khỏi gặp)',
      'dep.pit1': '<b>Nhân gốc không nạp được mô-đun.</b> Nhân Ubuntu 5.15 mặc định thiếu bản vá Vet-WAF — bạn phải biên dịch và khởi động vào 6.12.12-tfw trước.',
      'dep.pit2': '<b><code>bindeb-pkg</code> cần <code>debhelper</code>.</b> Nếu đóng gói lỗi <code>Unmet build dependencies: debhelper-compat</code>, hãy cài <code>debhelper</code> hoặc dùng <code>make modules_install && make install</code>.',
      'dep.pit3': '<b>Cổng đang bị chiếm.</b> Một WAF/proxy khác trên <code>:80</code> chặn việc khởi động — hãy dừng và vô hiệu hóa nó trước khi bật <code>vet-waf</code>.',
      'dep.pit4': '<b>Tắt ký mô-đun.</b> Tắt <code>MODULE_SIG</code>, <code>SYSTEM_TRUSTED_KEYS</code> và <code>DEBUG_INFO_BTF</code> trong cấu hình nhân, nếu không bản dựng ngoài cây sẽ lỗi.',
      'nav.cluster': 'Cụm 2 node',
      'clu.title': 'Cụm hai node: đồng bộ chính sách & tự động loại node lỗi',
      'clu.sub': 'Chạy Vet-WAF trên hai node biên sau cùng một tên miền. Chính sách được sao chép từ một node chủ duy nhất, mỗi node giám sát node kia, và node nào ngừng bảo vệ lưu lượng sẽ tự động bị loại khỏi vòng phục vụ. Bộ công cụ nằm trong <code>scripts/cluster/</code>.',
      'clu.c1.h': 'Node chủ &amp; node sao chép, không phải ngang hàng',
      'clu.c1.p': 'Một node soạn chính sách; node kia kéo về. <code>waf-sync.sh</code> từ chối đẩy từ node sao chép, vì hai bản đều ghi được chính là cách sinh ra split-brain. Mỗi thay đổi là một commit git trong <code>/etc/vet_waf/cluster</code> — <code>git log</code> là nhật ký kiểm toán và <code>git revert</code> là đường lùi. rsync là kênh truyền dự phòng.',
      'clu.c2.h': 'Kiểm tra hợp lệ trước khi tới bất kỳ node nào',
      'clu.c2.p': 'Bộ kiểm tra phản chiếu đúng ngữ pháp luật của nhân trong <code>fw/http_tbl.c</code>: trường so khớp phải là một trong <code>uri</code>, <code>host</code>, <code>hdr</code>, <code>mark</code>, <code>method</code>, <code>cookie</code>, và mỗi luật phải kết thúc bằng dấu chấm phẩy. Bộ luật mà nhân sẽ từ chối bị chặn lại trước khi đẩy đi, chứ không phải sau — kể cả luật mặc định trống, thứ sẽ âm thầm che khuất mọi luật bên dưới.',
      'clu.c3.h': 'Health check bắt được node còn sống nhưng vô dụng',
      'clu.c3.p': 'Kiểm tra TCP chỉ chứng minh socket có trả lời. <code>waf-health.sh</code> còn đòi hỏi <code>state=start</code>, có kết nối tới máy chủ gốc trong <code>/proc/vet_waf/perfstat</code>, và một request thật đi qua proxy. haproxy chạy nó dưới dạng <code>agent-check</code> song song với kiểm tra HTTP, loại node sau 3 lần lỗi liên tiếp và chỉ nhận lại sau 2 lần thành công.',
      'clu.c4.h': 'Cổng quản trị chỉ node kia truy cập được',
      'clu.c4.p': '<code>waf-firewall.sh</code> để <code>80/443</code> công khai và giới hạn <code>22</code>, <code>8081</code>, <code>8404</code> cho node kia cùng các địa chỉ quản trị bạn khai báo. <code>--apply</code> hẹn giờ tự khôi phục để một sai sót trên VPS từ xa không khóa bạn ở ngoài; <code>--commit</code> giữ lại bộ luật sau khi bạn xác nhận vẫn vào được.',
      'clu.tradeoff.h': 'Cái giá phải trả, nói thẳng',
      'clu.t1': '<b>haproxy và Vet-WAF không thể cùng giữ cổng 80.</b> Bố cục đặt haproxy ở <code>:80/:443</code> và chuyển Vet-WAF sang <code>:8080</code>, nên request phải đi qua một proxy không gian người dùng trước khi tới WAF trong nhân. Điều đó trả lại một phần hiệu năng vốn là lý do dùng Vet-WAF.',
      'clu.t2': '<b>Chọn bố cục này khi bạn cần tự động loại node.</b> Nếu ưu tiên thông lượng, hãy chạy Vet-WAF trực tiếp trên <code>:80</code> ở cả hai node, công bố cả hai bản ghi A, và rút bản ghi của node hỏng ở tầng DNS.',
      'clu.t3': '<b>Địa chỉ nguồn không phải là trường của <code>http_chain</code>.</b> Không có phép so khớp <code>ip ==</code>. Nguồn bị chặn được gắn thẻ trong nftables rồi khớp trong chính sách bằng <code>mark == 16</code>; <code>waf-firewall.sh --blockip</code> quản lý tập đó giúp bạn.',
      'clu.t4': '<b>Chính sách là ba tệp cố định, không phải một thư mục.</b> <code>!include</code> được khai triển bằng <code>find</code>, vốn trả về thứ tự thư mục, còn <code>http_chain</code> lấy luật khớp đầu tiên — một thư mục luật có thể chạy khác nhau trên mỗi node dù trông y hệt.',
      'cfg.title': 'Cấu hình đơn giản, bảo mật mặc định',
      'cfg.sub': 'Điểm khởi đầu thân thiện cho người mới: một listener, một backend, giới hạn Frang đã tăng cường. Mọi thứ khác đều tùy chọn.',
      'cfg.hint': 'Tài liệu tham khảo đầy đủ nằm ở <a href="https://github.com/hoangtuvungcao/vet-waf/wiki" target="_blank" rel="noopener">wiki dự án</a>. Bắt đầu chặt chẽ và chỉ nới lỏng những gì client thật của bạn cần.',
      'sup.title': 'Hỗ trợ & liên hệ',
      'sup.sub': 'Vet-WAF miễn phí và mã nguồn mở. Nếu nó hữu ích, một khoản đóng góp sẽ giúp việc phát triển tiếp tục.',
      'sup.contact.h': 'Liên hệ', 'sup.contact.p': 'Câu hỏi, lỗi, hoặc báo cáo bảo mật:',
      'sup.donate.h': 'Ủng hộ', 'sup.donate.p': 'Ủng hộ Vet-WAF qua PayPal:',
      'cta.title': 'Sẵn sàng đưa tường lửa vào nhân?',
      'cta.sub': 'Gắn sao cho dự án, đọc mã nguồn, và tự dựng frontend bảo mật hiệu năng cao của riêng bạn.',
      'cta.btn1': 'Gắn sao trên GitHub', 'cta.btn2': 'Đọc hướng dẫn bắt đầu',
      'footer.legal': 'Vet-WAF là phần mềm tự do theo giấy phép <b>GPLv2</b> — engine, công cụ và cả website này — bắt nguồn từ Tempesta FW. © 2026 Vet-WAF.'
    }
  };

  /* ---------------- apply language ---------------- */
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
      b.setAttribute('aria-pressed', b.getAttribute('data-lang-set') === lang ? 'true' : 'false');
    });
    try { localStorage.setItem('vetwaf-lang', lang); } catch (e) {}
  }

  var saved = 'en';
  try { saved = localStorage.getItem('vetwaf-lang') || 'en'; } catch (e) {}
  applyLang(saved);

  document.querySelectorAll('[data-lang-set]').forEach(function (b) {
    b.addEventListener('click', function () { applyLang(b.getAttribute('data-lang-set')); });
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
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(fallback);
      } else { fallback(); }
      function fallback() {
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  });

  /* ---------------- 3D pointer tilt ---------------- */
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
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
        var rx = (0.5 - py) * 8;
        var ry = (px - 0.5) * 10;
        card.style.transform = 'perspective(800px) rotateX(' + rx.toFixed(2) + 'deg) rotateY(' + ry.toFixed(2) + 'deg) translateY(-4px)';
        glare.style.setProperty('--mx', (px * 100).toFixed(1) + '%');
        glare.style.setProperty('--my', (py * 100).toFixed(1) + '%');
      });
      card.addEventListener('mouseleave', function () { card.style.transform = ''; });
    });
  }

  /* ---------------- reveal on scroll ---------------- */
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('.card, .section__head, .stat, .node, .bar, .step, .note-box').forEach(function (el) {
      el.classList.add('reveal'); io.observe(el);
    });
  }
})();
