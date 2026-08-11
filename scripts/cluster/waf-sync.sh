#!/bin/bash
#
# Vet-WAF — replicate WAF policy (blacklist, whitelist, ruleset) between nodes.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.  See LICENSE.
#
# Model: one node is the AUTHOR, the other is a REPLICA. You edit policy on
# the author only; the replica pulls. Both directions being writable is what
# produces split-brain rulesets, so this script deliberately refuses to push
# from a replica.
#
# Every change is a git commit in $WAF_SHARED_DIR, so `git log` is the audit
# trail and `git revert` is the rollback. rsync is the fallback transport when
# git is unavailable (--transport rsync).
#
# Usage (on the author):
#   waf-sync.sh --commit "block scanner range 203.0.113.0/24"
#   waf-sync.sh --push            # send to the peer and reload it
# On the replica:
#   waf-sync.sh --pull            # fetch, validate, reload
#   waf-sync.sh --status          # are the two nodes identical?
#

set -uo pipefail

CLUSTER_ENV=${CLUSTER_ENV:-/etc/vet_waf/cluster.env}
[ -f "$CLUSTER_ENV" ] || CLUSTER_ENV="$(dirname "$0")/cluster.env"
# shellcheck disable=SC1090
. "$CLUSTER_ENV"

# Which node may author changes. Override per-node in cluster.env if you
# promote the other one.
AUTHOR_IP=${AUTHOR_IP:-$NODE_A_IP}

SSH_OPTS=${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}
TRANSPORT=git

log()  { echo -e "\033[0;32m[sync]\033[0m $*"; }
warn() { echo -e "\033[0;33m[sync]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[sync]\033[0m $*" >&2; exit 1; }

cluster_identify || die "cannot identify this node"

is_author() { [ "$SELF_IP" = "$AUTHOR_IP" ]; }

# ---------------------------------------------------------------------------
# The replicated policy files. Each is a single file, not a glob directory:
# !include is expanded by scripts/vet_waf.sh with `find`, which returns
# directory order, and http_chain is first-match-wins — so a rule directory
# can evaluate in a different order on each node while looking identical.
# One file per concern keeps the order deterministic across both nodes.
# ---------------------------------------------------------------------------
POLICY_FILES="blacklist.conf whitelist.conf ruleset.conf"

ensure_repo()
{
	mkdir -p "$WAF_SHARED_DIR"
	if [ ! -d "$WAF_SHARED_DIR/.git" ]; then
		log "initialising policy repo at $WAF_SHARED_DIR"
		git -C "$WAF_SHARED_DIR" init -q
		git -C "$WAF_SHARED_DIR" config user.email "vet-waf@$SELF_NAME"
		git -C "$WAF_SHARED_DIR" config user.name  "Vet-WAF $SELF_NAME"
	fi

	local f
	for f in $POLICY_FILES; do
		[ -f "$WAF_SHARED_DIR/$f" ] || seed_policy "$f"
	done
}

seed_policy()
{
	local f="$WAF_SHARED_DIR/$1"
	log "seeding $1"
	case "$1" in
	blacklist.conf)
		cat > "$f" <<'EOF'
## Vet-WAF cluster policy — BLACKLIST
##
## Replicated to every node. Included from http_chain BEFORE the whitelist
## and the vhost routes, so a match here wins outright.
##
## Order matters: http_chain is first-match-wins.
##
## NOTE ON IP ADDRESSES: http_chain has no `ip` field. It matches on uri,
## host, hdr, mark, method and cookie only (see fw/http_tbl.c:206). To block
## by source address, mark the packet in nftables and match the mark here:
##
##   nft add element inet vetwaf blacklist { 203.0.113.0/24 }
##   mark == 16 -> block;
##
## waf-firewall.sh --blockip manages that nftables set for you.
##
## Syntax reminder:
##   hdr "User-Agent" == "*sqlmap*" -> block;
##   uri == "/wp-login.php*"        -> block;
##   mark == 16                     -> block;

# mark == 16 -> block;
EOF
		;;
	whitelist.conf)
		cat > "$f" <<'EOF'
## Vet-WAF cluster policy — WHITELIST
##
## Evaluated after the blacklist, before the ruleset. A match here routes
## straight to the vhost, skipping every ruleset check below it.
##
## Keep this short. Every entry here is traffic the WAF stops inspecting.
## As above, source addresses arrive as nftables marks, not as `ip ==`.

# mark == 32 -> firewall.hidev.dev;
EOF
		;;
	ruleset.conf)
		cat > "$f" <<'EOF'
## Vet-WAF cluster policy — RULESET
##
## Application-layer rules: scanners, probes, known-bad paths. Evaluated
## after blacklist and whitelist, before the normal host routes.

# hdr "User-Agent" == "*nikto*"   -> block;
# hdr "User-Agent" == "*sqlmap*"  -> block;
# hdr "User-Agent" == "*nmap*"    -> block;
# uri == "/.env"                  -> block;
# uri == "/.git/*"                -> block;
EOF
		;;
	esac
}

# ---------------------------------------------------------------------------
# Validate before anything is applied. A bad ruleset that reaches both nodes
# takes the whole cluster down, which is the one failure this design exists
# to prevent.
# ---------------------------------------------------------------------------
validate()
{
	# The kernel's grammar for an http_chain rule, mirrored here so a
	# policy that would be rejected reaches NEITHER node:
	#   - match fields: uri, host, hdr, mark, method, cookie
	#     (fw/http_tbl.c:206-214 — note there is no `ip` field)
	#   - a rule must terminate in a semicolon
	# A separate brace balance check catches a rule spanning two lines,
	# which no single-line regex will flag.
	local FIELDS='uri|host|hdr|mark|method|cookie'
	local rc=0 f line n open close

	for f in $POLICY_FILES; do
		local p="$WAF_SHARED_DIR/$f"
		[ -f "$p" ] || { warn "$f missing"; rc=1; continue; }

		open=$(grep -o '{' "$p" | wc -l)
		close=$(grep -o '}' "$p" | wc -l)
		if [ "$open" -ne "$close" ]; then
			warn "$f: unbalanced braces ($open open, $close close)"
			rc=1
		fi

		n=0
		while IFS= read -r line; do
			n=$((n + 1))
			# Skip blanks and comments.
			[[ -z "${line// }" || "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue

			# A bare default rule inside an included fragment would swallow
			# everything below it in the chain.
			if [[ "$line" =~ ^[[:space:]]*-\> ]]; then
				warn "$f:$n: unconditional default rule in an include" \
				     "— it would shadow every rule after it"
				rc=1
				continue
			fi

			# Every live rule must be a terminated http_chain rule.
			if [[ ! "$line" =~ -\>[[:space:]]*[A-Za-z0-9_.*-]+[[:space:]]*\;[[:space:]]*$ ]]; then
				warn "$f:$n: not a terminated rule: $line"
				rc=1
				continue
			fi

			# The match field must be one the kernel knows.
			if ! [[ "$line" =~ ^[[:space:]]*($FIELDS)[[:space:]] ]]; then
				warn "$f:$n: unknown match field (want uri|host|hdr|mark|method|cookie): $line"
				rc=1
			fi

			# The action target must exist: a block-ish action, a vhost in
			# the config, or a chain name. '-> block;' is the common case.
			local act
			act=$(sed -n 's/.*->[[:space:]]*\([A-Za-z0-9_.*\-]*\)[[:space:]]*;.*/\1/p' <<<"$line")
			if [ -n "$act" ] && [ "$act" != "block" ] \
			   && ! grep -Eq "vhost[[:space:]]+$act[[:space:]]*\{|^[[:space:]]*$act[[:space:]]*\{" \
			   "$WAF_SHARED_DIR"/../vet_waf.conf 2>/dev/null; then
				# The vhost may live in the WAF config which may be absent
				# at seed time on a fresh node — only warn, do not fail.
				warn "$f:$n: '$act' is not a vhost or chain in vet_waf.conf (assuming it will exist)"
			fi
		done < "$p"
	done
	[ $rc -eq 0 ] && log "policy validated" || warn "policy validation FAILED"
	return $rc
}

policy_digest()
{
	local f
	for f in $POLICY_FILES; do
		printf '%s ' "$f"
		sha256sum "$WAF_SHARED_DIR/$f" 2>/dev/null | awk '{print $1}' \
			|| echo missing
	done | sha256sum | awk '{print substr($1,1,16)}'
}

reload_waf()
{
	log "reloading Vet-WAF"
	if systemctl is-active --quiet vet-waf 2>/dev/null; then
		systemctl reload vet-waf && { log "reloaded"; return 0; }
		warn "systemctl reload failed"
		return 1
	fi
	if [ -x /lib/vet_waf/scripts/vet_waf.sh ]; then
		/lib/vet_waf/scripts/vet_waf.sh --reload && { log "reloaded"; return 0; }
	elif [ -x "$WAF_SRC/scripts/vet_waf.sh" ]; then
		"$WAF_SRC/scripts/vet_waf.sh" --reload && { log "reloaded"; return 0; }
	fi
	warn "Vet-WAF is not running — policy staged, will apply on next start"
	return 0
}

# ---------------------------------------------------------------------------
do_commit()
{
	local msg="${1:-policy update}"
	ensure_repo
	validate || die "refusing to commit an invalid policy"

	if git -C "$WAF_SHARED_DIR" diff --quiet && \
	   git -C "$WAF_SHARED_DIR" diff --cached --quiet && \
	   [ -z "$(git -C "$WAF_SHARED_DIR" ls-files -o --exclude-standard)" ]; then
		log "no policy changes to commit"
		return 0
	fi

	git -C "$WAF_SHARED_DIR" add -A
	git -C "$WAF_SHARED_DIR" commit -q -m "$msg" \
		|| die "commit failed"
	log "committed: $msg"
	git -C "$WAF_SHARED_DIR" log --oneline -1 | sed 's/^/    /'
}

do_push()
{
	is_author || die "this node ($SELF_NAME) is a replica. Edit policy on the author ($AUTHOR_IP) and pull here."
	ensure_repo
	validate || die "refusing to push an invalid policy"
	do_commit "policy sync from $SELF_NAME"

	log "pushing policy to $PEER_NAME ($PEER_IP)"
	# Back up the peer's current policy first so a bad push is recoverable
	# even if the peer's repo is somehow not in a clean state.
	ssh $SSH_OPTS -p "$SYNC_SSH_PORT" "root@$PEER_IP" \
		"mkdir -p '$WAF_SHARED_DIR' && \
		 tar -C '$WAF_SHARED_DIR' -czf /var/backups/vet-waf-policy-\$(date +%Y%m%d-%H%M%S).tgz . 2>/dev/null || true" \
		|| die "cannot reach $PEER_IP over SSH"

	if [ "$TRANSPORT" = git ]; then
		# Push into a bare mirror on the peer, then check it out there. A
		# direct push to a checked-out branch is refused by git.
		ssh $SSH_OPTS -p "$SYNC_SSH_PORT" "root@$PEER_IP" \
			"git init -q --bare '$WAF_SHARED_DIR.git' 2>/dev/null || true"
		git -C "$WAF_SHARED_DIR" push -q --force \
			"ssh://root@$PEER_IP:$SYNC_SSH_PORT$WAF_SHARED_DIR.git" \
			HEAD:refs/heads/main \
			|| die "git push failed"
		ssh $SSH_OPTS -p "$SYNC_SSH_PORT" "root@$PEER_IP" \
			"cd '$WAF_SHARED_DIR' && \
			 (git rev-parse --git-dir >/dev/null 2>&1 || git init -q) && \
			 git fetch -q '$WAF_SHARED_DIR.git' main && \
			 git checkout -q -f FETCH_HEAD -- . " \
			|| die "peer checkout failed"
	else
		local f
		for f in $POLICY_FILES; do
			rsync -a -e "ssh $SSH_OPTS -p $SYNC_SSH_PORT" \
				"$WAF_SHARED_DIR/$f" \
				"root@$PEER_IP:$WAF_SHARED_DIR/$f" \
				|| die "rsync of $f failed"
		done
	fi

	log "validating and reloading on $PEER_NAME"
	ssh $SSH_OPTS -p "$SYNC_SSH_PORT" "root@$PEER_IP" \
		"$0 --validate-and-reload" \
		|| die "peer rejected the policy — it kept its previous ruleset"

	do_status
}

do_pull()
{
	ensure_repo
	log "pulling policy from the author ($AUTHOR_IP)"
	[ "$SELF_IP" = "$AUTHOR_IP" ] && die "this node IS the author — nothing to pull"

	tar -C "$WAF_SHARED_DIR" -czf \
		"/var/backups/vet-waf-policy-$(date +%Y%m%d-%H%M%S).tgz" . 2>/dev/null

	local f
	for f in $POLICY_FILES; do
		rsync -a -e "ssh $SSH_OPTS -p $SYNC_SSH_PORT" \
			"root@$AUTHOR_IP:$WAF_SHARED_DIR/$f" \
			"$WAF_SHARED_DIR/$f" || die "rsync of $f failed"
	done

	validate || die "pulled policy is invalid — NOT reloading"
	do_commit "policy pulled from author $AUTHOR_IP"
	reload_waf
	do_status
}

do_status()
{
	local mine theirs
	mine=$(policy_digest)
	log "$SELF_NAME policy digest : $mine"

	theirs=$(ssh $SSH_OPTS -p "$SYNC_SSH_PORT" "root@$PEER_IP" \
		"cd '$WAF_SHARED_DIR' 2>/dev/null && for f in $POLICY_FILES; do printf '%s ' \$f; sha256sum \$f 2>/dev/null | awk '{print \$1}' || echo missing; done | sha256sum | awk '{print substr(\$1,1,16)}'" \
		2>/dev/null)

	if [ -z "$theirs" ]; then
		warn "$PEER_NAME unreachable — cannot compare"
		return 1
	fi
	log "$PEER_NAME policy digest : $theirs"

	if [ "$mine" = "$theirs" ]; then
		log "IN SYNC"
		return 0
	fi
	warn "OUT OF SYNC — run --push on the author ($AUTHOR_IP)"
	return 1
}

case "${1:---status}" in
	--commit)              do_commit "${2:-policy update}" ;;
	--push)                do_push ;;
	--pull)                do_pull ;;
	--validate)            validate ;;
	--validate-and-reload) validate && reload_waf ;;
	--status)              do_status ;;
	--init)                ensure_repo && validate && do_commit "seed cluster policy" ;;
	--transport)           TRANSPORT="${2:-git}"; shift 2; exec "$0" "$@" ;;
	*)
		echo "Usage: $0 {--init|--commit MSG|--push|--pull|--validate|--status}" >&2
		exit 1
		;;
esac
