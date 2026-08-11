#!/bin/bash
#
# Vet-WAF — post-reboot cutover: retire the legacy proxy, take over port 80.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59
# Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
# Installed by scripts/deploy-vps.sh as /root/vetwaf-cutover.sh.
#
# Order matters. Vet-WAF binds inside the TCP/IP stack, so port 80 must be
# free before it starts: the legacy proxy is stopped FIRST, and if Vet-WAF
# then fails to come up the legacy proxy is brought straight back.
#
# Modes:
#   --check    read-only preflight. Verifies the kernel, the modules, the
#              config and the origin. Touches nothing. Safe on a live box.
#   --cutover  the real thing: stop legacy, start Vet-WAF, verify, and roll
#              back automatically if verification fails.
#   --rollback stop Vet-WAF and restore the legacy proxy.
#   --status   what is serving right now.
#

set -uo pipefail

TFW_SRC=${TFW_SRC:-/usr/src/vet_waf}
TFW_CFG=${TFW_CFG:-/etc/vet_waf/vet_waf.conf}
LEGACY_SVC=${LEGACY_SVC:-mango-waf}
ORIGIN=${ORIGIN:-85.117.239.3:80}
TEST_HOST=${TEST_HOST:-firewall.hidev.dev}
TEST_PORT=${TEST_PORT:-80}

# Where the control script actually lives: the packaged path, or the staged
# source tree that deploy-vps.sh rsyncs.
if [ -x /lib/vet_waf/scripts/vet_waf.sh ]; then
	TFW_CTL=/lib/vet_waf/scripts/vet_waf.sh
elif [ -x "$TFW_SRC/scripts/vet_waf.sh" ]; then
	TFW_CTL="$TFW_SRC/scripts/vet_waf.sh"
else
	TFW_CTL=""
fi

MODS="tempesta_fw tempesta_regex tempesta_db tempesta_tls tempesta_lib"
KERN_WANT=6.12.12

fail_n=0

log()  { echo -e "\033[0;32m[cutover]\033[0m $*"; }
warn() { echo -e "\033[0;33m[cutover]\033[0m $*" >&2; }
err()  { echo -e "\033[0;31m[cutover]\033[0m $*" >&2; fail_n=$((fail_n + 1)); }
die()  { echo -e "\033[0;31m[cutover]\033[0m $*" >&2; exit 1; }

need_root()
{
	[ "$(id -u)" -eq 0 ] || die "must run as root"
}

tfw_state()
{
	local s
	s=$(sysctl -n net.vet_waf.state 2>/dev/null) || return 1
	echo "$s"
}

legacy_active()
{
	systemctl is-active --quiet "$LEGACY_SVC" 2>/dev/null
}

port80_owner()
{
	# ss reports the listener; Vet-WAF has no user-space process, so an empty
	# result with Vet-WAF started is expected and correct.
	ss -lntp "sport = :$TEST_PORT" 2>/dev/null | tail -n +2
}

# ---------------------------------------------------------------------------
# Preflight — every check is read-only.
# ---------------------------------------------------------------------------
preflight()
{
	log "preflight checks"

	local kver
	kver=$(uname -r)
	if [[ "$kver" == "$KERN_WANT"* ]]; then
		log "  kernel        : $kver"
	else
		err "  kernel        : $kver (expected ${KERN_WANT}*, patched). Reboot into the patched kernel first."
	fi

	# The modules must exist and match THIS kernel. A vermagic mismatch is the
	# single most common post-reboot failure: the tree was built before the
	# reboot, against the old kernel.
	local missing=0 m ko vm
	for m in $MODS; do
		ko=$(find "$TFW_SRC" -name "$m.ko" -print -quit 2>/dev/null)
		if [ -z "$ko" ]; then
			err "  module        : $m.ko not built (run 'make' in $TFW_SRC)"
			missing=1
			continue
		fi
		vm=$(modinfo -F vermagic "$ko" 2>/dev/null | awk '{print $1}')
		if [ "$vm" != "$kver" ]; then
			err "  module        : $m.ko built for '$vm', running '$kver' — rebuild"
			missing=1
		fi
	done
	[ $missing -eq 0 ] && log "  modules       : all 5 present and match $kver"

	if [ -n "$TFW_CTL" ]; then
		log "  control script: $TFW_CTL"
	else
		err "  control script: not found (looked in /lib/vet_waf/scripts and $TFW_SRC/scripts)"
	fi

	if [ -f "$TFW_CFG" ]; then
		log "  config        : $TFW_CFG"
		if grep -qE "^[[:space:]]*server[[:space:]]+${ORIGIN//./\\.}" "$TFW_CFG"; then
			log "  backend       : $ORIGIN"
		else
			warn "  backend       : $ORIGIN not found in the config — check srv_group"
		fi
	else
		err "  config        : $TFW_CFG missing"
	fi

	# The origin must be answering before we move traffic onto Vet-WAF;
	# otherwise a cutover turns a working site into 502s.
	if curl -fsS -o /dev/null -m 5 "http://$ORIGIN/" 2>/dev/null; then
		log "  origin        : $ORIGIN answering"
	else
		# A non-2xx is still a live origin — only a connection failure is fatal.
		if curl -sS -o /dev/null -m 5 "http://$ORIGIN/" 2>/dev/null; then
			warn "  origin        : $ORIGIN reachable but returned non-2xx"
		else
			err "  origin        : $ORIGIN unreachable — do not cut over"
		fi
	fi

	if legacy_active; then
		log "  legacy        : $LEGACY_SVC active (will be stopped)"
	else
		log "  legacy        : $LEGACY_SVC not active"
	fi

	local st
	if st=$(tfw_state); then
		log "  vet-waf       : state=$st"
	else
		log "  vet-waf       : not loaded"
	fi

	if [ $fail_n -eq 0 ]; then
		log "preflight PASSED"
		return 0
	fi
	err "preflight FAILED ($fail_n problem(s))"
	return 1
}

# ---------------------------------------------------------------------------
# Verification — run after Vet-WAF is up, decides whether we keep the cutover.
# ---------------------------------------------------------------------------
verify_live()
{
	local rc=0 st code

	st=$(tfw_state) || { err "sysctl net.vet_waf.state unavailable"; return 1; }
	if [ "$st" != "start" ]; then
		err "state is '$st', expected 'start'"
		return 1
	fi
	log "  state         : start"

	[ -r /proc/vet_waf/perfstat ] \
		|| { err "/proc/vet_waf/perfstat missing"; return 1; }

	# A real request through the edge. Host header is mandatory: the config
	# enables http_strict_host_checking and ends the chain with `-> block`,
	# so a hostless probe is dropped by design and would look like an outage.
	code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 \
		-H "Host: $TEST_HOST" "http://127.0.0.1:$TEST_PORT/" 2>/dev/null)
	if [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
		log "  proxied req   : HTTP $code"
	else
		err "  proxied req   : HTTP ${code:-no-response} — traffic is NOT flowing"
		rc=1
	fi

	# perfstat must show the request we just made actually reaching the
	# backend. A 200 served from cache with zero forwarded messages would
	# mean the origin link is still untested.
	local fwd conns
	fwd=$(awk -F':' '/^Client messages forwarded/ {gsub(/[^0-9]/,"",$2); print $2; exit}' \
		/proc/vet_waf/perfstat 2>/dev/null)
	conns=$(awk -F':' '/^Server connections active/ {gsub(/[^0-9]/,"",$2); print $2; exit}' \
		/proc/vet_waf/perfstat 2>/dev/null)
	log "  forwarded     : ${fwd:-?} message(s) to the origin"
	if [ -n "$conns" ] && [ "$conns" -gt 0 ] 2>/dev/null; then
		log "  origin conns  : $conns active"
	else
		warn "  origin conns  : none active — the origin link may be down"
	fi

	return $rc
}

show_perfstat()
{
	[ -r /proc/vet_waf/perfstat ] || return 0
	echo
	log "/proc/vet_waf/perfstat"
	grep -E '^(Client messages|Client connections active|Clients online|Server messages|Server connections|Cache (hits|misses))' \
		/proc/vet_waf/perfstat 2>/dev/null \
		| sed -e 's/\t\+/ /g' -e 's/^/    /'
	echo
}

start_legacy()
{
	legacy_active && return 0
	systemctl start "$LEGACY_SVC" 2>/dev/null \
		&& log "  $LEGACY_SVC restarted" \
		|| warn "  could not restart $LEGACY_SVC — port $TEST_PORT may be unserved"
}

stop_vetwaf()
{
	if [ -n "$TFW_CTL" ]; then
		TFW_CFG_PATH="$TFW_CFG" "$TFW_CTL" --stop >/dev/null 2>&1
	fi
	systemctl stop vet-waf 2>/dev/null
	sysctl -e -w net.vet_waf.state=stop >/dev/null 2>&1
}

rollback()
{
	warn "rolling back"
	stop_vetwaf
	start_legacy
	warn "rolled back to $LEGACY_SVC"
}

# ---------------------------------------------------------------------------
cutover()
{
	need_root
	preflight || die "refusing to cut over — fix the failures above"

	log "stopping legacy proxy: $LEGACY_SVC"
	if legacy_active; then
		# Disable too, or a reboot brings it back and it races Vet-WAF for
		# port 80 — whichever wins is a coin flip.
		systemctl stop "$LEGACY_SVC"    || die "failed to stop $LEGACY_SVC"
		systemctl disable "$LEGACY_SVC" 2>/dev/null
		log "  stopped and disabled"
	else
		log "  already inactive"
	fi

	# Anything else still holding :80 (a stray nginx, a container publish)
	# will make the Vet-WAF listener fail. Report it rather than killing it.
	local owner
	owner=$(port80_owner)
	if [ -n "$owner" ]; then
		warn "port $TEST_PORT still held by:"
		echo "$owner" | sed 's/^/    /'
		rollback
		die "free port $TEST_PORT and re-run"
	fi

	log "starting Vet-WAF"
	if ! TFW_CFG_PATH="$TFW_CFG" "$TFW_CTL" --start; then
		err "Vet-WAF failed to start — see dmesg"
		dmesg | tail -20 | sed 's/^/    /'
		rollback
		exit 1
	fi

	# Give the listener and the origin connections a moment to establish.
	sleep 3

	log "verifying live traffic"
	if ! verify_live; then
		dmesg | tail -20 | sed 's/^/    /'
		rollback
		die "verification failed — traffic restored to $LEGACY_SVC"
	fi

	systemctl enable vet-waf 2>/dev/null \
		&& log "vet-waf.service enabled for boot" \
		|| warn "vet-waf.service not enabled — Vet-WAF will NOT survive a reboot"

	show_perfstat
	log "CUTOVER COMPLETE — Vet-WAF is serving $TEST_HOST"
}

status()
{
	local st
	if st=$(tfw_state); then
		log "vet-waf : state=$st"
	else
		log "vet-waf : not loaded"
	fi
	legacy_active && log "legacy  : $LEGACY_SVC ACTIVE" || log "legacy  : $LEGACY_SVC inactive"
	log "kernel  : $(uname -r)"
	local owner
	owner=$(port80_owner)
	[ -n "$owner" ] && { log "port $TEST_PORT held by:"; echo "$owner" | sed 's/^/    /'; }
	show_perfstat
}

case "${1:---check}" in
	--check)
		preflight
		exit $?
		;;
	--cutover)
		cutover
		;;
	--rollback)
		need_root
		rollback
		;;
	--status)
		status
		;;
	*)
		echo "Usage: $0 {--check|--cutover|--rollback|--status}" >&2
		exit 1
		;;
esac
