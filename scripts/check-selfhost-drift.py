#!/usr/bin/env python3
"""The Coolify stack and the Kern Cloud stack are second and third copies of the self-host stack,
and a copy is only useful while it stays the same stack. Two things make them the same: the
environment `core` is handed, and the paths Caddy routes. Both are easy to change in one file and
forget in the others, and none of it shows up as a failure until somebody deploys.

    python3 scripts/check-selfhost-drift.py
    python3 scripts/check-selfhost-drift.py --emit-caddyfile /tmp/Caddyfile
    python3 scripts/check-selfhost-drift.py --emit-cloud-caddyfile /tmp/Caddyfile.cloud

The emit flags write out the config a stack builds at run time, so `caddy validate` can read it.
Nothing else ever would: it lives in a heredoc inside a container command.

What a copy is allowed to differ in is the *value* of a variable, never the set of keys — Kern
Cloud points S3_PUBLIC_ENDPOINT at its own storage hostname, for instance, because Cloudflare
rejects a proxied body over 100 MB and core signs single-PUT URLs far larger than that.

Routes are compared as ordered directive lists, but a copy may deliberately drop a route when the
service behind it does not exist there — Kern Cloud keeps no MinIO on the box (files go to Hetzner
Object Storage, see cloud/docker-compose.yml), so it has no `/s3` handler to keep alive. Such
omissions must be declared here, or the check fails; nothing else about the routing order may move.

Comparing the copies against the host answers "did one of them fall behind?" and cannot answer "does
any of them route this at all?" — three identical configs agree perfectly while all three are wrong.
That is not hypothetical: core serves `/mcp` and the OAuth discovery documents at the *root* of its
Fastify app, no stack had a route for them, every one of them fell through to the catch-all and was
answered with the app's HTML, and this check reported no drift throughout. REQUIRED_ROUTES is the
half that does not depend on the three agreeing: a route named there has to be present, in order,
above the catch-all, in the host Caddyfile and in both inline copies.
"""

import os
import re
import subprocess
import sys

import yaml

HOST = "selfhost/docker-compose.yml"
COOLIFY = "selfhost/coolify/docker-compose.yml"
CLOUD = "cloud/docker-compose.yml"

# Directives a copy is allowed to be missing, per path. Kern Cloud proxies no MinIO.
ALLOWED_MISSING = {
    CLOUD: {"handle /kern/* {", "reverse_proxy minio:9000"},
    COOLIFY: set(),
}

# Variables a copy declares with `${VAR:?message}`, which makes `docker compose config` fail rather
# than substitute a blank. That is the point of them — KERN_ADMIN_EMAIL creates a real instance
# administrator on the first boot, so defaulting it is worse than refusing to deploy — but it means
# this check has to supply a value to get a document at all. A placeholder here is not a default in
# the stack: remove the `:?` and the deploy silently gets one, which is the thing being prevented.
PLACEHOLDER_ENV = {"KERN_ADMIN_EMAIL": "drift-check@example.invalid"}

# Routes every stack must carry, whatever the three happen to agree on. Each entry is a run of
# directives that has to appear in that order, one after another, and above the `handle {` catch-all
# — a route below the catch-all is dead, because Caddy's first matching handler wins.
#
# Add one here whenever a service starts answering on a path that is not under an existing prefix.
# The MCP entry is the reason the section exists: those paths are fixed by the MCP and RFC 8414/9728
# specifications, so core cannot move them under /api where `handle /api/*` would already carry them.
CATCH_ALL = "handle {"
REQUIRED_ROUTES = {
    "MCP and its OAuth discovery documents reach core": [
        "@mcp path /mcp /mcp/* /.well-known/oauth-protected-resource "
        "/.well-known/oauth-protected-resource/* /.well-known/oauth-authorization-server",
        "handle @mcp {",
        "reverse_proxy core:4000",
    ],
    # The signalling WebSocket a browser opens before a call. LiveKit serves it at /rtc, so the
    # strip_prefix is part of the route rather than decoration: without it LiveKit is asked for
    # /livekit/rtc and the call never negotiates. That is why `uri` is in the directive list below.
    # livekit:7880 is not published by any of the three compose files, so this route is the only way
    # to reach it — and only these two paths, never /twirp/*.
    "LiveKit signalling reaches the media server": [
        "@livekit path /livekit/rtc /livekit/rtc/*",
        "handle @livekit {",
        "uri strip_prefix /livekit",
        "reverse_proxy livekit:7880",
    ],
}


def run_index(directives, run):
    """Index where `run` appears as a contiguous slice of `directives`, or -1."""
    for i in range(len(directives) - len(run) + 1):
        if directives[i : i + len(run)] == run:
            return i
    return -1


def require_routes(label, directives):
    """Absolute check: does this config route what it must, regardless of what the others do?"""
    global failed
    for what, run in REQUIRED_ROUTES.items():
        at = run_index(directives, run)
        if at < 0:
            failed = True
            print(f"::error::{label}: {what} — expected these directives, in this order:")
            for directive in run:
                print(f"    {directive}")
            continue
        if CATCH_ALL in directives and at > directives.index(CATCH_ALL):
            failed = True
            print(f"::error::{label}: {what} — routed below the `{CATCH_ALL}` catch-all, so it never matches")
            continue
        print(f"✔ {what} ({label})")


def config(path):
    """`docker compose config` rather than a plain YAML load, so anchors and defaults are resolved
    the way Docker resolves them."""
    out = subprocess.run(
        ["docker", "compose", "-f", path, "config"],
        capture_output=True,
        text=True,
        env={**os.environ, **PLACEHOLDER_ENV},
    )
    if out.returncode:
        sys.exit(f"::error::{path} does not parse:\n{out.stderr}")
    return yaml.safe_load(out.stdout)


failed = False


def compare(what, other_path, host_set, other_set):
    global failed
    if host_set == other_set:
        print(f"✔ {what} ({other_path})")
        return
    failed = True
    for key in sorted(host_set - other_set):
        print(f"::error::{what}: {key} is in {HOST} and missing from {other_path}")
    for key in sorted(other_set - host_set):
        print(f"::error::{what}: {key} is in {other_path} and missing from {HOST}")


def kern_images(doc):
    return {
        image.split("/")[-1].split(":")[0]
        for service in doc["services"].values()
        for image in [service.get("image", "")]
        if image.startswith("ghcr.io/kernaio/")
    }


def routes(caddyfile):
    """The directives that decide where a request goes, and what path the upstream is asked for.
    Formatting and comments are free to differ; the order matters, because Caddy's first matching
    handler wins. `uri` and `rewrite` are in the list because a route that reaches the right
    container with the wrong path is as broken as one that reaches nothing."""
    directive = re.compile(r"^\s*(reverse_proxy|handle|handle_path|@\w+ path|rewrite|uri)\b")
    return [re.sub(r"\s+", " ", line).strip() for line in caddyfile.splitlines() if directive.match(line)]


def inline_caddyfile(doc):
    """Neither copy has a Caddyfile beside it: a pasted Compose file has no files to mount, so the
    config is a heredoc inside the container's command."""
    return doc["services"]["caddy"]["command"][0].split("<<'CADDYFILE'", 1)[1].split("\nCADDYFILE", 1)[0]


def emit(flag, text):
    if flag in sys.argv:
        destination = sys.argv[sys.argv.index(flag) + 1]
        open(destination, "w").write(text)
        print(f"✔ wrote {destination}")


host = config(HOST)
host_routes = routes(open("selfhost/Caddyfile").read())
require_routes("selfhost/Caddyfile", host_routes)

for path, emit_flag in ((COOLIFY, "--emit-caddyfile"), (CLOUD, "--emit-cloud-caddyfile")):
    doc = config(path)
    compare("core environment", path, set(host["services"]["core"]["environment"]), set(doc["services"]["core"]["environment"]))
    compare("Kern images", path, kern_images(host), kern_images(doc))

    inline = inline_caddyfile(doc)
    emit(emit_flag, inline)
    require_routes(path, routes(inline))

    if routes(inline) == host_routes:
        print(f"✔ Caddy routes ({path})")
    else:
        missing = set(host_routes) - set(routes(inline))
        allowed = ALLOWED_MISSING[path]
        if routes(inline) == [d for d in host_routes if d not in allowed] and missing <= allowed:
            print(f"✔ Caddy routes ({path}, minus declared omissions: {sorted(missing)})")
        else:
            failed = True
            print(f"::error::the Caddy config inside {path} no longer routes the same paths as selfhost/Caddyfile")
            print("  host: ", host_routes)
            print(f"  {path}: ", routes(inline))

sys.exit(1 if failed else 0)
