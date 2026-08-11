#!/bin/bash
#
# Vet-WAF — health agent. Answers haproxy's agent-check on $HEALTH_PORT.
#
# Copyright (C) 2015-2026 Vet-WAF
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.  See LICENSE.
#
# Why an agent and not a plain HTTP check: haproxy's `check` only proves the
# socket answers. Vet-WAF can be listening while its origin link is down, or
# be in state=stop with something else holding the port — both serve errors
# to real users while passing a naive TCP check. This agent inspects the
# module state, the origin connections in perfstat, and a real proxied
# request, then reports a weight haproxy acts on.
#
# haproxy agent-check protocol: a single line, then close.
#   "up ready"    — take traffic
#   "down#reason" — eject this node
#   "100%"/"0%"   — relative weight
#
# Run under systemd via waf-health.service (socket-activated by xinetd-style
# per-connection invocation, or standalone with --serve).
#

set -uo pipefail

CLUSTER_ENV=${CLUSTER_ENV:-/etc/vet_waf/cluster.env}
[ -f "$CLUSTER_ENV" ] || CLUSTER_ENV="$(dirname "$0")/cluster.env"
# shellcheck disable=SC1090
. "$CLUSTER_ENV"

PERFSTAT=/proc/vet_waf/perfstat

# ---------------------------------------------------------------------------
# Returns 0 and echoes an haproxy agent line.
# ---------------------------------------------------------------------------
health_verdict()
{
	local state conns code

	# 1. Is the engine actually started? state=stop means the modules are
	#    loaded but not serving — a TCP check on :80 could still succeed if
	#    something else grabbed the port, which is exactly the case that
	#    silently serves the wrong site.
	state=$(sysctl -n net.vet_waf.state 2>/dev/null)
	if [ -z "$state" ]; then
		echo "down#vet-waf-not-loaded"
		return 0
	fi
	if [ "$state" != "start" ]; then
		echo "down#vet-waf-state-$state"
		return 0
	fi

	# 2. Is the origin link up? Vet-WAF answers on the socket even with every
	#    backend connection dead; those requests become 502s. Ejecting the
	#    node here sends users to the peer instead.
	if [ -r "$PERFSTAT" ]; then
		conns=$(awk -F':' '/^Server connections active/ {gsub(/[^0-9]/,"",$2); print $2; exit}' \
			"$PERFSTAT" 2>/dev/null)
		if [ -n "$conns" ] && [ "$conns" -eq 0 ] 2>/dev/null; then
			echo "down#origin-unreachable"
			return 0
		fi
	else
		echo "down#perfstat-missing"
		return 0
	fi

	# 3. Does a real request survive the whole path? Host header is required:
	#    http_strict_host_checking is on and the chain ends in `-> block`, so
	#    a hostless probe is dropped by design and would look like an outage.
	code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 \
		-H "Host: $CLUSTER_DOMAIN" \
		"http://127.0.0.1:$WAF_PORT/" 2>/dev/null)
	case "$code" in
	""|000)  echo "down#no-response"        ; return 0 ;;
	5*)      echo "down#backend-$code"      ; return 0 ;;
	esac

	# 4. Degrade rather than eject under memory pressure: still serving, but
	#    prefer the peer while this node recovers.
	local mem_avail mem_total pct
	mem_avail=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
	mem_total=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
	if [ -n "$mem_avail" ] && [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
		pct=$(( mem_avail * 100 / mem_total ))
		if [ "$pct" -lt 10 ]; then
			echo "50%"
			return 0
		fi
	fi

	echo "up ready"
}

case "${1:---once}" in
--once)
	health_verdict
	;;
--serve)
	# Standalone listener, bound to the private address only so the health
	# port is never reachable from the internet even if the firewall is
	# misconfigured. One line per connection, then close.
	command -v socat >/dev/null || {
		echo "socat is required for --serve (apt install socat)" >&2
		exit 1
	}
	cluster_identify || exit 1
	exec socat -T2 \
		"TCP-LISTEN:$HEALTH_PORT,bind=$SELF_IP,reuseaddr,fork" \
		"EXEC:$0 --once"
	;;
--check)
	# Human-readable: what would the agent say, and why.
	v=$(health_verdict)
	echo "verdict: $v"
	echo "state  : $(sysctl -n net.vet_waf.state 2>/dev/null || echo not-loaded)"
	[ -r "$PERFSTAT" ] && \
		grep -E '^(Server connections active|Client messages forwarded)' "$PERFSTAT" \
		| sed -e 's/\t\+/ /g' -e 's/^/         /'
	[ "$v" = "up ready" ] && exit 0 || exit 1
	;;
*)
	echo "Usage: $0 {--once|--serve|--check}" >&2
	exit 1
	;;
esac
