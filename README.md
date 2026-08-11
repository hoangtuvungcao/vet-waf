![Vet-WAF](logo.png)

# Vet-WAF

**Website / docs:** https://hoangtuvungcao.github.io/vet-waf/ ·
**Source:** https://github.com/hoangtuvungcao/vet-waf ·
**License:** [GPLv2](LICENSE)

**Vet-WAF** is an all-in-one, open-source edge for high-performance web content
delivery and advanced protection against DDoS and web attacks. It is a drop-in
replacement for a whole web-server frontend: an HTTPS load balancer, a web
accelerator, a DDoS-mitigation system, and a web application firewall (WAF) —
all running as **Linux kernel modules**, inside the TCP/IP stack.

Because it lives in kernel space, Vet-WAF serves up to **1.8M HTTP requests/sec**
on cheap hardware (≈ **3× faster** than Nginx or HAProxy), and terminates TLS
[**40–80% faster** than Nginx/OpenSSL with up to 4× lower latency](https://netdevconf.info/0x14/session.html?talk-performance-study-of-kernel-TLS-handshakes).

---

## Features

**Delivery & performance**
- Kernel-space HTTP/1.1 and **HTTP/2** reverse proxy — no socket-API or
  kernel-bypass overhead.
- In-kernel **TLS 1.2/1.3 termination** on the fast path.
- Upstream **connection pooling** (persistent, reused origin connections) that
  absorbs connection churn so the origin sees a small, steady set of sockets.
- Optional **web cache** / accelerator for cacheable responses (disabled by
  default for dynamic, session-bearing origins).
- **Load balancing, active health checks, and automatic failover** across a
  server group.

**Protection (Frang, per-client-IP, in kernel space)**
- L7 **request-rate / burst** limiting and **connection-flood** limiting.
- **TLS handshake-flood** limiting, including never-completed handshakes.
- **Slowloris / slow-drip** defense via header/body timeouts and chunk counts.
- **Malformed / oversized request** rejection (header count & length, URI
  length, body length; HTTP/1 and HPACK alike).
- **Strict host checking** — kills host confusion, cache poisoning, and request
  smuggling; bare-IP `Host` values are rejected.
- **Method allow-listing** and method-override / trailer-split denial.
- **Scanner / brute-force ejection**: ban an IP that produces too many error
  responses in a window.
- Optional **User-Agent / signature** blocking via regex rules
  ([`etc/ua_block_rules.conf`](etc/ua_block_rules.conf)).
- Silent **drop** of confirmed attacks (denies attackers tuning feedback) while
  honest client errors still get a polite reply.

**Integration**
- [Seamless integration](https://hoangtuvungcao.github.io/vet-waf/configuration.html)
  with Linux **iptables / nftables** (e.g. an nftables fwmark drives the
  `:80 → :443` redirect).
- Sits cleanly **behind Cloudflare** (Full mode) or directly at the edge.

## How it works

Vet-WAF is built into the Linux TCP/IP stack for better, more stable
performance than TCP servers on top of the common Socket API — or even DPDK and
other kernel-bypass technologies. Kernel modifications are kept as small as
possible: the current [patch](linux-6.12.12.patch) against Linux **6.12.12** is
a few thousand lines.

At runtime the engine is five cooperating kernel modules, loaded in order:

```
tempesta_lib → tempesta_tls → tempesta_db → tempesta_regex → tempesta_fw
```

```
client ──▶ Cloudflare (optional) ──▶ :443  Vet-WAF edge  ──▶ origin
                                     (TLS terminate,          (never in DNS)
                                      Frang, cache, LB)
                          :80 ──▶ 301 redirect to :443
```

## Requirements

- A patched Linux kernel — **6.12.12-tfw** (build it with
  [`linux-6.12.12.patch`](linux-6.12.12.patch); see the
  [kernel-patching guide](https://hoangtuvungcao.github.io/vet-waf/kernel-patching.html)).
- x86-64 CPU with **AVX2 + BMI2 + ADX**.
- Kernel headers matching the patched kernel, plus a C toolchain (`make`, `gcc`).

## Quick install (from source)

```bash
# 1. Build & boot the patched kernel (one-time) — see the kernel-patching guide.
#    Then, from a checkout of this repo:

# 2. Build the five kernel modules against the running patched kernel.
make

# 3. Install a configuration and a TLS certificate.
sudo mkdir -p /etc/vet_waf/tls
sudo cp etc/vet_waf.prod.conf     /etc/vet_waf/vet_waf.conf
sudo cp etc/ua_block_rules.conf   /etc/vet_waf/ua_block_rules.conf
#    …and place your cert/key at /etc/vet_waf/tls/<domain>.{crt,key}

# 4. Load the engine.
sudo ./scripts/vet_waf.sh --start

# 5. Verify.
curl -kI https://localhost/
```

Full, copy-pasteable steps are in the
**[Quick-start guide](https://hoangtuvungcao.github.io/vet-waf/quickstart.html)**.
For a production, two-node edge cluster (staging, cutover, rollback), see the
tooling under [`scripts/cluster/`](scripts/cluster/) and
[`etc/vet_waf.prod.conf`](etc/vet_waf.prod.conf) — a fully commented production
profile you can adapt.

## Configuration

Configuration lives in `/etc/vet_waf/vet_waf.conf`. The annotated production
profile in [`etc/vet_waf.prod.conf`](etc/vet_waf.prod.conf) is the best starting
point; it covers listeners & TLS, Frang limits, caching, the backend server
group with health checks, and the routing `http_chain`. The
**[Configuration guide](https://hoangtuvungcao.github.io/vet-waf/configuration.html)**
and **[Frang rules guide](https://hoangtuvungcao.github.io/vet-waf/frang.html)**
explain every directive.

## Documentation

The complete documentation site is published from [`docs/`](docs/) at
**https://hoangtuvungcao.github.io/vet-waf/**:

| Guide | What it covers |
|-------|----------------|
| [Quick start](https://hoangtuvungcao.github.io/vet-waf/quickstart.html) | Requirements, build, configure, start, verify |
| [Kernel patching](https://hoangtuvungcao.github.io/vet-waf/kernel-patching.html) | Applying the 6.12.12 patch, building & booting the kernel |
| [Configuration](https://hoangtuvungcao.github.io/vet-waf/configuration.html) | Listeners, TLS, backends, vhosts, routing, cache |
| [Frang rules](https://hoangtuvungcao.github.io/vet-waf/frang.html) | Anti-DDoS / WAF limits and how to verify them |
| [Troubleshooting](https://hoangtuvungcao.github.io/vet-waf/troubleshooting.html) | Won't start, blocked users, backend & performance issues |

## Repository layout

| Path | Contents |
|------|----------|
| [`fw/`](fw/) | Core firewall / HTTP engine (`tempesta_fw`) |
| [`tls/`](tls/) | Kernel-space TLS (`tempesta_tls`) |
| [`db/`](db/) | In-kernel database (`tempesta_db`) |
| [`regex/`](regex/) | Regex engine (`tempesta_regex`) |
| [`lib/`](lib/) | Shared kernel library (`tempesta_lib`) |
| [`etc/`](etc/) | Configuration profiles & rule sets |
| [`scripts/`](scripts/) | Build, run, deploy & cluster tooling |
| [`pkg/`](pkg/) | Debian packaging |
| [`docs/`](docs/) | Documentation website (GitHub Pages) |
| [`linux-6.12.12.patch`](linux-6.12.12.patch) | The kernel patch |

## Current state

Beta. The **master** branch is a development branch for contributors and early
testers. Build from [source](https://hoangtuvungcao.github.io/vet-waf/quickstart.html)
or from the Debian packaging under [`pkg/`](pkg/).

## Support

Questions, bug reports, and feature requests: open an issue on
[GitHub](https://github.com/hoangtuvungcao/vet-waf/issues), or email
**trong20843@gmail.com**. If Vet-WAF is useful to you, donations are welcome via
PayPal to **chosandaccap@gmail.com** — thank you.

## Contribute

Contributions are welcome. Please match the existing kernel-C and configuration
style (`CodingStyle`), keep kernel modifications minimal, and open a pull request
against `master`.

## License

Vet-WAF is licensed in full under the **GNU General Public License, version 2**
— see [LICENSE](LICENSE). This covers the kernel engine, the configuration, the
tooling, **and** the documentation website under `docs/`.

Vet-WAF is a derived work of [Tempesta FW](https://github.com/tempesta-tech/tempesta),
Copyright (C) 2012-2024 Tempesta Technologies, Inc., distributed under GPLv2. The
copyleft terms carry over to this fork, so every part of the project stays GPLv2.
