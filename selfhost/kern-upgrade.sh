#!/usr/bin/env bash
# Upgrade a self-hosted Kern instance.
#
#   ./kern-upgrade.sh              upgrade to the newest stable release
#   ./kern-upgrade.sh 1.2.0        upgrade to a specific version
#   ./kern-upgrade.sh --check      run the preflight checks and stop
#   ./kern-upgrade.sh --auto       upgrade only if the instance's own policy says to
#   ./kern-upgrade.sh --stack-files  bring docker-compose.yml, Caddyfile and postgres-init/
#                                    forward and stop, without touching the running stack
#
# `--auto` is what the timer runs. It asks Kern whether it may proceed — the policy, the window and
# the settling period all live in the instance, set by an admin in Admin -> Updates — and does
# nothing at all unless the answer is yes. That way the panel and the job at 03:00 cannot disagree.
#
# Nothing here is clever. It refuses to start when the instance is not in a state to be upgraded,
# takes a snapshot you can go back to, closes the API while migrations run, and checks that every
# service came back on the new version. If any step fails it stops and prints how to undo it.
set -euo pipefail

DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

SNAPSHOT_DIR="${KERN_SNAPSHOT_DIR:-$DIR/snapshots}"
KEEP_SNAPSHOTS="${KERN_KEEP_SNAPSHOTS:-5}"
FEED_URL="${KERN_FEED_URL:-https://github.com/KernAIO/app/releases/latest/download/releases.json}"

step()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
fail()  { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

CHECK_ONLY=false
AUTO=false
STACK_ONLY=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --auto) AUTO=true ;;
    --stack-files) STACK_ONLY=true ;;
    -*) fail "Unknown option: $arg" ;;
    *) TARGET="$arg" ;;
  esac
done

[ -f .env ] || fail "No .env here. Run this from the directory that holds your docker-compose.yml."
[ -f docker-compose.yml ] || fail "No docker-compose.yml here."
# --stack-files only reads and writes files in this directory, so it does not need a Docker at all.
[ "$STACK_ONLY" = true ] || command -v docker >/dev/null || fail "Docker is required."

# --auto runs unattended on a timer, so it says nothing on the ordinary "nothing to do" path.
if [ "$AUTO" = true ]; then
  step() { :; }
  info() { :; }
fi

compose() { docker compose "$@"; }
# Values are written single-quoted (a password may contain `$`, `#` or a space, and only a
# single-quoted .env value survives that), so strip one enclosing quote of either kind.
env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

# Write a value into .env without going through sed's replacement parsing, where `&`, `|` and `\`
# are syntax. Same helper as install.sh's, for the same reason.
set_env() { # set_env <KEY> <literal value>
  local tmp
  tmp="$(mktemp)" || fail "Could not create a temporary file."
  K="$1" V="$2" awk '
    BEGIN { key = ENVIRON["K"]; val = ENVIRON["V"]; done = 0 }
    !done && index($0, key "=") == 1 { print key "=" q val q; done = 1; next }
    { print }
    END { if (!done) print key "=" q val q }
  ' q="'" .env > "$tmp" && mv "$tmp" .env
}

# ---------------------------------------------------------------- the release's stack files
#
# Until 2026-09-05 an upgrade changed KERN_VERSION and pulled images, and nothing else. install.sh
# downloads a distribution file only when it is absent (`[ -f "$f" ] || curl`), so an instance kept
# the docker-compose.yml, Caddyfile and postgres-init/ it was installed with for ever. Every fix that
# lives in one of those files reached new installs only — the MCP Caddy route never arrived, a blank
# KERN_SIGNUP= kept core from booting after the very release that fixed it, and MAIL_WEBHOOK_TOKEN
# was passed to a mail service by a compose file the instance did not have.
#
# So the upgrade brings them forward. It cannot simply overwrite: an operator is invited by the
# Caddyfile's own comments to add a site block, and a stack file is theirs to edit. The way to tell an
# operator's edit from a release's change is to fetch BOTH versions and compare:
#
#   live == release(TARGET)    already current, nothing to do
#   live == release(CURRENT)   untouched since install, safe to replace
#   anything else              the operator edited it, or we cannot prove they did not — leave it
#                              alone, print the diff they need, and do not report the upgrade as
#                              having delivered everything
#
# KERN_RAW_BASE exists so this is testable: point it at a directory laid out as <ref>/selfhost/<file>
# and no network is involved. CI does exactly that.
# What an upgrade brings forward. `.env.example` is in here because it is the only place a new
# optional key is ever described, and an instance that never refreshes it cannot discover one.
# kern-backup.sh and kern-rollback.sh are here because a fix to either of them otherwise reaches new
# installs only, which is the whole disease this section treats.
#
# kern-upgrade.sh is deliberately NOT in the list: bash reads a script incrementally as it runs, so
# rewriting this file underneath itself executes whatever lands at the byte offset the interpreter
# had reached. It is offered at the end instead, for the operator to install between runs.
STACK_FILES="docker-compose.yml Caddyfile postgres-init/01-extensions.sql .env.example kern-backup.sh kern-rollback.sh"
RAW_BASE="${KERN_RAW_BASE:-https://raw.githubusercontent.com/KernAIO/app}"

# Where diffs and replaced originals are kept. Created only when there is something to put in it.
STACK_KEEP="$SNAPSHOT_DIR/stack-$(date +%Y%m%d-%H%M%S)"

INCOMING="$(mktemp -d)" || fail "Could not create a temporary directory."
# `|| true` because an EXIT trap whose last command fails takes the script's exit status with it,
# which would turn a clean upgrade into a reported failure.
trap 'rm -rf "$INCOMING" 2>/dev/null || true' EXIT

fetch_stack_file() { # fetch_stack_file <ref> <relative path> <destination>
  mkdir -p "$(dirname "$3")"
  case "$RAW_BASE" in
    /*|./*|../*)  [ -f "$RAW_BASE/$1/selfhost/$2" ] && cp "$RAW_BASE/$1/selfhost/$2" "$3" ;;
    file://*)     [ -f "${RAW_BASE#file://}/$1/selfhost/$2" ] && cp "${RAW_BASE#file://}/$1/selfhost/$2" "$3" ;;
    *)            curl -fsSL "$RAW_BASE/$1/selfhost/$2" -o "$3" 2>/dev/null ;;
  esac
}

# Filled in by classify_stack_files. Space-separated lists of paths.
STACK_UPDATE=""
STACK_BLOCKED=""

classify_stack_files() {
  local f live_target live_current
  for f in $STACK_FILES; do
    fetch_stack_file "v$TARGET" "$f" "$INCOMING/target/$f" || true
    fetch_stack_file "v$CURRENT" "$f" "$INCOMING/current/$f" || true

    if [ ! -f "$INCOMING/target/$f" ]; then
      # Nothing to compare against. A release that genuinely dropped a file looks the same as a
      # network failure from here, and guessing which is which is how a stack loses its Caddyfile.
      STACK_BLOCKED="$STACK_BLOCKED $f"
      info "$f: could not fetch it from release $TARGET — left as it is"
      continue
    fi
    if [ ! -f "$f" ]; then
      STACK_UPDATE="$STACK_UPDATE $f"   # the release added it; the instance has never had it
      continue
    fi

    cmp -s "$f" "$INCOMING/target/$f" && live_target=yes || live_target=no
    if [ "$live_target" = yes ]; then continue; fi   # already what the release ships

    if [ -f "$INCOMING/current/$f" ]; then
      cmp -s "$f" "$INCOMING/current/$f" && live_current=yes || live_current=no
    else
      live_current=unknown
    fi

    case "$live_current" in
      yes) STACK_UPDATE="$STACK_UPDATE $f" ;;
      *)   STACK_BLOCKED="$STACK_BLOCKED $f" ;;
    esac
  done
}

# Write out what an operator has to apply by hand for each file we refused to touch, and say so in a
# way that cannot be mistaken for success. Deliberately printf/cat rather than step/info: those two
# are silenced under --auto, and this is the one thing an unattended run must never swallow.
report_blocked_stack_files() {
  local f
  [ -n "$STACK_BLOCKED" ] || return 0
  mkdir -p "$STACK_KEEP"
  for f in $STACK_BLOCKED; do
    if [ -f "$INCOMING/target/$f" ]; then
      cp "$INCOMING/target/$f" "$STACK_KEEP/$(basename "$f").from-$TARGET" 2>/dev/null || true
      if [ -f "$INCOMING/current/$f" ]; then
        diff -u "$INCOMING/current/$f" "$INCOMING/target/$f" \
          > "$STACK_KEEP/$(basename "$f").diff" 2>/dev/null || true
      else
        diff -u "$f" "$INCOMING/target/$f" > "$STACK_KEEP/$(basename "$f").diff" 2>/dev/null || true
      fi
    fi
  done

  printf '\n\033[33m⚠ These files were NOT brought forward to %s:\033[0m\n' "$TARGET" >&2
  for f in $STACK_BLOCKED; do printf '      %s\n' "$f" >&2; done
  cat >&2 <<EOS

  Each one differs from the copy release $CURRENT shipped — so it has local edits — or that copy
  could not be fetched and an edit cannot be ruled out. Replacing it would throw away work that is
  not ours to throw away.

  What release $TARGET changed, and the files it ships, are here:

      $STACK_KEEP

  Merge each .diff into your copy and then run: docker compose up -d

EOS
  logger -t kern-auto-update "stack files not brought forward:$STACK_BLOCKED" 2>/dev/null || true
}

apply_stack_files() {
  local f
  [ -n "$STACK_UPDATE" ] || return 0
  mkdir -p "$STACK_KEEP"
  for f in $STACK_UPDATE; do
    if [ -f "$f" ]; then
      mkdir -p "$STACK_KEEP/$(dirname "$f")"
      cp "$f" "$STACK_KEEP/$f" || fail "Could not back up $f before replacing it."
    fi
    mkdir -p "$(dirname "$f")"
    cp "$INCOMING/target/$f" "$f" || fail "Could not write $f."
    # curl writes 644, and `cp` over an existing file keeps that file's mode — so a script arriving
    # here for the first time would land unexecutable.
    case "$f" in *.sh) chmod +x "$f" ;; esac
    info "$f is now the copy release $TARGET ships"
  done
  info "the previous copies are in $STACK_KEEP"
}

# kern-upgrade.sh cannot replace itself while it is running (bash reads a script incrementally), so
# the new one is fetched beside the old and the operator is told how to install it. Silent when there
# is nothing newer, which is the common case.
offer_new_upgrade_script() {
  fetch_stack_file "v$TARGET" kern-upgrade.sh "$INCOMING/kern-upgrade.sh" || return 0
  [ -f "$INCOMING/kern-upgrade.sh" ] || return 0
  cmp -s kern-upgrade.sh "$INCOMING/kern-upgrade.sh" && return 0
  cp "$INCOMING/kern-upgrade.sh" kern-upgrade.sh.new || return 0
  chmod +x kern-upgrade.sh.new
  printf '\n  Release %s ships a newer kern-upgrade.sh. This one could not replace itself while it\n' "$TARGET"
  printf '  was running, so it is saved beside it. To use it from now on:\n\n'
  printf '      mv %s/kern-upgrade.sh.new %s/kern-upgrade.sh\n' "$DIR" "$DIR"
}

# Put back what apply_stack_files replaced. Used when the new compose file will not parse, which is
# the one failure that would otherwise leave the instance unable to run any docker compose command.
restore_stack_files() {
  local f
  for f in $STACK_UPDATE; do
    [ -f "$STACK_KEEP/$f" ] && cp "$STACK_KEEP/$f" "$f"
  done
}

# ---------------------------------------------------------------- .env repairs
#
# A key that is present in .env but blank is not the same as a key that is absent, and Compose's
# pass-through form depends on the difference: a bare `KERN_SIGNUP:` in docker-compose.yml passes the
# variable only when it is set, but `KERN_SIGNUP=` in .env *is* a value — the empty string. core
# parses it with `z.enum(['open','invite']).optional()`, which answers "Invalid option" for '' rather
# than reading it as absent, and throws before :4000 is bound. core-worker, chat, mail and collab all
# wait on core being healthy, so the whole stack stays down.
#
# .env.example carried that blank line for a while, so instances installed in that window have one.
# Commenting it out is the repair — and it has to happen here, because the compose file that makes
# the pass-through work is itself something only this script now delivers.
env_blank() { # env_blank <KEY> -> 0 when the key is present and its value is empty
  grep -qE "^$1=" .env && [ -z "$(env_value "$1")" ]
}

comment_out_blank_env() { # comment_out_blank_env <KEY>
  local tmp
  tmp="$(mktemp)" || fail "Could not create a temporary file."
  K="$1" awk '
    BEGIN { key = ENVIRON["K"]; done = 0 }
    !done && index($0, key "=") == 1 {
      v = substr($0, length(key) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v == "" || v == q q || v == "\"\"") { print "#" $0; done = 1; next }
    }
    { print }
  ' q="'" .env > "$tmp" && mv "$tmp" .env
}

# Ask a running service what version it is actually on. The images are node:24-slim — no wget, no
# curl — and every service listens on IPv4 only, so `localhost` resolves to ::1 and is refused.
# `node -e fetch(127.0.0.1)` is the shape the Dockerfile HEALTHCHECK uses and the only one that works.
reported_version() { # reported_version <service> <port>
  compose exec -T "$1" node -e "
    fetch('http://127.0.0.1:$2/api/health')
      .then(r => r.json()).then(j => console.log(j.version)).catch(() => console.log(''))
  " 2>/dev/null | tr -d '[:space:]'
}

wait_ready() { # wait_ready <service> <port> <attempts, 2s apart>
  local _attempt
  for _attempt in $(seq 1 "$3"); do
    if compose exec -T "$1" node -e "
      fetch('http://127.0.0.1:$2/api/ready')
        .then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))
    " >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

CURRENT="$(env_value KERN_VERSION)"
[ -n "$CURRENT" ] || fail "KERN_VERSION is not set in .env."

# ---------------------------------------------------------------- what the instance says

if [ "$AUTO" = true ]; then
  PLAN="$(compose exec -T core node dist/updates-cli.js plan 2>/dev/null | sed -n '/^{/,$p')" \
    || fail "Could not ask Kern whether to upgrade. Is it running?"
  SHOULD="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["shouldUpgrade"])' 2>/dev/null || echo False)"
  REASON="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reason"])' 2>/dev/null || echo "unreadable plan")"
  if [ "$SHOULD" != "True" ]; then
    logger -t kern-auto-update "not upgrading: $REASON" 2>/dev/null || true
    exit 0
  fi
  TARGET="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
  logger -t kern-auto-update "upgrading to $TARGET" 2>/dev/null || true
fi

# ---------------------------------------------------------------- target version

if [ -z "$TARGET" ]; then
  step "Asking which release is newest"
  if ! command -v curl >/dev/null; then fail "curl is required to look up the newest release."; fi
  # The feed is a signed document; the instance verifies the signature, this only needs the number.
  TARGET="$(curl -fsSL "$FEED_URL" \
    | python3 -c 'import base64,json,sys; d=json.load(sys.stdin); f=json.loads(base64.b64decode(d["payload"])); print(sorted((r["version"] for r in f["releases"] if r["channel"]=="stable"), key=lambda v: [int(p) for p in v.split("-")[0].split(".")])[-1])' \
    2>/dev/null)" || fail "Could not read the release feed at $FEED_URL. Pass a version instead: ./kern-upgrade.sh 1.2.0"
  [ -n "$TARGET" ] || fail "The release feed had no stable release in it."
fi

info "Now:      $CURRENT"
info "Upgrading to: $TARGET"
[ "$CURRENT" != "$TARGET" ] || fail "This instance is already on $TARGET."

# ---------------------------------------------------------------- stack files, on their own

# `--stack-files` is the whole file-refresh and nothing else: no images, no migrations, no downtime.
# It exists for two reasons — an operator who wants the new compose file before upgrading can have
# it, and it is the seam CI drives to prove the refresh works without standing up a Kern.
if [ "$STACK_ONLY" = true ]; then
  step "Bringing the stack files release $TARGET ships forward"
  classify_stack_files
  apply_stack_files
  if [ -n "$STACK_BLOCKED" ]; then
    report_blocked_stack_files
    exit 1
  fi
  [ -n "$STACK_UPDATE" ] || info "every stack file already matches release $TARGET"
  printf '\n\033[32m✔ Stack files are release %s. The running stack was not touched.\033[0m\n' "$TARGET"
  offer_new_upgrade_script
  printf '\n'
  exit 0
fi

# ---------------------------------------------------------------- preflight

step "Preflight"

compose config >/dev/null || fail "docker-compose.yml is not valid. Fix it before upgrading."
info "compose file is valid"

# An instance installed before the services stopped connecting as the database superuser has no
# KERN_DB_APP_PASSWORD, and .env is never rewritten by an upgrade. Left empty, db-init would set
# kern_app's password to nothing and every service would then fail to authenticate — so fill it in
# here rather than let the upgrade take the instance down. db-init applies it on the next `up`.
if [ -z "$(env_value KERN_DB_APP_PASSWORD)" ]; then
  command -v openssl >/dev/null || fail "openssl is needed to generate KERN_DB_APP_PASSWORD. Set it in .env by hand."
  set_env KERN_DB_APP_PASSWORD "$(openssl rand -hex 32)"
  info "generated KERN_DB_APP_PASSWORD (the services stop connecting as the database superuser)"
fi

# Same shape, same reason: an instance installed before the mail webhooks required a shared secret
# has no MAIL_WEBHOOK_TOKEN, and .env is never rewritten by an upgrade. Mail refuses every webhook
# while it is empty, so bounce and complaint handling would silently stop at this upgrade.
#
# This only reaches an instance whose docker-compose.yml passes MAIL_WEBHOOK_TOKEN to the mail
# service. An upgrade does not re-download the compose file, so an older instance needs the new one
# from the release before the variable is read at all — see the upgrade notes.
if [ -z "$(env_value MAIL_WEBHOOK_TOKEN)" ]; then
  command -v openssl >/dev/null || fail "openssl is needed to generate MAIL_WEBHOOK_TOKEN. Set it in .env by hand."
  set_env MAIL_WEBHOOK_TOKEN "$(openssl rand -hex 32)"
  info "generated MAIL_WEBHOOK_TOKEN — re-point your provider's webhooks at the new ?token= value"
fi

# The other half of the .env problem, and the opposite shape: not a key that is missing, but a key
# that is present and blank where the stack needs it absent. See comment_out_blank_env above —
# `KERN_SIGNUP=` is an empty string to core, not an absence, and it stops core booting.
if env_blank KERN_SIGNUP; then
  comment_out_blank_env KERN_SIGNUP
  info "commented out the blank KERN_SIGNUP= (an empty value stops core booting; unset is the default)"
fi

# The stack files this release ships. Classified now, applied after the snapshot, so `--check` can
# say what would happen and a refusal is known before anything has changed.
classify_stack_files
if [ -n "$STACK_UPDATE" ]; then
  info "to bring forward:$STACK_UPDATE"
else
  info "stack files are already release $TARGET's"
fi
[ -z "$STACK_BLOCKED" ] || info "locally edited, will be left alone:$STACK_BLOCKED"

compose ps --status running --quiet postgres >/dev/null 2>&1 || fail "Postgres is not running."
compose exec -T postgres pg_isready -U "$(env_value POSTGRES_USER)" >/dev/null \
  || fail "Postgres is not accepting connections."
info "database is reachable"

DB_BYTES="$(compose exec -T postgres psql -U "$(env_value POSTGRES_USER)" -d "$(env_value POSTGRES_DB)" \
  -tAc "select pg_database_size(current_database())" | tr -d '[:space:]')"
FREE_KB="$(df -Pk "$DIR" | awk 'NR==2 {print $4}')"
NEED_KB="$(( DB_BYTES * 2 / 1024 ))"
[ "$FREE_KB" -gt "$NEED_KB" ] \
  || fail "Not enough disk space for a snapshot: need about $(( NEED_KB / 1024 )) MB, $(( FREE_KB / 1024 )) MB free."
info "disk space is enough for a snapshot"

step "Pulling $TARGET"
# Before the dry run, because the dry run has to execute the *target* image to say anything about
# the target release, and before the snapshot, so a pull that fails costs nothing.
#
# KERN_VERSION goes in the environment rather than in `-e`: `-e` sets a variable inside the
# container, which does not change the image tag Compose interpolated from .env — so the dry run
# used to run the OLD image and report on the release the instance was already on. A shell variable
# takes precedence over .env when Compose interpolates `${KERN_VERSION}`, which is what actually
# selects the image.
KERN_VERSION="$TARGET" compose pull || fail "Could not pull the $TARGET images. Nothing has been changed."

step "Checking what the migrations would do"
KERN_VERSION="$TARGET" compose run --rm --no-deps core node dist/migrate.js --check \
  || fail "The migration dry run failed. Nothing has been changed."
# What that dry run covers: core's own schema and every module core hosts. It does not cover chat,
# mail or collab, which own module schemas and migrate them inside their own boot — there is no
# migrate entrypoint in those images to ask. The upgrade compensates by keeping maintenance mode on
# until those services are up and past their migrations, rather than by pretending to know first.
info "covers core and the modules core hosts; chat, mail and collab migrate at boot, under maintenance"

if [ "$CHECK_ONLY" = true ]; then
  if [ -n "$STACK_BLOCKED" ]; then
    report_blocked_stack_files
    printf '\033[33m⚠ Preflight passed, but the upgrade would not deliver everything. Nothing was changed.\033[0m\n' >&2
    exit 1
  fi
  printf '\n\033[32m✔ Preflight passed. Nothing was changed.\033[0m\n'
  exit 0
fi

# ---------------------------------------------------------------- snapshot

step "Taking a snapshot before anything changes"
STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP="$SNAPSHOT_DIR/$CURRENT-to-$TARGET-$STAMP"
mkdir -p "$SNAP"
compose exec -T postgres pg_dump -U "$(env_value POSTGRES_USER)" -Fc "$(env_value POSTGRES_DB)" > "$SNAP/database.dump" \
  || fail "The database dump failed. Nothing has been changed."
cp .env "$SNAP/.env"
cp docker-compose.yml "$SNAP/docker-compose.yml"
[ -f Caddyfile ] && cp Caddyfile "$SNAP/Caddyfile"
# postgres-init/ too, now that an upgrade can replace it. A snapshot has to hold everything the
# upgrade is about to change, or rolling back restores a stack the database no longer matches.
[ -d postgres-init ] && cp -R postgres-init "$SNAP/postgres-init"

# What rollback re-pins. `latest` is not a version you can go back to — it is a moving pointer, and
# after this upgrade it points at TARGET, so recording it would make kern-rollback.sh a no-op that
# reports success. An instance installed before install.sh started pinning is on `latest`, so ask
# the running core what it actually is: the number is baked into the image, so it cannot be wrong.
FROM="$CURRENT"
if [ "$CURRENT" = "latest" ] || [ "$CURRENT" = "main" ]; then
  RESOLVED="$(reported_version core 4000)"
  if [ -n "$RESOLVED" ]; then
    FROM="$RESOLVED"
    info "KERN_VERSION was \"$CURRENT\"; core reports $RESOLVED, so that is what rollback will use"
  else
    info "KERN_VERSION is \"$CURRENT\" and core could not be asked what it is running."
    info "A rollback from this snapshot will refuse; pin KERN_VERSION to a number to fix that."
  fi
fi
printf '%s\n' "$FROM" > "$SNAP/from-version"

# Object storage is NOT in this snapshot: it holds the database, .env and the compose files, and
# nothing else. A file uploaded after it was taken still exists after a rollback, but a rollback
# with --database restores rows that no longer know about it — and rows deleted since will point at
# objects that were already removed. ./kern-backup.sh is the one that mirrors the bucket.
printf 'database, .env, docker-compose.yml, Caddyfile, postgres-init/. NOT object storage.\n' > "$SNAP/contents"
info "snapshot: $SNAP (database and configuration only — not object storage)"

# Keep the last few and no more, so snapshots cannot fill the disk on their own. The glob is the
# snapshot naming pattern (`<from>-to-<target>-<stamp>`) rather than `*/`, because this directory now
# holds `stack-<stamp>/` directories too — the diffs an operator has been told to merge by hand. A
# bare `*/` counted those as snapshots: it would delete the instructions and evict a real snapshot to
# make room for them.
if [ -d "$SNAPSHOT_DIR" ]; then
  ls -1dt "$SNAPSHOT_DIR"/*-to-*/ 2>/dev/null | tail -n +"$(( KEEP_SNAPSHOTS + 1 ))" | xargs -r rm -rf
fi

# What the panel is told. One helper so the two callers cannot drift: whatever an unattended run
# reports here is what Admin -> Updates shows, and it has to be the same verdict the shell exits on.
record_attempt() { # record_attempt ok|failed [message]
  compose exec -T core node dist/updates-cli.js record "$TARGET" "$@" >/dev/null 2>&1 || true
}

undo() {
  if [ "$AUTO" = true ]; then
    # Tell the instance it failed. The next run reads this and stands down until an admin has
    # looked — a nightly job that keeps retrying the release that broke turns one bad night into
    # a week of them.
    record_attempt failed "$1"
    logger -t kern-auto-update "upgrade to $TARGET failed: $1" 2>/dev/null || true
  fi
  printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2
  printf '\nTo go back to %s:\n\n' "$CURRENT" >&2
  printf '  %s/kern-rollback.sh %s\n\n' "$DIR" "$SNAP" >&2
  exit 1
}

# ---------------------------------------------------------------- the release's stack files

# After the snapshot, so the copies being replaced are already saved and kern-rollback.sh can put
# them back; before maintenance mode, so a compose file that will not parse costs nothing.
if [ -n "$STACK_UPDATE" ]; then
  step "Bringing the stack files release $TARGET ships forward"
  apply_stack_files
  # A compose file that does not parse leaves the instance unable to run any docker compose command
  # at all — including the one that would undo this. Put the old ones back rather than find out.
  if ! compose config >/dev/null 2>&1; then
    restore_stack_files
    fail "The $TARGET docker-compose.yml does not parse here. The previous files are back in place and nothing else was changed."
  fi
  info "compose file still valid"
fi

# ---------------------------------------------------------------- apply

step "Closing the API while the database changes"
KERN_VERSION="$TARGET" compose run --rm --no-deps core node dist/migrate.js --maintenance on \
  || undo "Could not turn maintenance mode on."

step "Pinning $TARGET"
set_env KERN_VERSION "$TARGET"

step "Migrating"
compose run --rm --no-deps core node dist/migrate.js || undo "The migrations failed."

step "Starting core"
compose up -d core core-worker || undo "core did not start."
wait_ready core 4000 60 || undo "core did not become ready."
info "core is ready"

# Everything else comes up while maintenance is still on, on purpose. chat, mail and collab each own
# module schemas and migrate them inside their own boot, so turning maintenance off before they had
# started — which is what used to happen here — ran their schema changes with the API already open
# to users. They are the migrations the dry run above cannot see, so they are the ones that most
# need the door shut.
step "Starting everything else"
compose up -d || undo "Not every service started."

step "Waiting for the services that migrate at boot"
for pair in "chat 4100" "mail 4200" "collab 4300"; do
  # deliberate split of "<service> <port>" into $1 and $2
  # shellcheck disable=SC2086
  set -- $pair
  compose ps --status running --quiet "$1" >/dev/null 2>&1 || continue
  wait_ready "$1" "$2" 60 || undo "$1 did not become ready, so its migrations may not have finished."
  info "$1 is ready"
done

step "Opening the API again"
compose run --rm --no-deps core node dist/migrate.js --maintenance off \
  || undo "Could not turn maintenance mode off."

# ---------------------------------------------------------------- verify

step "Checking every service reports $TARGET"
sleep 5
FAILED=""
for pair in "core 4000" "chat 4100" "mail 4200" "collab 4300"; do
  # deliberate split of "<service> <port>" into $1 and $2
  # shellcheck disable=SC2086
  set -- $pair
  compose ps --status running --quiet "$1" >/dev/null 2>&1 || continue
  REPORTED="$(reported_version "$1" "$2")"
  if [ "$REPORTED" = "$TARGET" ]; then info "$1: $REPORTED"; else FAILED="$FAILED $1($REPORTED)"; fi
done

# app is the web front end and has no /api/health to ask — its own healthcheck fetches `/`. So it is
# checked by the image it is running, which is the thing an upgrade actually changes. Skipping it
# entirely, as this loop used to, meant a shell left on the old build passed the upgrade.
if compose ps --status running --quiet app >/dev/null 2>&1; then
  APP_IMAGE="$(compose ps --format '{{.Image}}' app 2>/dev/null | tr -d '[:space:]')"
  case "$APP_IMAGE" in
    *:"$TARGET") info "app: $APP_IMAGE" ;;
    *) FAILED="$FAILED app($APP_IMAGE)" ;;
  esac
fi

[ -z "$FAILED" ] || undo "These services are not on $TARGET:$FAILED"

# The images moved either way, so this is not a failed upgrade — but it is not a finished one, and it
# used to print the same green tick in both cases. A release whose fix lives in the Caddyfile or the
# compose file has not reached an instance that kept its own copy, and the only person who can finish
# the job is the operator reading this line.
#
# The outcome is recorded after this verdict, never before it. Recorded above and exited on below,
# the two disagreed: Admin -> Updates said the release was applied while systemd marked
# kern-auto-update.service failed for the same run, because the unit is Type=oneshot and reads any
# non-zero status as a failure. An operator seeing a red unit every night for an upgrade that
# worked stops reading them, which is how the night one genuinely fails goes unnoticed.
if [ -n "$STACK_BLOCKED" ]; then
  report_blocked_stack_files
  printf '\033[33m⚠ Kern is on %s, but this upgrade could not deliver all of it — see above.\033[0m\n' "$TARGET"
  printf '  Snapshot kept at %s\n' "$SNAP"
  printf '  To go back:      %s/kern-rollback.sh %s\n' "$DIR" "$SNAP"
  offer_new_upgrade_script
  printf '\n'
  if [ "$AUTO" = true ]; then
    # `ok` is the honest record: the images moved, the migrations ran and every service reports
    # $TARGET a few lines above, so the release IS applied. `failed` would also stand the timer
    # down until an admin cleared it — and the file is still edited tomorrow night, so a locally
    # edited Caddyfile would silently end automatic updates for good.
    record_attempt ok
    logger -t kern-auto-update \
      "upgraded to $TARGET; these files still need merging by hand:$STACK_BLOCKED" 2>/dev/null || true
    # Warning, not failure, for the unattended run: the work waiting for an operator is in the
    # journal and in the panel, and neither of them needs the unit painted red to be found. A person
    # at a terminal gets the non-zero status, because there the exit code is the only signal.
    exit 0
  fi
  exit 1
fi

if [ "$AUTO" = true ]; then
  record_attempt ok
  logger -t kern-auto-update "upgraded to $TARGET" 2>/dev/null || true
fi

printf '\n\033[32m✔ Kern is on %s.\033[0m\n' "$TARGET"
printf '  Snapshot kept at %s\n' "$SNAP"
printf '  To go back:      %s/kern-rollback.sh %s\n' "$DIR" "$SNAP"
offer_new_upgrade_script
printf '\n'
