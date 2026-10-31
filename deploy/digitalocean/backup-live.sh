#!/usr/bin/env bash
# Installed at /usr/local/sbin/paintball-backup-live.sh; run nightly by paintball-backup.timer.
# Tars the live profile/clout data (DATA_DIR) and keeps 14 days of archives.
set -euo pipefail
SRC=/var/lib/paintball/live
DEST=/var/backups/paintball
KEEP_DAYS=14
mkdir -p "$DEST" && chmod 0700 "$DEST"
[ -d "$SRC" ] || { echo "no $SRC yet; nothing to back up"; exit 0; }
OUT="$DEST/live-$(date +%Y%m%d).tar.gz"
tar -czf "$OUT.tmp" -C /var/lib/paintball live
mv -f "$OUT.tmp" "$OUT"
chmod 0600 "$OUT"
find "$DEST" -maxdepth 1 -name 'live-*.tar.gz' -mtime +$((KEEP_DAYS - 1)) -delete
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)); $(ls "$DEST"/live-*.tar.gz | wc -l) archive(s) kept"
