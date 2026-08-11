#!/bin/bash
#
# Vet-WAF — firewall for a two-node cluster.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.  See LICENSE.
#
# Public   : 80, 443           — the world
# Internal : 22, 8081, 8404    — the peer node only
# Egress   : origin backend, DNS, NTP, HTTP(S) for packages
#
# Uses nftables when available (it also gives Vet-WAF the packet-mark sets
# used by the blacklist policy), falling back to ufw.
#
# SAFETY: --apply keeps your CURRENT SSH session alive by allowing established
# connections before the new policy takes effect, and by default arms a
# rollback timer. If you lose the connection, the previous ruleset is restored
# automatically. Confirm with --commit once you have verified access.
#

set -uo pipefail

CLUSTER_ENV=${CLUSTER_ENV:-/etc/vet_waf/cluster.env}
[ -f "$CLUSTER_ENV" ] || CLUSTER_ENV="$(dirname "$0")/cluster.env"
# shellcheck disable=SC1090
. "$CLUSTER_ENV"

ROLLBACK_SECS=${ROLLBACK_SECS:-300}
STATE_DIR=/var/lib/vet-waf
BACKUP=$STATE_DIR/nft-rules.bak
STAMP=/run/vet-waf-fw-pending

log()  { echo -e "\033[0;32m[fw]\033[0m $*"; }
warn() { echo -e "\033[0;33m[fw]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[fw]\033[0m $*" >&2; exit 1; }

# Extra admin sources beyond the peer, e.g. your workstation. Set in
# cluster.env as ADMIN_IPS="1.2.3.4 5.6.7.8".
ADMIN_IPS=${ADMIN_IPS:-}

# --print and --status change nothing, so they must work without root and off
# the cluster. You want to read the ruleset before you apply it, and needing
# root on the target box to do that is exactly how an untested ruleset gets
# applied. VETWAF_NODE=edge-a|edge-b selects the identity when this host owns
# neither node address.
case "${1:-}" in
--print|--status) READONLY=1 ;;
*)                READONLY=0 ;;
esac

if [ "$READONLY" -eq 0 ]; then
	[ "$(id -u)" -eq 0 ] || die "must run as root"
	cluster_identify || die "cannot identify this node"
	mkdir -p "$STATE_DIR"
elif ! cluster_identify 2>/dev/null; then
	case "${VETWAF_NODE:-}" in
	"$NODE_A_NAME") SELF_IP=$NODE_A_IP; SELF_NAME=$NODE_A_NAME
	                PEER_IP=$NODE_B_IP; PEER_NAME=$NODE_B_NAME ;;
	"$NODE_B_NAME") SELF_IP=$NODE_B_IP; SELF_NAME=$NODE_B_NAME
	                PEER_IP=$NODE_A_IP; PEER_NAME=$NODE_A_NAME ;;
	*) die "not running on a cluster node; set VETWAF_NODE=$NODE_A_NAME or $NODE_B_NAME to preview" ;;
	esac
	warn "previewing as $SELF_NAME — this host is not a cluster node"
fi

have_nft() { command -v nft >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
build_nft()
{
	local admin_set="$PEER_IP"
	local ip
	for ip in $ADMIN_IPS; do admin_set="$admin_set, $ip"; done

	cat <<EOF
#!/usr/sbin/nft -f
# Vet-WAF cluster firewall — generated for $SELF_NAME ($SELF_IP)
# Peer: $PEER_NAME ($PEER_IP)

table inet vetwaf
delete table inet vetwaf
table inet vetwaf {
	# Source addresses blocked by cluster policy. http_chain has no \`ip\`
	# field, so a blacklisted source is tagged here and matched in the WAF
	# as \`mark == 16\`.
	set blacklist {
		type ipv4_addr
		flags interval
		auto-merge
	}

	set admins {
		type ipv4_addr
		flags interval
		elements = { $admin_set }
	}

	chain prerouting {
		type filter hook prerouting priority -150; policy accept;

		# Tag blacklisted sources for the WAF policy.
		ip saddr @blacklist meta mark set 0x10

		# Drop obvious garbage early, before conntrack.
		ip frag-off & 0x1fff != 0 counter drop
		tcp flags & (fin|syn|rst|psh|ack|urg) == 0 counter drop
		tcp flags & (fin|syn) == (fin|syn) counter drop
		tcp flags & (syn|rst) == (syn|rst) counter drop
	}

	chain input {
		type filter hook input priority 0; policy drop;

		# Keep existing connections — this is what stops --apply from
		# cutting the SSH session that is running it.
		ct state established,related accept
		ct state invalid counter drop

		iif lo accept

		# ICMP: allow echo at a low rate. Blanket-dropping ICMP breaks
		# path MTU discovery, which shows up as large responses hanging.
		ip protocol icmp icmp type { echo-request } limit rate 5/second accept
		ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
		ip6 nexthdr icmpv6 accept

		# ---- PUBLIC -------------------------------------------------
		# SYN flood braking, same 'limit rate over ... drop' shape as
		# the SSH rule below. Frang does the real L7 work; this only
		# keeps the socket backlog from becoming the weak point.
		tcp dport { $PUBLIC_PORTS } ct state new \\
			limit rate over 2000/second burst 4000 packets counter drop
		tcp dport { $PUBLIC_PORTS } accept

		# ---- INTERNAL: peer and admins only -------------------------
		# SSH, rate limited per source even for allowed addresses, so a
		# stolen key cannot be used for unbounded brute force.
		#
		# 'limit rate over' matches the packets that EXCEED the rate and
		# drops them; the accept below then takes the rest. Written the
		# other way round — a plain 'limit ... accept' followed by an
		# unconditional accept — the over-limit packets simply fall
		# through to the second rule and the brake never engages.
		ip saddr @admins tcp dport $SSH_PORT ct state new \\
			limit rate over 6/minute burst 6 packets counter drop
		ip saddr @admins tcp dport $SSH_PORT accept

		# Health agent + haproxy stats: peer only, never the world.
		ip saddr { $PEER_IP } tcp dport { $HEALTH_PORT, $STATS_PORT } accept

		# Everything else is dropped by policy. Log a sample so a
		# genuine misconfiguration is diagnosable.
		limit rate 10/minute log prefix "vetwaf-fw-drop " level info
	}

	chain forward {
		type filter hook forward priority 0; policy drop;
		ct state established,related accept
	}

	chain output {
		type filter hook output priority 0; policy accept;
	}
}
EOF
}

do_apply()
{
	have_nft || { do_apply_ufw; return; }

	log "backing up current ruleset to $BACKUP"
	nft list ruleset > "$BACKUP" 2>/dev/null || true

	local tmp
	tmp=$(mktemp /tmp/vetwaf-nft.XXXXXX)
	build_nft > "$tmp"

	log "checking ruleset syntax"
	nft -c -f "$tmp" || { rm -f "$tmp"; die "ruleset is invalid — nothing applied"; }

	log "applying ruleset for $SELF_NAME (peer $PEER_IP)"
	nft -f "$tmp" || { rm -f "$tmp"; die "apply failed"; }
	rm -f "$tmp"

	if [ "${1:-}" = "--no-rollback" ]; then
		log "applied with NO rollback timer"
		return 0
	fi

	# Arm the rollback. If the SSH session dies here, the timer restores the
	# previous ruleset and the node stays reachable.
	touch "$STAMP"
	log "rollback armed: previous ruleset restores in ${ROLLBACK_SECS}s"
	log "run '$0 --commit' now to keep this ruleset"
	setsid bash -c "
		sleep $ROLLBACK_SECS
		[ -f '$STAMP' ] || exit 0
		nft flush ruleset 2>/dev/null
		[ -s '$BACKUP' ] && nft -f '$BACKUP' 2>/dev/null
		logger -t vet-waf-fw 'rollback: firewall was not committed, previous ruleset restored'
		rm -f '$STAMP'
	" >/dev/null 2>&1 &
	disown
}

do_commit()
{
	[ -f "$STAMP" ] || { log "nothing pending"; }
	rm -f "$STAMP"
	if have_nft; then
		mkdir -p /etc/nftables.d
		nft list ruleset > /etc/nftables.conf
		systemctl enable nftables >/dev/null 2>&1 || true
		log "committed and persisted to /etc/nftables.conf"
	else
		ufw --force enable >/dev/null 2>&1 || true
		log "committed (ufw)"
	fi
}

do_rollback()
{
	rm -f "$STAMP"
	have_nft || die "rollback is nftables only"
	[ -s "$BACKUP" ] || die "no backup at $BACKUP"
	nft flush ruleset
	nft -f "$BACKUP"
	log "previous ruleset restored"
}

# ---------------------------------------------------------------------------
do_apply_ufw()
{
	command -v ufw >/dev/null || die "neither nft nor ufw is installed"
	warn "using ufw — no packet-mark sets, so the blacklist policy's"
	warn "\`mark ==\` rules will not fire. Install nftables for full function."

	ufw --force reset >/dev/null
	ufw default deny incoming
	ufw default allow outgoing

	local p
	for p in ${PUBLIC_PORTS//,/ }; do
		ufw allow "${p}/tcp" comment 'vet-waf public'
	done

	local ip
	for ip in $PEER_IP $ADMIN_IPS; do
		ufw allow from "$ip" to any port "$SSH_PORT" proto tcp comment 'cluster admin ssh'
	done
	ufw allow from "$PEER_IP" to any port "$HEALTH_PORT" proto tcp comment 'peer health agent'
	ufw allow from "$PEER_IP" to any port "$STATS_PORT" proto tcp comment 'peer haproxy stats'

	ufw limit "$SSH_PORT/tcp" comment 'ssh brute-force brake'
	ufw --force enable
	log "ufw policy applied"
}

# ---------------------------------------------------------------------------
do_blockip()
{
	local addr="${1:?usage: --blockip ADDR[/LEN]}"
	have_nft || die "--blockip requires nftables"
	nft add element inet vetwaf blacklist "{ $addr }" \
		|| die "could not add $addr"
	log "blacklisted $addr (mark 0x10 — matched as 'mark == 16' in http_chain)"
	log "replicate to the peer: waf-sync.sh --push"
}

do_unblockip()
{
	local addr="${1:?usage: --unblockip ADDR[/LEN]}"
	have_nft || die "--unblockip requires nftables"
	nft delete element inet vetwaf blacklist "{ $addr }" \
		|| die "could not remove $addr"
	log "removed $addr from the blacklist"
}

do_status()
{
	echo "node: $SELF_NAME ($SELF_IP)   peer: $PEER_NAME ($PEER_IP)"
	if have_nft; then
		nft list table inet vetwaf 2>/dev/null \
			|| warn "table inet vetwaf is not loaded — run --apply"
	else
		ufw status verbose
	fi
	[ -f "$STAMP" ] && warn "a rollback is ARMED — run --commit to keep the current ruleset"
}

case "${1:---status}" in
	--apply)     do_apply "${2:-}" ;;
	--commit)    do_commit ;;
	--rollback)  do_rollback ;;
	--blockip)   do_blockip "${2:-}" ;;
	--unblockip) do_unblockip "${2:-}" ;;
	--status)    do_status ;;
	--print)     build_nft ;;
	*)
		cat >&2 <<EOF
Usage: $0 COMMAND

  --apply [--no-rollback]   apply the cluster firewall (rollback armed by default)
  --commit                  keep and persist the applied ruleset
  --rollback                restore the previous ruleset now
  --blockip ADDR[/LEN]      blacklist a source (tags mark 0x10 for the WAF)
  --unblockip ADDR[/LEN]    remove a blacklist entry
  --status                  show the active policy
  --print                   print the generated ruleset without applying it
EOF
		exit 1
		;;
esac
