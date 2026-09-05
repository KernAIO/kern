#!/usr/bin/env bash
#
# Decide where the rollout should talk to Coolify, and refuse to put the token on the wire.
#
# `COOLIFY_TOKEN` is a full Coolify API token — it can read and change every application on the
# host, not just deploy this one. The rollout used to send it as an `Authorization: Bearer` header
# to `http://<ip>:8000`: plain HTTP, to a bare address, from a GitHub-hosted runner across the
# public internet, on every nightly release. Anything on that path reads the token and owns the
# instance.
#
# There is no HTTPS to switch to. Measured on 2026-09-05: :8000 speaks no TLS at all, :443 is
# Coolify's Traefik and holds certificates for kernaio.com, www, docs, app and files only, the
# instance has no FQDN configured, and no Coolify hostname exists in DNS. Pointing the workflow at
# `https://` would break every release rather than secure one.
#
# So it goes the way it was always going to: the rollout already holds an SSH connection to the
# same host, because it dry-runs migrations and dumps the database there. This forwards a local
# port down that connection to Coolify's own loopback address, and the API call becomes a local
# one. The token never leaves the runner, and what crosses the internet is the SSH channel that
# was crossing it anyway.
#
# Prints exactly one line on stdout — the base URL every later step uses. Everything else is
# stderr. Exits non-zero rather than falling back to cleartext: a fallback nobody sees is how the
# credential ends up on the wire again.
#
#   COOLIFY_URL=http://1.2.3.4:8000 SSH_HOST=1.2.3.4 SSH_USER=root \
#   SSH_KEY_FILE=~/.ssh/rollout_key .github/scripts/coolify-endpoint.sh
#
set -uo pipefail

COOLIFY_URL="${COOLIFY_URL:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/rollout_key}"
LOCAL_PORT="${COOLIFY_LOCAL_PORT:-18000}"
CONTROL_SOCKET="${COOLIFY_CONTROL_SOCKET:-${RUNNER_TEMP:-/tmp}/coolify-tunnel.sock}"

die() { echo "::error::$*" >&2; exit 1; }
note() { echo "$*" >&2; }

[ -n "$COOLIFY_URL" ] || die "COOLIFY_URL is not set. The rollout pins KERN_VERSION through the Coolify API; set the repository or organisation variable COOLIFY_URL to where that API listens."

scheme="${COOLIFY_URL%%://*}"
rest="${COOLIFY_URL#*://}"
authority="${rest%%/*}"

case "$authority" in
  \[*) die "COOLIFY_URL uses an IPv6 literal ($authority), which this cannot take apart. Give Coolify a hostname with a certificate and use https://, or open the port forward by hand." ;;
esac

host="${authority%%:*}"
port="${authority##*:}"
if [ "$port" = "$authority" ]; then
  [ "$scheme" = "https" ] && port=443 || port=80
fi

case "$scheme" in
  https)
    # Encrypted already: nothing to protect it from.
    note "Coolify over TLS at $host:$port — talking to it directly."
    printf '%s\n' "$COOLIFY_URL"
    exit 0
    ;;
  http) ;;
  *) die "COOLIFY_URL must be an http:// or https:// URL — got '$scheme://'." ;;
esac

case "$host" in
  127.0.0.1|localhost|::1)
    # Already a local call; nothing crosses a network.
    note "Coolify at $host:$port is local to this runner — nothing to tunnel."
    printf '%s\n' "$COOLIFY_URL"
    exit 0
    ;;
esac

[ -n "$SSH_HOST" ] || die "COOLIFY_URL is cleartext http:// to $host, and there is no SSH host to reach it through. Set KERN_CLOUD_SSH_HOST, or give Coolify a hostname with a certificate and use https:// — the API token must not cross the internet unencrypted."

if [ "$host" != "$SSH_HOST" ]; then
  die "COOLIFY_URL is cleartext http:// to $host, but the rollout's SSH host is $SSH_HOST — so there is no encrypted path to it. Serve the Coolify API over https://, or run it on the host this rollout already connects to. Sending a full Coolify API token to a third host in the clear is what this refusal exists to prevent."
fi

[ -f "$SSH_KEY_FILE" ] || die "$SSH_KEY_FILE does not exist, so the port forward to Coolify cannot be opened. This runs after the step that writes the key."

# More than one step needs the API, and a second `ssh -L` on the same port dies with "Address
# already in use" — measured. So reuse a forward this job already opened, and only then if it still
# answers: a master that is alive but whose forward is dead is worse than no master at all.
endpoint="http://127.0.0.1:$LOCAL_PORT"
if ssh -S "$CONTROL_SOCKET" -O check "$SSH_USER@$SSH_HOST" >/dev/null 2>&1; then
  # Same status match as below, and for the same reason: a curl that cannot connect prints `000`
  # and exits non-zero, so `|| echo 000` makes it `000000` and any "is it 000" test says no.
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$endpoint/api/v1/version" 2>/dev/null)"
  case "$code" in
    [1-5][0-9][0-9])
      note "Reusing the SSH tunnel this job already opened on 127.0.0.1:$LOCAL_PORT (HTTP $code)."
      printf '%s\n' "$endpoint"
      exit 0
      ;;
  esac
  note "The SSH tunnel this job opened is no longer carrying anything — replacing it."
  ssh -S "$CONTROL_SOCKET" -O exit "$SSH_USER@$SSH_HOST" >/dev/null 2>&1
fi

# A control socket, so the forward can be closed again by name. `-f -N` puts ssh in the background
# after authentication; `ExitOnForwardFailure` makes it fail *there* rather than sitting open with
# nothing listening, which is the difference between an error here and a confusing 000 later.
rm -f "$CONTROL_SOCKET"
if ! ssh -f -N -M -S "$CONTROL_SOCKET" \
      -i "$SSH_KEY_FILE" \
      -o BatchMode=yes -o ConnectTimeout=15 -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -L "127.0.0.1:$LOCAL_PORT:127.0.0.1:$port" \
      "$SSH_USER@$SSH_HOST"; then
  die "Could not open the port forward to $SSH_USER@$SSH_HOST for Coolify on port $port. The rollout will not send a Coolify API token over plain HTTP instead."
fi

endpoint="http://127.0.0.1:$LOCAL_PORT"

# Prove it before anything is changed. An unauthenticated request is enough: any HTTP status means
# Coolify answered through the tunnel, and 000 means it did not — the token is not needed to learn
# that, so it is not sent.
#
# Match the status rather than testing for "000": a curl that cannot connect prints `000` *and*
# exits non-zero, so a `|| echo 000` appends a second one and `[ "$code" = "000" ]` is false
# against `000000`. That shipped for the length of one test run — the tunnel pointed at a dead
# port and this said "Coolify answers".
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$endpoint/api/v1/version" 2>/dev/null)"
case "$code" in
  [1-5][0-9][0-9]) ;; # any HTTP status at all means something answered through the tunnel
  *)
    ssh -S "$CONTROL_SOCKET" -O exit "$SSH_USER@$SSH_HOST" 2>/dev/null
    die "The port forward to Coolify opened but nothing answered on the host's 127.0.0.1:$port. Check that Coolify still publishes that port on the loopback interface of $SSH_HOST."
    ;;
esac

note "Coolify answers through the SSH tunnel: 127.0.0.1:$LOCAL_PORT -> $SSH_HOST:127.0.0.1:$port (HTTP $code unauthenticated). The API token stays on the runner."
printf '%s\n' "$endpoint"
