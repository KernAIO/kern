#!/usr/bin/env bash
# Back up a self-hosted Kern instance: the database, the object storage, and the configuration
# needed to rebuild the stack around them.
#
#   ./kern-backup.sh                 take a backup, prune old ones
#   ./kern-backup.sh --list          list the backups you have
#   ./kern-backup.sh --keep 30       keep 30 instead of the default 14
#   ./kern-backup.sh --to /mnt/nas   write somewhere other than ./backups
#
# This is not the same thing as an upgrade snapshot. `kern-upgrade.sh` snapshots the database and
# the compose files so a bad release can be undone in a hurry; it does NOT copy object storage,
# because that would make every upgrade wait on the size of the whole bucket. So a
# `kern-rollback.sh --database` can bring back rows that refer to files which are no longer there.
# This script is the one that captures both at the same moment, which is what you restore from when
# the disk fails rather than when a release did.
#
# Restoring is deliberately manual — see RESTORE.txt inside each backup.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

BACKUP_DIR="${KERN_BACKUP_DIR:-$DIR/backups}"
KEEP="${KERN_KEEP_BACKUPS:-14}"
LIST_ONLY=false

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    # The usage is the comment at the top of this file; print it rather than keep a second copy.
    -h|--help) sed -n '2,/^$/p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --list) LIST_ONLY=true ;;
    --keep) shift; [ $# -gt 0 ] || fail "--keep needs a number."; KEEP="$1" ;;
    --keep=*) KEEP="${1#--keep=}" ;;
    --to) shift; [ $# -gt 0 ] || fail "--to needs a directory."; BACKUP_DIR="$1" ;;
    --to=*) BACKUP_DIR="${1#--to=}" ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
  shift
done

case "$KEEP" in ''|*[!0-9]*) fail "--keep takes a number, not \"$KEEP\"." ;; esac

# Does this directory hold a database dump? That is the one artefact whose absence makes a copy
# worthless — everything else in a backup is written in a fraction of a second at the end of the
# run, so a directory holding the configuration and not the dump is exactly what an interrupted
# backup leaves behind. `PGDMP` is pg_dump's custom-format magic, so this rejects an empty file and
# a shell error message caught by the redirection alike.
#
# Deliberately only the dump: --list and the prune ask this of directories written by whatever
# version of this script was installed at the time, and a copy taken before object storage was
# mirrored is still a copy of the database. What *this* run must have produced is a longer list, and
# is checked separately just before publishing.
holds_a_dump() { # holds_a_dump <directory>
  [ -s "$1/database.dump" ] || return 1
  [ "$(head -c 5 "$1/database.dump" 2>/dev/null)" = "PGDMP" ] || return 1
  return 0
}

if [ "$LIST_ONLY" = true ]; then
  [ -d "$BACKUP_DIR" ] || fail "No backups in $BACKUP_DIR yet."
  # The same glob the prune uses, so what this lists and what that counts are the same set. A backup
  # in progress is a dot-prefixed `.<stamp>.partial` directory and matches neither.
  FOUND=false
  for d in "$BACKUP_DIR"/[0-9]*-[0-9]*/; do
    [ -d "$d" ] || continue
    FOUND=true
    if holds_a_dump "${d%/}"; then
      printf '%s\t%s\n' "$(du -sh "$d" | cut -f1)" "${d%/}"
    else
      # Said here rather than left for the night the restore is needed. Only a run of the script as
      # it stood before 2026-09-05 can have left one of these.
      printf '%s\t%s\t\033[33m⚠ no database dump — not a backup, and not counted\033[0m\n' \
        "$(du -sh "$d" | cut -f1)" "${d%/}"
    fi
  done
  [ "$FOUND" = true ] || fail "No backups in $BACKUP_DIR yet."
  exit 0
fi

[ -f .env ] || fail "No .env here. Run this from the directory that holds your docker-compose.yml."
[ -f docker-compose.yml ] || fail "No docker-compose.yml here."
command -v docker >/dev/null || fail "Docker is required."

compose() { docker compose "$@"; }
# Values are written single-quoted, because a password may contain `$`, `#` or a space and only a
# single-quoted .env value survives that. Strip one enclosing quote of either kind.
env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

compose ps --status running --quiet postgres >/dev/null 2>&1 || fail "Postgres is not running."

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/$STAMP"

# A half-written backup that looks finished is worse than none — and this one did look finished. The
# directory used to be created under its final name and never renamed, so a backup interrupted by the
# systemd timer's 6h TimeoutStartSec, a reboot or a Ctrl-C left a `<stamp>/` holding a truncated dump
# and no files at all. It sorted newest, `--list` showed it, and the prune counted it as a good copy
# while deleting a real one: fourteen nights of that and every backup on disk is the broken one.
#
# So everything is written to a dot-prefixed working directory and `mv`d into place only after
# RESTORE.txt exists. A dot prefix is what keeps it out of `--list` and out of the prune — both use
# globs that cannot match a leading dot — and `mv` within one directory is atomic, so the final name
# never exists in a partial state. The trap covers the signals; the exit path covers `fail`.
WORK="$BACKUP_DIR/.$STAMP.partial"
mkdir -p "$WORK" || fail "Could not create $WORK."

# `return 0` is load-bearing, not tidiness. Under `set -e` an EXIT trap whose last command fails
# takes the whole script's exit status with it, so a handler ending in a false test turns a
# completed backup into a non-zero exit — and systemd would mail the operator a failure every night
# for a backup that worked.
cleanup_failed() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; return 0; }

# A signal has to END the run, and until it did this script published the interrupted backup as a
# good one. `trap cleanup_failed EXIT INT TERM` ran the same handler for all three, and a signal
# handler that returns hands control back to the line after the one that was interrupted: the
# working directory had just been deleted, so the script carried on, `mkdir -p "$WORK/files"` made
# it again, the configuration was copied into it, and the publish moved a directory holding no
# database dump into place under a green "Backup complete". Worse than the truncated dump it
# replaced — that at least had rows in it — and the prune then deleted a real backup to keep it.
#
# So EXIT tidies up and the two signals tidy up and leave, 128+signal as a shell conventionally
# reports a death by one. The timer's 6h TimeoutStartSec sends TERM and a Ctrl-C sends INT; both
# now end with nothing published and a non-zero status, which is what systemd should see.
trap cleanup_failed EXIT
trap 'cleanup_failed; exit 130' INT
trap 'cleanup_failed; exit 143' TERM

# Sweep working directories an earlier run abandoned. Only ones untouched for a day, so a backup
# running right now in another shell is never touched.
find "$BACKUP_DIR" -maxdepth 1 -type d -name '.*.partial' -mtime +0 -exec rm -rf {} + 2>/dev/null || true

# ---------------------------------------------------------------- database

step "Dumping the database"
# -Fc is the custom format: compressed, and pg_restore can be selective on the way back. Taken as
# POSTGRES_USER (the superuser) rather than kern_app, so it includes every object regardless of
# owner and is not filtered by row-level security — a dump taken as kern_app would silently contain
# only the rows its policies let it see, which is the worst possible backup.
if ! compose exec -T postgres pg_dump \
      -U "$(env_value POSTGRES_USER)" -Fc "$(env_value POSTGRES_DB)" > "$WORK/database.dump"; then
  fail "The database dump failed. Nothing was kept."
fi
info "database.dump ($(du -h "$WORK/database.dump" | cut -f1))"

# ---------------------------------------------------------------- object storage

step "Mirroring object storage"
S3_BUCKET="$(env_value S3_BUCKET)"
S3_ACCESS_KEY="$(env_value S3_ACCESS_KEY)"
S3_SECRET_KEY="$(env_value S3_SECRET_KEY)"
S3_ENDPOINT="$(env_value S3_ENDPOINT)"

if compose ps --status running --quiet minio >/dev/null 2>&1; then
  mkdir -p "$WORK/files"
  # `mc mirror` into a mounted directory, run on the compose network so it reaches minio by name.
  # --overwrite --remove makes the copy match the bucket rather than accumulate: without --remove a
  # mirror only ever grows, and a "backup" that can never forget a deleted file is not a copy of
  # anything that existed.
  if compose run --rm --no-deps \
      -v "$WORK/files:/backup" \
      --entrypoint /bin/sh minio-init -c "
        mc alias set src '$S3_ENDPOINT' '$S3_ACCESS_KEY' '$S3_SECRET_KEY' >/dev/null &&
        mc mirror --overwrite --remove --quiet \"src/$S3_BUCKET\" /backup
      "; then
    info "files/ ($(du -sh "$WORK/files" | cut -f1))"
  else
    fail "The object storage mirror failed. Nothing was kept."
  fi
else
  # An instance pointed at an external S3 has nothing local to mirror, and copying somebody else's
  # bucket to this disk is not this script's business. Say so rather than leaving a silent gap.
  printf 'This instance uses external object storage at %s.\nIt is NOT in this backup; back it up where it lives.\n' \
    "$S3_ENDPOINT" > "$WORK/files-EXTERNAL.txt"
  info "object storage is external ($S3_ENDPOINT) — recorded, not copied"
fi

# ---------------------------------------------------------------- configuration

step "Copying the configuration"
cp .env "$WORK/.env"
cp docker-compose.yml "$WORK/docker-compose.yml"
[ -f Caddyfile ] && cp Caddyfile "$WORK/Caddyfile"
[ -f livekit.yaml ] && cp livekit.yaml "$WORK/livekit.yaml"
[ -d postgres-init ] && cp -R postgres-init "$WORK/postgres-init"
# .env holds every secret this instance has, so the backup is exactly as sensitive as .env is.
chmod -R go-rwx "$WORK"
info "configuration copied (.env included — treat this directory as a secret)"

cat > "$WORK/RESTORE.txt" <<EOS
Kern backup $STAMP
Version at the time: $(env_value KERN_VERSION)

Contents
  database.dump   pg_dump -Fc of the whole database
  files/          a mirror of the object storage bucket "$S3_BUCKET"
  .env            every secret this instance has. Keep this directory private.
  docker-compose.yml, Caddyfile, livekit.yaml, postgres-init/

To restore onto an empty host

1. Install Docker, then put this directory's .env, docker-compose.yml, Caddyfile and
   livekit.yaml into a new directory, and download the scripts:
       curl -fsSL https://raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh -o install.sh
   Do not run install.sh: it would generate new secrets. You already have them in .env.

2. Start only the infrastructure, so nothing migrates before the data is back:
       docker compose up -d postgres minio

3. Restore the database. db-init has not run yet, so create the role the dump expects first:
       docker compose up db-init
       docker compose exec -T postgres pg_restore -U $(env_value POSTGRES_USER) \\
           -d $(env_value POSTGRES_DB) --clean --if-exists < database.dump

4. Restore the files:
       docker compose run --rm --no-deps -v "\$PWD/files:/backup" --entrypoint /bin/sh minio-init \\
           -c "mc alias set dst '$S3_ENDPOINT' '<S3_ACCESS_KEY>' '<S3_SECRET_KEY>' &&
               mc mirror --overwrite /backup dst/$S3_BUCKET"
   The keys are in .env.

5. Start everything:
       docker compose up -d

The database and the files were captured a few seconds apart, not atomically. A file uploaded
during the backup may be in one and not the other.
EOS

# ---------------------------------------------------------------- publish

# Every part is now written, so the backup becomes a backup. Until this line there was nothing under
# a name anything else looks at; after it there is nothing under a name that is incomplete. Clearing
# the trap first is what stops the EXIT handler deleting the finished copy.
#
# Checked rather than assumed, and this is the second lock rather than the first: reaching here
# means no step reported a failure, which is exactly the claim an interrupted run was able to make
# while its dump had been deleted out from under it. A backup that cannot prove it holds a dump is
# not published — the run fails, the working directory goes, and the operator is told tonight
# instead of on the night they need it.
if ! holds_a_dump "$WORK" \
  || { [ ! -d "$WORK/files" ] && [ ! -f "$WORK/files-EXTERNAL.txt" ]; } \
  || [ ! -f "$WORK/RESTORE.txt" ]; then
  fail "$(printf '%s\n' \
    "This backup is missing something a restore needs, so it was NOT published:" \
    "" \
    "    database.dump   $(holds_a_dump "$WORK" && echo present || echo MISSING)" \
    "    files/          $({ [ -d "$WORK/files" ] || [ -f "$WORK/files-EXTERNAL.txt" ]; } && echo present || echo MISSING)" \
    "    RESTORE.txt     $([ -f "$WORK/RESTORE.txt" ] && echo present || echo MISSING)" \
    "" \
    "Nothing was kept, and the backups you already have are untouched. Run it again.")"
fi

mv "$WORK" "$DEST" || fail "Could not move $WORK into place as $DEST."
WORK=""
trap - EXIT INT TERM

# ---------------------------------------------------------------- prune

step "Pruning"
# Keep the newest $KEEP and no more, so backups cannot fill the disk on their own. Only directories
# that look like a stamp are considered, so nothing else in here is ever deleted — and a backup still
# being written is `.<stamp>.partial`, which this glob cannot match on either count.
#
# Counted, not merely listed: a directory that cannot be restored from does not fill one of the
# $KEEP places. Counting it did the real damage in the failure this script is built around — the
# broken copy sorts newest, so it took a place every night while a genuine backup was deleted to
# stay under the limit, and after $KEEP nights every copy on disk was the broken one. It is left
# where it is rather than deleted: it may hold an object storage mirror, and it is not this
# script's business to decide that for an operator who has not seen it yet.
mapfile -t STAMPED < <(ls -1d "$BACKUP_DIR"/[0-9]*-[0-9]*/ 2>/dev/null | sort -r)
KEPT=0
REMOVED=0
UNRESTORABLE=""
for dir in ${STAMPED[@]+"${STAMPED[@]}"}; do
  if ! holds_a_dump "${dir%/}"; then
    UNRESTORABLE="$UNRESTORABLE $(basename "${dir%/}")"
    continue
  fi
  KEPT=$((KEPT + 1))
  if [ "$KEPT" -gt "$KEEP" ]; then
    rm -rf "$dir"
    info "removed $(basename "${dir%/}")"
    REMOVED=$((REMOVED + 1))
  fi
done
[ "$REMOVED" -gt 0 ] || info "nothing to prune (keeping $KEEP)"
if [ -n "$UNRESTORABLE" ]; then
  printf '\n\033[33m⚠ These hold no database dump, so they are not backups and were not counted:\033[0m\n' >&2
  for dir in $UNRESTORABLE; do printf '      %s\n' "$BACKUP_DIR/$dir" >&2; done
  printf '  A run interrupted before 2026-09-05 left them. Delete them once you have looked.\n' >&2
fi

printf '\n\033[32m✔ Backup complete: %s (%s)\033[0m\n' "$DEST" "$(du -sh "$DEST" | cut -f1)"
printf '  Restoring is described in %s/RESTORE.txt\n\n' "$DEST"
