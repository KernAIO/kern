#!/usr/bin/env bash
# Go back to the version an upgrade snapshot was taken from.
#
#   ./kern-rollback.sh                          use the newest snapshot that records a version
#   ./kern-rollback.sh snapshots/1.1.0-to-1.2.0-20260822-140301
#   ./kern-rollback.sh <snapshot> --database    also restore the database
#   ./kern-rollback.sh <snapshot> --version X   go back to X, whatever the snapshot recorded
#
# Images roll back on their own. The database does not: migrations only go forwards. Within a minor
# release that is fine, because a migration must stay compatible with the image before it — so the
# older image runs against the newer schema. Across a release that changed the schema in a way it
# could not (the release notes say so), pass --database and accept losing what was written since the
# snapshot was taken.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

SNAPSHOT_DIR="${KERN_SNAPSHOT_DIR:-$DIR/snapshots}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

RESTORE_DB=false
SNAP=""
WANT_VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    # The usage is the comment at the top of this file; print it rather than keep a second copy.
    -h|--help) sed -n '2,/^$/p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --database) RESTORE_DB=true ;;
    --version) shift; [ $# -gt 0 ] || fail "--version needs a version, e.g. --version 1.2.0"; WANT_VERSION="$1" ;;
    --version=*) WANT_VERSION="${1#--version=}" ;;
    -*) fail "Unknown option: $1" ;;
    *) SNAP="$1" ;;
  esac
  shift
done

if [ -z "$SNAP" ]; then
  # The newest snapshot that can actually be rolled back to, not the newest directory. An upgrade
  # writes its stack-file diffs into this same directory as `stack-<stamp>/`, and creates it *after*
  # the snapshot — so `head -1` of `ls -1dt` picked one of those on every instance whose upgrade
  # touched a stack file, and this script then refused with "has no from-version file" while a
  # perfectly good snapshot sat beside it. install.sh prints `./kern-rollback.sh` as the way out of
  # a bad upgrade, so that is the documented recovery path failing.
  #
  # The test is the from-version file rather than the `*-to-*` naming the prune globs on: it is the
  # property the next line actually needs, so a snapshot from an older layout still qualifies and
  # anything else in here never does.
  CANDIDATES=0
  while IFS= read -r dir; do
    CANDIDATES=$((CANDIDATES + 1))
    [ -f "${dir}from-version" ] || continue
    SNAP="$dir"
    break
  done < <(ls -1dt "$SNAPSHOT_DIR"/*/ 2>/dev/null || true)
  if [ -z "$SNAP" ]; then
    [ "$CANDIDATES" -gt 0 ] \
      || fail "No snapshots in $SNAPSHOT_DIR. Pass one, or set KERN_VERSION in .env by hand."
    fail "$(printf '%s\n' \
      "Nothing in $SNAPSHOT_DIR records the version it was taken from." \
      "" \
      "An upgrade writes one; a stack-<stamp>/ directory is the diffs an upgrade left for you to" \
      "merge, not a snapshot. Pick a release from https://github.com/KernAIO/app/releases and pass" \
      "it instead:" \
      "" \
      "    ./kern-rollback.sh $SNAPSHOT_DIR/<snapshot> --version 1.2.0")"
  fi
fi
SNAP="${SNAP%/}"
[ -d "$SNAP" ] || fail "No such snapshot: $SNAP"
[ -f "$SNAP/from-version" ] || fail "$SNAP has no from-version file, so there is nothing to go back to."

env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

set_env() { # set_env <KEY> <literal value>, without sed's replacement parsing
  local tmp
  tmp="$(mktemp)" || fail "Could not create a temporary file."
  K="$1" V="$2" awk '
    BEGIN { key = ENVIRON["K"]; val = ENVIRON["V"]; done = 0 }
    !done && index($0, key "=") == 1 { print key "=" q val q; done = 1; next }
    { print }
    END { if (!done) print key "=" q val q }
  ' q="'" .env > "$tmp" && mv "$tmp" .env
}

FROM="$(tr -d '[:space:]' < "$SNAP/from-version")"
CURRENT="$(env_value KERN_VERSION)"
[ -z "$WANT_VERSION" ] || FROM="$WANT_VERSION"

# A moving tag is not somewhere to go back to. `latest` means "the newest release", which after the
# upgrade is the version you are trying to leave — so re-pinning it would pull the same images,
# report success, and change nothing at all. Say so instead of doing that.
case "$FROM" in
  latest|main|"")
    fail "$(printf '%s\n' \
      "This snapshot records from-version \"$FROM\", which is not a version." \
      "" \
      "\"latest\" moves: it now points at the release you are trying to leave, so putting it back" \
      "would pull the same images and change nothing while reporting success." \
      "" \
      "Pick the release you want from https://github.com/KernAIO/app/releases, then:" \
      "" \
      "    ./kern-rollback.sh $SNAP --version 1.2.0" \
      "" \
      "Newer instances record a real number here — install.sh pins one, and kern-upgrade.sh asks" \
      "core what it is running when .env still says \"latest\".")"
    ;;
esac

info "Now:        $CURRENT"
info "Going back to: $FROM"
info "Snapshot:   $SNAP"

step "Closing the API"
docker compose run --rm core node dist/migrate.js --maintenance on || info "could not close the API; carrying on"

if [ "$RESTORE_DB" = true ]; then
  [ -f "$SNAP/database.dump" ] || fail "$SNAP has no database.dump."
  printf '\n\033[31mThis replaces the database with the snapshot. Everything written since %s is lost.\033[0m\n' \
    "$(basename "$SNAP")"
  # Object storage is not in an upgrade snapshot, so the two go back to different moments: rows
  # restored from the dump can refer to files deleted since, and files uploaded since will have no
  # row pointing at them. ./kern-backup.sh is the one that captures both together.
  printf '\033[31mThe snapshot holds no files. Attachments uploaded since it was taken will be\n'
  printf 'orphaned, and rows it restores may point at objects that have since been deleted.\033[0m\n'
  confirm=""
  if [ -e /dev/tty ]; then
    printf 'Type the word restore to continue: '
    IFS= read -r confirm </dev/tty || confirm=""
  else
    fail "No terminal to confirm on. Run this from a terminal — it destroys data."
  fi
  [ "$confirm" = "restore" ] || fail "Nothing was changed."

  step "Restoring the database"
  docker compose stop core core-worker chat mail collab app >/dev/null 2>&1 || true
  docker compose exec -T postgres pg_restore \
    -U "$(env_value POSTGRES_USER)" \
    -d "$(env_value POSTGRES_DB)" \
    --clean --if-exists < "$SNAP/database.dump" || fail "The restore failed. The instance is down; fix this before starting it."
  info "database restored"
fi

step "Putting $FROM back"
set_env KERN_VERSION "$FROM"
docker compose pull
docker compose up -d

step "Opening the API again"
sleep 5
docker compose run --rm core node dist/migrate.js --maintenance off || info "could not clear maintenance mode; it expires on its own after 30 minutes"

printf '\n\033[32m✔ Kern is back on %s.\033[0m\n' "$FROM"
if [ "$RESTORE_DB" = false ]; then
  printf '  The database was left as it is. If the release changed the schema in a way the old\n'
  printf '  images cannot read, run this again with --database.\n\n'
fi
