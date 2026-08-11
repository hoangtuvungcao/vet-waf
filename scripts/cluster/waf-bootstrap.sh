#!/bin/bash
#
# Vet-WAF — one-shot node bootstrap: dependencies, tooling, centralised logs.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.  See LICENSE.
#
# Run on BOTH nodes. Idempotent: safe to re-run after a failure.
#
#   ./waf-bootstrap.sh --all              everything
#   ./waf-bootstrap.sh --deps             build + runtime dependencies only
#   ./waf-bootstrap.sh --logging          rsyslog + logrotate only
#   ./waf-bootstrap.sh --services         install systemd units only
#   ./waf-bootstrap.sh --verify           report what is and is not ready
#
# It does NOT patch or install the kernel, and does NOT start Vet-WAF. The
# kernel step needs a reboot and a decision about which kernel to boot, so it
# stays a deliberate manual action — see docs/kernel-patching.html.
#

set -uo pipefail

CLUSTER_ENV=${CLUSTER_ENV:-/etc/vet_waf/cluster.env}
[ -f "$CLUSTER_ENV" ] || CLUSTER_ENV="$(dirname "$0")/cluster.env"
# shellcheck disable=SC1090
. "$CLUSTER_ENV"

SRC_DIR=${WAF_SRC:-/root/vet-waf}
LOG_DIR=/var/log/vet-waf

log()  { echo -e "\033[0;32m[bootstrap]\033[0m $*"; }
warn() { echo -e "\033[0;33m[bootstrap]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[bootstrap]\033[0m $*" >&2; exit 1; }
step() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }

[ "$(id -u)" -eq 0 ] || die "must run as root"

detect_os()
{
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		OS_ID=$ID
		OS_VER=${VERSION_ID:-}
	else
		die "cannot detect the distribution (/etc/os-release missing)"
	fi
	case "$OS_ID" in
	debian|ubuntu) PKG=apt ;;
	centos|rhel|rocky|almalinux) PKG=dnf ;;
	*) die "unsupported distribution: $OS_ID" ;;
	esac
	log "$OS_ID $OS_VER (package manager: $PKG)"
}

# ---------------------------------------------------------------------------
do_deps()
{
	step "Dependencies"
	detect_os

	if [ "$PKG" = apt ]; then
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq || die "apt-get update failed"

		# Build toolchain for the kernel modules. libssl-dev, libelf-dev
		# and bison/flex are needed to build a kernel, not just a module,
		# because the Vet-WAF patch requires a full kernel build.
		apt-get install -y -qq \
			build-essential bc bison flex libssl-dev libelf-dev \
			libncurses-dev dwarves rsync git curl wget \
			pkg-config make gcc \
			"linux-headers-$(uname -r)" \
			|| warn "some build packages failed — check the kernel headers name"

		# Runtime and cluster tooling.
		apt-get install -y -qq \
			haproxy nftables socat jq net-tools iproute2 \
			rsyslog logrotate ca-certificates \
			|| die "runtime package install failed"

		# Language runtimes for the tooling and tests. python3 drives the
		# functional test suite; Go is only needed if you build the
		# optional load generators.
		apt-get install -y -qq \
			python3 python3-pip python3-venv \
			|| warn "python3 install incomplete"

		if ! command -v go >/dev/null 2>&1; then
			apt-get install -y -qq golang-go || warn "golang-go unavailable — skipping Go"
		fi
	else
		dnf install -y -q \
			gcc make bc bison flex openssl-devel elfutils-libelf-devel \
			ncurses-devel rsync git curl wget \
			"kernel-devel-$(uname -r)" \
			haproxy nftables socat jq iproute \
			rsyslog logrotate python3 python3-pip golang \
			|| die "dnf install failed"
	fi

	log "dependencies installed"

	# Report, don't assume: the WAF will not build without AVX2, and finding
	# that out at the end of a kernel build wastes an hour.
	if grep -qo avx2 /proc/cpuinfo; then
		log "CPU supports AVX2"
	else
		warn "CPU has NO AVX2 — Vet-WAF cannot run on this host"
	fi
}

# ---------------------------------------------------------------------------
do_logging()
{
	step "Centralised logging"
	mkdir -p "$LOG_DIR"
	chmod 0750 "$LOG_DIR"

	# Vet-WAF is a kernel module: everything it emits arrives as kernel
	# messages, not as an application log. Every module message carries the
	# prefix "[Vet-WAF <mod>] " from lib/log.h:170 (mod is fw, tls or
	# ktest), which is what we select on — matching that prefix is exact,
	# where guessing at message substrings would both miss records and
	# capture unrelated kernel output.
	cat > /etc/rsyslog.d/30-vet-waf.conf <<EOF
# Vet-WAF centralised logging — managed by waf-bootstrap.sh
#
# The modules log through printk, so records arrive on the kern facility
# tagged "[Vet-WAF fw]", "[Vet-WAF tls]" or "[Vet-WAF ktest]".

\$FileCreateMode 0640

template(name="VetWafFmt" type="string"
	 string="%TIMESTAMP:::date-rfc3339% $SELF_NAME %syslogtag%%msg%\\n")

# Everything from the Vet-WAF modules.
if (\$syslogfacility-text == "kern") and (\$msg contains "[Vet-WAF ") then {
	action(type="omfile" file="$LOG_DIR/engine.log" template="VetWafFmt")

	# Blocked-request records are the ones you actually review after an
	# attack, so give them their own file. "ERROR:" is the T_ERR_NL prefix;
	# "frang" and "filter" cover the limit and blocking paths.
	if (\$msg contains "frang" or \$msg contains "filter" or \\
	    \$msg contains "block" or \$msg contains "ERROR:") then
		action(type="omfile" file="$LOG_DIR/security.log" template="VetWafFmt")

	stop
}

# haproxy front-end access and health-check transitions.
if (\$programname == "haproxy") then {
	action(type="omfile" file="$LOG_DIR/haproxy.log" template="VetWafFmt")
	stop
}

# Firewall drops (nft log prefix "vetwaf-fw-drop").
if (\$msg contains "vetwaf-fw-drop") then {
	action(type="omfile" file="$LOG_DIR/firewall.log" template="VetWafFmt")
	stop
}

# ---------------------------------------------------------------------------
# OPTIONAL: forward to the peer or to a collector, so one node's logs survive
# that node dying. Uncomment ONE of these and set the target.
#
# The queue settings matter: without them rsyslog blocks when the target is
# unreachable, and a blocked rsyslog on a WAF node is its own outage.
# ---------------------------------------------------------------------------
#*.* action(type="omfwd"
#	  target="$PEER_IP" port="514" protocol="tcp"
#	  queue.type="linkedList" queue.size="10000"
#	  queue.saveOnShutdown="on"
#	  action.resumeRetryCount="-1")
EOF

	cat > /etc/logrotate.d/vet-waf <<EOF
# Vet-WAF log rotation — managed by waf-bootstrap.sh
$LOG_DIR/*.log {
	daily
	rotate 14
	compress
	delaycompress
	missingok
	notifempty
	create 0640 root adm
	sharedscripts
	postrotate
		/usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || \\
			systemctl kill -s HUP rsyslog.service 2>/dev/null || true
	endscript
}
EOF

	# Kernel ring buffer is small and Vet-WAF is chatty under attack; a
	# too-small buffer loses the beginning of an incident.
	if [ -w /proc/sys/kernel/printk_ratelimit ]; then
		sysctl -qw kernel.printk_ratelimit=0 2>/dev/null || true
	fi
	cat > /etc/sysctl.d/60-vet-waf-log.conf <<'EOF'
# Do not rate-limit kernel messages: under attack the dropped lines are
# exactly the ones describing the attack.
kernel.printk_ratelimit = 0
EOF

	systemctl restart rsyslog 2>/dev/null || warn "could not restart rsyslog"
	log "logging configured under $LOG_DIR"
	log "  engine.log security.log haproxy.log firewall.log"
}

# ---------------------------------------------------------------------------
do_services()
{
	step "systemd units"
	local here
	here=$(cd "$(dirname "$0")" && pwd)

	mkdir -p /etc/vet_waf
	[ -f /etc/vet_waf/cluster.env ] || {
		install -m 0640 "$here/cluster.env" /etc/vet_waf/cluster.env
		log "installed /etc/vet_waf/cluster.env — EDIT IT before starting"
	}

	install -m 0750 "$here/waf-health.sh"   /usr/local/sbin/waf-health.sh
	install -m 0750 "$here/waf-sync.sh"     /usr/local/sbin/waf-sync.sh
	install -m 0750 "$here/waf-firewall.sh" /usr/local/sbin/waf-firewall.sh

	cat > /etc/systemd/system/waf-health.service <<'EOF'
[Unit]
Description=Vet-WAF health agent for haproxy agent-check
Documentation=https://hoangtuvungcao.github.io/vet-waf/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=CLUSTER_ENV=/etc/vet_waf/cluster.env
ExecStart=/usr/local/sbin/waf-health.sh --serve
Restart=always
RestartSec=2
# The agent only reads /proc and curls loopback.
NoNewPrivileges=yes
ProtectHome=yes
ProtectSystem=strict
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

	# Replica pull timer. On the author node this unit stays disabled;
	# waf-sync.sh refuses to pull there anyway.
	cat > /etc/systemd/system/waf-sync.service <<'EOF'
[Unit]
Description=Vet-WAF policy pull from the cluster author
After=network-online.target

[Service]
Type=oneshot
Environment=CLUSTER_ENV=/etc/vet_waf/cluster.env
ExecStart=/usr/local/sbin/waf-sync.sh --pull
EOF

	cat > /etc/systemd/system/waf-sync.timer <<'EOF'
[Unit]
Description=Pull Vet-WAF policy from the author every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
# Stagger so both nodes never reload in the same instant.
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF

	systemctl daemon-reload
	systemctl enable --now waf-health.service 2>/dev/null \
		|| warn "waf-health did not start — check 'journalctl -u waf-health'"
	log "units installed; enable the pull timer on the REPLICA only:"
	log "  systemctl enable --now waf-sync.timer"
}

# ---------------------------------------------------------------------------
do_verify()
{
	step "Verification"
	local ok=0 bad=0
	chk() {
		if eval "$2" >/dev/null 2>&1; then
			printf '  \033[0;32mOK  \033[0m %s\n' "$1"; ok=$((ok+1))
		else
			printf '  \033[0;31mMISS\033[0m %s\n' "$1"; bad=$((bad+1))
		fi
	}

	chk "gcc"                  "command -v gcc"
	chk "make"                 "command -v make"
	chk "git"                  "command -v git"
	chk "rsync"                "command -v rsync"
	chk "curl"                 "command -v curl"
	chk "haproxy"              "command -v haproxy"
	chk "nft"                  "command -v nft"
	chk "socat"                "command -v socat"
	chk "python3"              "command -v python3"
	chk "AVX2 CPU support"     "grep -qo avx2 /proc/cpuinfo"
	chk "kernel headers"       "test -d /lib/modules/$(uname -r)/build"
	chk "cluster.env"          "test -f /etc/vet_waf/cluster.env"
	chk "log directory"        "test -d $LOG_DIR"
	chk "rsyslog rules"        "test -f /etc/rsyslog.d/30-vet-waf.conf"
	chk "logrotate rules"      "test -f /etc/logrotate.d/vet-waf"
	chk "health agent running" "systemctl is-active --quiet waf-health"
	chk "Vet-WAF source"       "test -d $SRC_DIR"
	chk "Vet-WAF loaded"       "sysctl -n net.vet_waf.state"
	chk "haproxy config valid" "haproxy -c -f /etc/haproxy/haproxy.cfg"

	echo
	echo "  ready: $ok   missing: $bad"
	[ "$bad" -eq 0 ] || {
		echo
		echo "  'Vet-WAF loaded' being MISSing is expected until you patch the"
		echo "  kernel, reboot into it, build, and start — see the kernel"
		echo "  patching guide. Everything else should be OK."
	}
	return 0
}

case "${1:---all}" in
	--all)      do_deps; do_logging; do_services; do_verify ;;
	--deps)     do_deps ;;
	--logging)  do_logging ;;
	--services) do_services ;;
	--verify)   do_verify ;;
	*)
		echo "Usage: $0 {--all|--deps|--logging|--services|--verify}" >&2
		exit 1
		;;
esac
