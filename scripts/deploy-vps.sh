#!/bin/bash
#
# Vet-WAF — stage a source tree onto a VPS over SSH.
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
# This script only STAGES. It copies sources and the edge config to the VPS
# and stops. It never loads a module, never touches a running proxy, and never
# switches traffic — that is the cutover script's job, run separately and
# deliberately after a reboot onto the patched kernel.
#
# Usage:
#   scripts/deploy-vps.sh                  # dry run, shows what would change
#   scripts/deploy-vps.sh --apply          # actually copy
#   VETWAF_HOST=root@1.2.3.4 ... --apply   # override the target
#

set -euo pipefail

TFW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

host=${VETWAF_HOST:-root@185.113.223.17}
remote_src=${VETWAF_REMOTE_SRC:-/usr/src/vet_waf}
remote_cfg=${VETWAF_REMOTE_CFG:-/etc/vet_waf}
local_cfg=${VETWAF_LOCAL_CFG:-etc/vet_waf.vps.conf}
ssh_opts=${VETWAF_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}

dry_run=1
[ "${1:-}" = "--apply" ] && dry_run=0

log()  { echo -e "\033[0;32m[deploy]\033[0m $*"; }
warn() { echo -e "\033[0;33m[deploy]\033[0m $*" >&2; }
die()  { echo -e "\033[0;31m[deploy]\033[0m $*" >&2; exit 1; }

[ -f "$TFW_ROOT/$local_cfg" ] || die "missing $local_cfg in $TFW_ROOT"

# Never ship build output or local state: the modules must be compiled on the
# VPS against its own running kernel, or insmod will reject them on vermagic.
rsync_excludes=(
	--exclude '.git'
	--exclude '*.ko'
	--exclude '*.o'
	--exclude '*.mod'
	--exclude '*.mod.c'
	--exclude '*.cmd'
	--exclude 'Module.symvers'
	--exclude 'modules.order'
	--exclude '.tmp_versions'
	--exclude 'etc/vet_waf_tmp.conf'
	--exclude 'tempesta_db_*'
)

rsync_flags=(-az --delete --human-readable --info=stats1)
[ $dry_run -eq 1 ] && rsync_flags+=(--dry-run --itemize-changes)

log "target      : $host"
log "sources     : $TFW_ROOT/ -> $remote_src/"
log "edge config : $local_cfg -> $remote_cfg/vet_waf.conf"
[ $dry_run -eq 1 ] && warn "DRY RUN — nothing will be written. Re-run with --apply."

ssh $ssh_opts "$host" true 2>/dev/null \
	|| die "cannot reach $host over SSH (key auth, BatchMode). Check the key."

if [ $dry_run -eq 0 ]; then
	ssh $ssh_opts "$host" "mkdir -p '$remote_src' '$remote_cfg'"
fi

log "syncing sources..."
rsync "${rsync_flags[@]}" "${rsync_excludes[@]}" \
	-e "ssh $ssh_opts" \
	"$TFW_ROOT/" "$host:$remote_src/"

# The config is copied separately and NOT deleted by --delete, so a config
# hand-edited on the VPS is only ever replaced on an explicit apply, and a
# timestamped backup is kept so the previous edge policy can be restored.
log "syncing edge config..."
if [ $dry_run -eq 0 ]; then
	ssh $ssh_opts "$host" "
		set -e
		if [ -f '$remote_cfg/vet_waf.conf' ]; then
			cp -a '$remote_cfg/vet_waf.conf' \
			   '$remote_cfg/vet_waf.conf.bak.\$(date +%Y%m%d-%H%M%S)'
		fi"
fi
rsync "${rsync_flags[@]}" -e "ssh $ssh_opts" \
	"$TFW_ROOT/$local_cfg" "$host:$remote_cfg/vet_waf.conf"

log "installing cutover script..."
rsync "${rsync_flags[@]}" -e "ssh $ssh_opts" \
	"$TFW_ROOT/scripts/vetwaf-cutover.sh" "$host:/root/vetwaf-cutover.sh"
if [ $dry_run -eq 0 ]; then
	ssh $ssh_opts "$host" "chmod 0700 /root/vetwaf-cutover.sh"
fi

if [ $dry_run -eq 1 ]; then
	warn "dry run complete — no changes made"
	exit 0
fi

log "staged. Nothing is running yet. Next, on the VPS:"
cat <<EOF

  ssh $host
  cd $remote_src && make            # build against the RUNNING kernel
  uname -r                          # must be the patched 6.12.12 kernel
  /root/vetwaf-cutover.sh --check   # validate without switching traffic
  /root/vetwaf-cutover.sh --cutover # tear down the legacy proxy, go live

EOF
