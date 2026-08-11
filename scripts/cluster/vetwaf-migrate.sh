#!/bin/bash
#
# Vet-WAF — per-node migration driver: mango-waf -> Vet-WAF, safely.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.  See LICENSE.
#
# ---------------------------------------------------------------------------
# WHAT THIS DOES
# ---------------------------------------------------------------------------
# Migrates a single edge node from the legacy mango-waf proxy to Vet-WAF with
# zero downtime up to the cutover instant and automatic rollback if the cutover
# does not verify. Run it on the node (it is rsynced to /usr/src/vet_waf by
# scripts/deploy-vps.sh). Drive it one phase at a time and read the output
# between phases:
#
#   ./vetwaf-migrate.sh --preflight     # read-only: kernel, modules, origin
#   ./vetwaf-migrate.sh --install       # non-disruptive: cert, config, units
#   ./vetwaf-migrate.sh --parse-test    # non-disruptive: prove config on :8080/:8443
#   ./vetwaf-migrate.sh --cutover       # THE switch: mango down, Vet-WAF up, auto-rollback
#   ./vetwaf-migrate.sh --status        # what is serving right now
#   ./vetwaf-migrate.sh --purge-legacy  # ONLY after cutover verified: delete mango + haproxy
#   ./vetwaf-migrate.sh --rollback      # undo: Vet-WAF down, mango back
#   ./vetwaf-migrate.sh --full          # preflight->install->parse-test->cutover->purge
#
# The dangerous operations are ORDERED so nothing irreversible happens before
# Vet-WAF is proven to be serving live traffic:
#   - --parse-test never touches mango (Vet-WAF runs on alt ports beside it).
#   - --cutover stops mango FIRST (Vet-WAF binds inside the stack, so :80/:443
#     must be free), then rolls mango straight back if verification fails.
#   - --purge-legacy REFUSES to run unless Vet-WAF is up and answering.
#

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration — authoritative here; cluster.env is sourced only for node IDs.
# ---------------------------------------------------------------------------
SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # /usr/src/vet_waf

DOMAIN=${DOMAIN:-firewall.hidev.dev}
ORIGIN=${ORIGIN:-103.77.246.164:80}          # protected backend, never in DNS
KERN_WANT=${KERN_WANT:-6.12.12}
LEGACY_SVC=${LEGACY_SVC:-mango-waf}

CFG_DIR=/etc/vet_waf
CFG_LIVE="$CFG_DIR/vet_waf.conf"              # what the service loads
CFG_TEST="$CFG_DIR/vet_waf.parsetest.conf"    # alt-port derivative
TLS_DIR="$CFG_DIR/tls"
CRT="$TLS_DIR/$DOMAIN.crt"
KEY="$TLS_DIR/$DOMAIN.key"
UA_LIVE="$CFG_DIR/ua_block_rules.conf"

SRC_CFG="$SRC_ROOT/etc/vet_waf.prod.conf"
SRC_UA="$SRC_ROOT/etc/ua_block_rules.conf"
SRC_UNIT="$SRC_ROOT/pkg/debian/vet-waf.service"

CTL_LINK=/lib/vet_waf/scripts                 # symlink -> $SRC_ROOT/scripts
CTL="$CTL_LINK/vet_waf.sh"

# The control script derives its module paths from its own location. Invoked
# through the /lib/vet_waf/scripts symlink it computes a root of /lib/vet_waf,
# which holds no modules — so a bare call fails with "tempesta_lib.ko: No such
# file". Export the same explicit paths the systemd unit sets, pointing at the
# real source tree, so a manual --start behaves identically to the service.
export TFW_PATH="$SRC_ROOT/fw"
export TDB_PATH="$SRC_ROOT/db/core"
export TLS_PATH="$SRC_ROOT/tls"
export LIB_PATH="$SRC_ROOT/lib"
export REGEX_PATH="$SRC_ROOT/regex"
export REGEX_SETUP_SCRIPT_PATH="$CTL_LINK/regex_setup.sh"

# Alt ports used for the live-fire parse test while mango still owns 80/443.
ALT_HTTP=8080
ALT_HTTPS=8443

MODS="tempesta_fw tempesta_regex tempesta_db tempesta_tls tempesta_lib"

# nftables mark that makes the http_chain `mark == 80` HTTPS-redirect rule fire
# for inbound :80 traffic only (0x50 == 80).
NFT_DIR=/etc/nftables.d
NFT_FILE="$NFT_DIR/vetwaf-mark.nft"
NFT_SVC=vetwaf-nftmark
NFT_UNIT="/etc/systemd/system/$NFT_SVC.service"

# Set by cutover() when it disables a legacy unit that was enabled at boot, so
# rollback() restores boot state and not merely the running state.
LEGACY_WAS_ENABLED=0

fail_n=0
log()  { echo -e "\033[0;32m[migrate]\033[0m $*"; }
warn() { echo -e "\033[0;33m[migrate]\033[0m $*" >&2; }
err()  { echo -e "\033[0;31m[migrate]\033[0m $*" >&2; fail_n=$((fail_n + 1)); }
die()  { echo -e "\033[0;31m[migrate]\033[0m $*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root"; }

# Best-effort node identity for nicer logging; never fatal.
SELF_NAME="$(hostname -s 2>/dev/null || echo node)"
if [ -f "$CFG_DIR/cluster.env" ]; then
	# shellcheck disable=SC1091
	. "$CFG_DIR/cluster.env" 2>/dev/null && cluster_identify 2>/dev/null || true
elif [ -f "$SRC_ROOT/scripts/cluster/cluster.env" ]; then
	# shellcheck disable=SC1091
	. "$SRC_ROOT/scripts/cluster/cluster.env" 2>/dev/null && cluster_identify 2>/dev/null || true
fi

tfw_state()    { sysctl -n net.vet_waf.state 2>/dev/null; }
legacy_active(){ systemctl is-active --quiet "$LEGACY_SVC" 2>/dev/null; }
vetwaf_up()    { [ "$(tfw_state)" = "start" ]; }

port_owner() { ss -lntp "sport = :$1" 2>/dev/null | tail -n +2; }

# ---------------------------------------------------------------------------
# PREFLIGHT — read-only. Verifies everything --cutover will rely on.
# ---------------------------------------------------------------------------
preflight()
{
	log "preflight on ${SELF_NAME}"
	fail_n=0

	local kver; kver=$(uname -r)
	if [[ "$kver" == "$KERN_WANT"* ]]; then
		log "  kernel        : $kver"
	else
		err "  kernel        : $kver (need ${KERN_WANT}* patched kernel — reboot into it first)"
	fi

	# Modules must exist AND match the running kernel. A vermagic mismatch is
	# the classic post-reboot trap: built before the reboot, against the old
	# kernel, so insmod rejects them.
	local missing=0 m ko vm
	for m in $MODS; do
		ko=$(find "$SRC_ROOT" -name "$m.ko" -print -quit 2>/dev/null)
		if [ -z "$ko" ]; then
			err "  module        : $m.ko not built (run: cd $SRC_ROOT && make TFW_MODULES_ONLY=1)"
			missing=1; continue
		fi
		vm=$(modinfo -F vermagic "$ko" 2>/dev/null | awk '{print $1}')
		[ "$vm" = "$kver" ] || { err "  module        : $m.ko built for '$vm' != running '$kver' — rebuild"; missing=1; }
	done
	[ $missing -eq 0 ] && log "  modules       : all 5 present, vermagic $kver"

	[ -x "$CTL" ] && log "  control script: $CTL" \
	              || err "  control script: $CTL missing (run --install to create the symlink)"

	[ -f "$SRC_CFG" ] && log "  source config : $SRC_CFG" \
	                  || err "  source config : $SRC_CFG missing from the synced tree"
	[ -f "$SRC_UA" ]  && log "  scanner rules : $SRC_UA" \
	                  || err "  scanner rules : $SRC_UA missing from the synced tree"

	# The origin must answer before we move traffic, or a cutover turns a
	# working site into 502s. Any HTTP reply (even non-2xx) means it is live;
	# only a connection failure is fatal.
	if curl -sS -o /dev/null -m 5 "http://$ORIGIN/" 2>/dev/null; then
		local oc; oc=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://$ORIGIN/" 2>/dev/null)
		log "  origin        : $ORIGIN answering (HTTP $oc)"
	else
		err "  origin        : $ORIGIN unreachable — DO NOT cut over"
	fi

	legacy_active && log "  legacy        : $LEGACY_SVC active (will be replaced)" \
	             || log "  legacy        : $LEGACY_SVC not active"

	command -v nft >/dev/null 2>&1 && log "  nftables      : present (:80->:443 redirect mark available)" \
	                              || warn "  nftables      : absent — :80 will SERVE instead of redirecting (safe, degraded)"

	if [ $fail_n -eq 0 ]; then log "preflight PASSED"; return 0; fi
	err "preflight FAILED ($fail_n problem(s))"; return 1
}

# ---------------------------------------------------------------------------
# INSTALL — idempotent, non-disruptive. Puts everything in place but starts
# nothing and does not touch mango. Safe to run repeatedly on a live box.
# ---------------------------------------------------------------------------
install_all()
{
	need_root
	log "installing Vet-WAF artifacts (non-disruptive)"

	# 1. control-script symlink the systemd unit expects at /lib/vet_waf/scripts
	mkdir -p /lib/vet_waf
	ln -sfn "$SRC_ROOT/scripts" "$CTL_LINK"
	log "  symlink   : $CTL_LINK -> $SRC_ROOT/scripts"

	# 2. self-signed origin certificate (idempotent — keep an existing one).
	#    Valid for the apex name + wildcard; accepted by Cloudflare Full mode.
	mkdir -p "$TLS_DIR"; chmod 700 "$TLS_DIR"
	if [ -f "$CRT" ] && [ -f "$KEY" ]; then
		log "  tls       : reusing $CRT"
	else
		openssl req -x509 -newkey rsa:2048 -nodes \
			-keyout "$KEY" -out "$CRT" -days 3650 \
			-subj "/CN=$DOMAIN" \
			-addext "subjectAltName=DNS:$DOMAIN,DNS:*.hidev.dev" >/dev/null 2>&1 \
			|| die "openssl failed to generate the self-signed certificate"
		chmod 600 "$KEY"; chmod 644 "$CRT"
		log "  tls       : generated self-signed $CRT (CN=$DOMAIN, +*.hidev.dev, 10y)"
	fi

	# 3. scanner rules, then the production config (back up any existing live
	#    config so a hand-edit is never lost).
	install -m 0644 "$SRC_UA" "$UA_LIVE"
	log "  rules     : $UA_LIVE"

	if [ -f "$CFG_LIVE" ] && ! cmp -s "$SRC_CFG" "$CFG_LIVE"; then
		cp -a "$CFG_LIVE" "$CFG_LIVE.bak.$(date +%Y%m%d-%H%M%S)"
		log "  config    : backed up previous $CFG_LIVE"
	fi
	install -m 0644 "$SRC_CFG" "$CFG_LIVE"
	log "  config    : $CFG_LIVE (backend $ORIGIN, domain $DOMAIN)"

	# 4. systemd unit for Vet-WAF.
	install -m 0644 "$SRC_UNIT" /etc/systemd/system/vet-waf.service
	log "  unit      : /etc/systemd/system/vet-waf.service"

	# 5. nftables :80 redirect-mark table + a oneshot unit to apply it. A
	#    DEDICATED table (inet vetwaf_mark) and a DEDICATED unit are used on
	#    purpose: this never reads or rewrites the distro's /etc/nftables.conf,
	#    so it cannot clobber another firewall and is trivially reversible.
	if command -v nft >/dev/null 2>&1; then
		mkdir -p "$NFT_DIR"
		cat > "$NFT_FILE" <<-'NFT'
			#!/usr/sbin/nft -f
			# Vet-WAF: tag inbound :80 packets with fwmark 0x50 (80) so the
			# http_chain "mark == 80" rule redirects plain HTTP to HTTPS.
			# add-then-delete makes reloading this file idempotent.
			add table inet vetwaf_mark
			delete table inet vetwaf_mark
			table inet vetwaf_mark {
			    chain prerouting {
			        type filter hook prerouting priority mangle; policy accept;
			        tcp dport 80 meta mark set 0x50
			    }
			}
		NFT
		cat > "$NFT_UNIT" <<-UNIT
			[Unit]
			Description=Vet-WAF :80 fwmark for HTTP->HTTPS redirect
			DefaultDependencies=no
			Before=vet-waf.service network-pre.target
			Wants=network-pre.target
			[Service]
			Type=oneshot
			RemainAfterExit=yes
			ExecStart=/usr/sbin/nft -f $NFT_FILE
			ExecStop=/usr/sbin/nft delete table inet vetwaf_mark
			[Install]
			WantedBy=multi-user.target
		UNIT
		log "  nftmark   : $NFT_FILE + $NFT_SVC.service (not yet applied)"
	else
		warn "  nftmark   : nft absent — skipping redirect mark (:80 will serve, safe)"
	fi

	systemctl daemon-reload
	log "install complete — nothing started, $LEGACY_SVC untouched"
}

# ---------------------------------------------------------------------------
# PARSE-TEST — start Vet-WAF on ALT ports (8080/8443) beside a still-running
# mango, prove the config parses and serves end-to-end, then stop it. Zero
# downtime: mango keeps 80/443 the entire time. This is where the real risks
# are caught — regex module load, `listen 443` with only a named-vhost cert,
# and backend reachability — without exposing users to any of them.
# ---------------------------------------------------------------------------
parse_test()
{
	need_root
	[ -f "$CFG_LIVE" ] || die "run --install first ($CFG_LIVE missing)"
	[ -f "$CRT" ]      || die "run --install first ($CRT missing)"
	[ -x "$CTL" ]      || die "run --install first ($CTL missing)"

	# Make sure no stale Vet-WAF instance is loaded.
	if vetwaf_up; then
		warn "Vet-WAF already loaded — stopping it before the parse test"
		TFW_CFG_PATH="$CFG_LIVE" "$CTL" --stop >/dev/null 2>&1
		sleep 1
	fi

	# Derive an alt-port config from exactly what will go live. Two rewrites:
	#   - listen ports -> 8080/8443 so this runs beside mango.
	#   - http_strict_host_checking -> false, ONLY here: that check compares the
	#     port implied by the Host/:authority against the real listener port, so
	#     an :8080 listener rejects a normal `Host: firewall.hidev.dev` (implies
	#     :80) as an attack and silently drops it. Strict host checking can only
	#     be exercised on the real ports, and it is — by verify_live at cutover
	#     (:80->80, :443->443 both match). The mark==80 redirect rule stays but
	#     cannot match here (no nft mark on 8080), so :8080 requests fall through
	#     to the host rules and get proxied — which is what proves the backend.
	sed -e 's/^listen 80;/listen '"$ALT_HTTP"';/' \
	    -e 's/^listen 443 /listen '"$ALT_HTTPS"' /' \
	    -e 's/http_strict_host_checking[[:space:]]\+true/http_strict_host_checking    false/' \
	    "$CFG_LIVE" > "$CFG_TEST"
	log "parse test on :$ALT_HTTP/:$ALT_HTTPS (mango keeps :80/:443; strict-host checked at cutover)"

	if ! TFW_CFG_PATH="$CFG_TEST" "$CTL" --start; then
		err "Vet-WAF did NOT start — config rejected or a module failed to load"
		dmesg | tail -25 | sed 's/^/    /'
		TFW_CFG_PATH="$CFG_TEST" "$CTL" --stop >/dev/null 2>&1
		rm -f "$CFG_TEST"
		die "parse test FAILED (start)"
	fi
	sleep 2

	local rc=0 st code
	st=$(tfw_state)
	[ "$st" = "start" ] && log "  parse/load    : OK (state=start, regex + TLS modules up)" \
	                    || { err "  parse/load    : state='$st'"; rc=1; }

	# Plain HTTP through the edge to the backend.
	code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 \
		-H "Host: $DOMAIN" "http://127.0.0.1:$ALT_HTTP/" 2>/dev/null)
	[ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ] \
		&& log "  http  :$ALT_HTTP    : HTTP $code (routed to origin)" \
		|| { err "  http  :$ALT_HTTP    : HTTP ${code:-none} — routing/backend broken"; rc=1; }

	# TLS termination + SNI + the named-vhost certificate + backend. --resolve
	# forces SNI=$DOMAIN while connecting to loopback.
	code=$(curl -sk -o /dev/null -w '%{http_code}' -m 10 \
		--resolve "$DOMAIN:$ALT_HTTPS:127.0.0.1" "https://$DOMAIN:$ALT_HTTPS/" 2>/dev/null)
	[ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ] \
		&& log "  https :$ALT_HTTPS   : HTTP $code (TLS terminated, cert presented, routed to origin)" \
		|| { err "  https :$ALT_HTTPS   : HTTP ${code:-none} — TLS or backend broken"; rc=1; }

	log "stopping the parse-test instance (mango was never touched)"
	TFW_CFG_PATH="$CFG_TEST" "$CTL" --stop >/dev/null 2>&1
	rm -f "$CFG_TEST"

	if [ $rc -eq 0 ]; then log "parse test PASSED — safe to --cutover"; return 0; fi
	die "parse test FAILED — do not cut over"
}

# ---------------------------------------------------------------------------
# Live verification, used after Vet-WAF takes :80/:443.
# ---------------------------------------------------------------------------
verify_live()
{
	local rc=0 code redir

	vetwaf_up || { err "state='$(tfw_state)', expected 'start'"; return 1; }
	log "  state         : start"
	[ -r /proc/vet_waf/perfstat ] || { err "/proc/vet_waf/perfstat missing"; return 1; }

	# :80 — ideally a 301 to HTTPS (mark active); a 2xx/3xx/4xx means the mark
	# did not propagate and :80 is being served directly. That is degraded but
	# safe (no loop, no outage), so it is a warning, not a failure.
	redir=$(curl -s -o /dev/null -w '%{http_code}' -m 10 \
		-H "Host: $DOMAIN" "http://127.0.0.1:80/" 2>/dev/null)
	case "$redir" in
		30[1237]) log "  http  :80     : HTTP $redir -> HTTPS redirect working" ;;
		"" | 000 | 5*) err "  http  :80     : HTTP ${redir:-none} — :80 not serving"; rc=1 ;;
		*) warn "  http  :80     : HTTP $redir (served, not redirected — nft mark not active; safe)" ;;
	esac

	# :443 — the real user path: TLS terminated here, proxied to the origin.
	code=$(curl -sk -o /dev/null -w '%{http_code}' -m 10 \
		--resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN:443/" 2>/dev/null)
	if [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
		log "  https :443    : HTTP $code (serving $DOMAIN through to origin)"
	else
		err "  https :443    : HTTP ${code:-none} — HTTPS traffic is NOT flowing"; rc=1
	fi

	# Confirm the request actually reached the backend (a cached/edge-only 200
	# with zero forwarded messages would leave the origin link untested).
	local fwd conns
	fwd=$(awk -F':' '/^Client messages forwarded/  {gsub(/[^0-9]/,"",$2); print $2; exit}' /proc/vet_waf/perfstat 2>/dev/null)
	conns=$(awk -F':' '/^Server connections active/ {gsub(/[^0-9]/,"",$2); print $2; exit}' /proc/vet_waf/perfstat 2>/dev/null)
	log "  forwarded     : ${fwd:-?} message(s) to origin; ${conns:-?} origin conn(s) active"
	[ -n "$conns" ] && [ "$conns" -gt 0 ] 2>/dev/null || warn "  origin link    : no active origin connections yet"

	return $rc
}

start_legacy()
{
	legacy_active || systemctl start "$LEGACY_SVC" 2>/dev/null \
		&& log "  $LEGACY_SVC restarted" \
		|| warn "  could not restart $LEGACY_SVC — :80/:443 may be unserved"
	if [ "$LEGACY_WAS_ENABLED" = 1 ]; then
		systemctl enable "$LEGACY_SVC" 2>/dev/null \
			&& log "  $LEGACY_SVC re-enabled for boot" \
			|| warn "  could not re-enable $LEGACY_SVC"
	fi
}

stop_vetwaf()
{
	[ -x "$CTL" ] && TFW_CFG_PATH="$CFG_LIVE" "$CTL" --stop >/dev/null 2>&1
	systemctl stop vet-waf 2>/dev/null
	sysctl -e -w net.vet_waf.state=stop >/dev/null 2>&1
	systemctl stop "$NFT_SVC" 2>/dev/null
}

rollback()
{
	warn "ROLLING BACK to $LEGACY_SVC"
	stop_vetwaf
	start_legacy
	warn "rolled back"
}

# ---------------------------------------------------------------------------
# CUTOVER — the switch. mango down first (the stack needs :80/:443 free), then
# Vet-WAF up, verified, and enabled. Any failure auto-restores mango.
# ---------------------------------------------------------------------------
cutover()
{
	need_root
	preflight || die "refusing to cut over — fix the failures above"

	systemctl is-enabled --quiet "$LEGACY_SVC" 2>/dev/null && LEGACY_WAS_ENABLED=1

	# Apply the redirect mark first (before anything binds :80) so the very
	# first :80 request is already redirected. Non-fatal if nft is absent.
	if command -v nft >/dev/null 2>&1 && [ -f "$NFT_FILE" ]; then
		systemctl enable --now "$NFT_SVC" 2>/dev/null \
			&& log "nft :80 mark applied and enabled for boot" \
			|| warn "could not apply the nft :80 mark — :80 will serve (safe)"
	fi

	log "stopping legacy proxy: $LEGACY_SVC"
	if legacy_active; then
		systemctl stop "$LEGACY_SVC"    || { rollback; die "failed to stop $LEGACY_SVC"; }
		systemctl disable "$LEGACY_SVC" 2>/dev/null
		log "  stopped and disabled (won't race Vet-WAF for :80 on reboot)"
	else
		log "  already inactive"
	fi

	# Anything else still holding :80/:443 (a stray nginx, a container publish)
	# makes the Vet-WAF listener fail. Report and roll back rather than kill.
	local o80 o443; o80=$(port_owner 80); o443=$(port_owner 443)
	if [ -n "$o80$o443" ]; then
		warn "ports still held:"; { echo "$o80"; echo "$o443"; } | sed '/^$/d;s/^/    /'
		rollback; die "free :80/:443 and re-run"
	fi

	log "starting Vet-WAF on :80/:443"
	if ! TFW_CFG_PATH="$CFG_LIVE" "$CTL" --start; then
		err "Vet-WAF failed to start — see dmesg"
		dmesg | tail -25 | sed 's/^/    /'
		rollback; exit 1
	fi
	sleep 3

	log "verifying live traffic"
	if ! verify_live; then
		dmesg | tail -25 | sed 's/^/    /'
		rollback; die "verification failed — traffic restored to $LEGACY_SVC"
	fi

	systemctl enable vet-waf 2>/dev/null \
		&& log "vet-waf.service enabled for boot" \
		|| warn "vet-waf.service NOT enabled — Vet-WAF will not survive a reboot"

	log "CUTOVER COMPLETE — Vet-WAF is serving $DOMAIN on :80/:443"
	log "mango is stopped+disabled but still installed. Verify, then --purge-legacy."
}

# ---------------------------------------------------------------------------
# PURGE-LEGACY — irreversible. Guarded so it can only run once Vet-WAF is
# actually serving. Backs mango up first (root-only), then removes it.
# ---------------------------------------------------------------------------
purge_legacy()
{
	need_root

	# Hard gate: Vet-WAF must be up AND answering HTTPS right now.
	vetwaf_up || die "REFUSING to purge: Vet-WAF is not running (state='$(tfw_state)')"
	local code
	code=$(curl -sk -o /dev/null -w '%{http_code}' -m 10 \
		--resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN:443/" 2>/dev/null)
	{ [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ]; } \
		|| die "REFUSING to purge: Vet-WAF not serving HTTPS (HTTP ${code:-none}). Run --status."
	log "gate passed: Vet-WAF serving $DOMAIN (HTTP $code) — proceeding to purge legacy"

	# --- mango-waf ---------------------------------------------------------
	if systemctl list-unit-files 2>/dev/null | grep -q "^${LEGACY_SVC}\.service" \
	   || [ -e "/etc/systemd/system/$LEGACY_SVC.service" ]; then
		# Discover its install dir from the unit before deleting anything.
		local wd exe root ts tgz
		wd=$(systemctl show -p WorkingDirectory --value "$LEGACY_SVC" 2>/dev/null)
		exe=$(systemctl show -p ExecStart --value "$LEGACY_SVC" 2>/dev/null | grep -oE '/[^ ]+' | head -1)
		root="$wd"; [ -n "$root" ] || root=$(dirname "$exe" 2>/dev/null)
		[ "$root" = "/" ] && root=""    # never treat / as the app dir

		ts=$(date +%Y%m%d-%H%M%S)
		if [ -n "$root" ] && [ -d "$root" ]; then
			tgz="/root/${LEGACY_SVC}-backup-$ts.tgz"
			tar czf "$tgz" -C "$(dirname "$root")" "$(basename "$root")" 2>/dev/null \
				&& { chmod 600 "$tgz"; log "  backed up $root -> $tgz (root-only; delete when confident)"; } \
				|| warn "  could not archive $root"
		fi

		systemctl stop "$LEGACY_SVC" 2>/dev/null
		systemctl disable "$LEGACY_SVC" 2>/dev/null
		rm -f "/etc/systemd/system/$LEGACY_SVC.service" \
		      "/lib/systemd/system/$LEGACY_SVC.service" \
		      "/etc/systemd/system/multi-user.target.wants/$LEGACY_SVC.service"
		systemctl daemon-reload
		systemctl reset-failed "$LEGACY_SVC" 2>/dev/null
		log "  $LEGACY_SVC service removed"
		if [ -n "$root" ] && [ -d "$root" ]; then
			rm -rf "$root"
			log "  removed $root (was mango's install dir — contained its config + CF token)"
		fi
	else
		log "  $LEGACY_SVC not installed — nothing to remove"
	fi

	# --- haproxy (dead weight while we ran the fronting pattern) ----------
	if systemctl list-unit-files 2>/dev/null | grep -q '^haproxy\.service'; then
		systemctl stop haproxy 2>/dev/null
		systemctl disable haproxy 2>/dev/null
		if command -v apt-get >/dev/null 2>&1; then
			DEBIAN_FRONTEND=noninteractive apt-get -y purge haproxy >/dev/null 2>&1 \
				&& log "  haproxy purged" \
				|| warn "  apt purge haproxy reported an issue"
		else
			warn "  apt-get absent — left haproxy stopped+disabled"
		fi
	else
		log "  haproxy not installed — nothing to remove"
	fi

	# Free :80/:443 confirmation: only Vet-WAF (no userspace listener) should
	# remain, i.e. ss shows nothing for these ports.
	local o80 o443; o80=$(port_owner 80); o443=$(port_owner 443)
	if [ -n "$o80$o443" ]; then
		warn "  a userspace process still listens on :80/:443:"
		{ echo "$o80"; echo "$o443"; } | sed '/^$/d;s/^/    /'
	else
		log "  :80/:443 have no userspace listener (Vet-WAF owns them in-stack) — clean"
	fi
	log "legacy purge complete"
}

# ---------------------------------------------------------------------------
status()
{
	log "status on ${SELF_NAME} ($(uname -r))"
	vetwaf_up && log "  vet-waf : state=start (serving)" \
	          || log "  vet-waf : state=$(tfw_state 2>/dev/null || echo 'not loaded')"
	legacy_active && log "  legacy  : $LEGACY_SVC ACTIVE" || log "  legacy  : $LEGACY_SVC inactive"
	systemctl is-active --quiet "$NFT_SVC" 2>/dev/null && log "  nftmark : applied" || log "  nftmark : not applied"
	local o80 o443; o80=$(port_owner 80); o443=$(port_owner 443)
	[ -n "$o80$o443" ] && { log "  :80/:443 userspace listeners:"; { echo "$o80"; echo "$o443"; } | sed '/^$/d;s/^/      /'; } \
	                   || log "  :80/:443 : no userspace listener"
	if [ -r /proc/vet_waf/perfstat ]; then
		grep -E '^(Client messages|Client connections active|Server messages forwarded|Server connections)' \
			/proc/vet_waf/perfstat 2>/dev/null | sed -e 's/\t\+/ /g' -e 's/^/      /'
	fi
}

# ---------------------------------------------------------------------------
usage() { echo "Usage: $0 {--preflight|--install|--parse-test|--cutover|--status|--purge-legacy|--rollback|--full}" >&2; exit 1; }

case "${1:---status}" in
	--preflight)    preflight; exit $? ;;
	--install)      install_all ;;
	--parse-test)   parse_test ;;
	--cutover)      cutover ;;
	--status)       status ;;
	--purge-legacy) purge_legacy ;;
	--rollback)     need_root; LEGACY_WAS_ENABLED=1; rollback ;;
	--full)
		need_root
		preflight   || die "preflight failed"
		install_all
		parse_test  || die "parse test failed"
		cutover     || die "cutover failed"
		purge_legacy
		log "FULL MIGRATION COMPLETE on ${SELF_NAME}"
		;;
	*) usage ;;
esac
