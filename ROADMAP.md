# Kern roadmap

> Status: **public, pre-1.0.** The repositories are open and every commit is visible.
> **v1.0 ships on 2026-09-16.** Rewritten on 2026-09-02 against what is actually built, not against
> the plan; the previous roadmap said "Q4 2026" and listed as missing several things that ship today.

## What v1.0 is

One application for a team's work — **issues, conversations, documents, mail, people and assets** —
that a company can buy hosted, a self-hoster can install with one command and keep updated without
us, and a developer can extend with a module of their own. The rule we cut by has not changed: a
module ships when every capability its server offers is reachable from the interface.

### Shipped, and in v1.0

Verified on 2026-09-02 by reading the registry, the routes and the release feed — not the plan.

- **Platform** — accounts with password, magic link, Google/GitHub/Microsoft sign-in, two-factor,
  passkeys, API keys. Many workspaces per instance; members,
  built-in and custom roles, groups, per-object permission bindings. One notification inbox across
  workspaces. Files, cross-module search, the audit log, per-workspace module and capability
  switches, data export and account erasure. Instance admin console: users, workspaces, modules,
  plans, subscriptions, updates. MCP server for AI clients. REST API with OpenAPI. Four languages
  (en, de, fa, ar, plus tr) with zero untranslated strings, RTL, light and dark, installable as an
  app.
- **Tracker** — projects, work item types and hierarchy, custom fields and layouts, workflows with
  a visual editor, issues with relations, comments, watchers, attachments, approvals, list and board
  views, KQL and saved views, cycles, milestones, versions, components, labels, triage, the public
  intake form, repeating issues, import, time tracking and reports.
- **Chat** — channels, private channels, group and direct messages, threads, reactions, mentions,
  pins, read state, presence, search, attachments, object channels tied to an issue.
- **Quire** — spaces, a nested page tree, real-time collaborative editing, version history,
  comments, draft/publish, published sites addressed by path, diagrams and embeds, databases.
- **Mail** — outbound email per workspace through SMTP, Mailgun, SES, Postmark or Resend, with
  templates, delivery log, bounces and suppression. Email-to-issue is **not** built (corrected
  2026-09-04: `inbound_routes` is a placeholder table, `tracker.issues.createFromEmail` has no
  caller, and the mail service receives nothing).
- **HR** — directory, org chart, offices, legal entities and cost centres, leave, attendance,
  approvals, subject access and erasure, onboarding and offboarding checklists (shipped in 0.22.0,
  2026-09-03).
  Reachability audited 2026-09-03: of the 137 contract procedures, 129 have client call sites; the
  six that had none (entities and cost-centre writes — `payroll.export.v1` needs an employer to
  exist, so a fresh workspace could not run payroll at all) got the Entities settings screen. The
  eight still without callers are deliberate: four single-get reads covered by list + client-side
  filter (`offices.get`, `policies.get`, `leave.requests.get`, `entities.get`), `approvals.get`
  (the inbox already carries steps and decisions), `attendance.days.recompute` (a server job calls
  the internal function), `policies.resolveFor` (an explainer endpoint with no natural screen) and
  `people.history` (the field-change log; the person card tells the employment story through
  `employment.history`).
- **Inventory** — the asset register: what the company owns, who holds it, purchase and warranty,
  categories, full history. Reachability audited 2026-09-03: every one of the 32 contract
  procedures (assets, fields, custody, categories, repairs, attachments, stats) has a client call
  site — nothing server-only.
- **Billing** — plans, subscriptions, entitlements and Stripe checkout, administered from the admin
  console. Off by default on a self-hosted instance. Reachability audited 2026-09-03: 13 of the 14
  contract procedures (plans, subscription, admin) have client call sites (PlansAdmin,
  SubscriptionsAdmin, PlanSettings) — nothing server-only. The one miss, `plans.public`, is
  deliberate: the unauthenticated catalogue kernaio.com's pricing page regenerates from on every
  build (core's diagnostics test holds it as the only public billing surface).
- **Release and update** — a nightly release that advances every module, signs a feed, rolls the
  cloud out as the canary with a migration dry run, snapshot, maintenance mode and rollback; a
  self-hosted instance that notifies or updates itself inside a window it chooses. Automatic end to
  end since 2026-09-02.

### Not in v1.0

Never started, or a schema with no screens. Each is documented on the docs site as *planned* and
on the website as *planned*; nothing sells them.

**Drive** · **Calendar** · **Recruiting** · **CRM** · **Automation** rules engine · **Calls**
(not in v1.0; being built now for v1.1 on 2026-09-23 — see below. `module-meet` exists and is
empty, and no module reads the LiveKit profile yet) · **AI assistant** · **Personal mail
inbox** (IMAP) · **Email-to-issue** (intake addresses) · **SSO** (OIDC/SAML — the entitlement is
gated, but registering a provider answers 500 and has no screen; [core#1](https://github.com/KernAIO/core/issues/1),
found 2026-09-04) · **Outgoing webhooks** · cross-workspace shared channels ·
Meilisearch · SCIM · GitHub/GitLab links · CalDAV/Google sync · WebDAV · whiteboards · mobile and
desktop shells · a marketplace for community modules.

## What "finished" means on 2026-09-16

Three people have to succeed without talking to us, and each one is a slice below.

1. **A company buys Kern Cloud** and its data is safe: backups exist and have been restored once,
   somebody is told when the instance breaks, the plan they bought enforces what it promises, and
   every page they read on the way in says only true things.
2. **A self-hoster installs Kern** on a clean machine from the one-line command, upgrades it, rolls
   it back, and restores a backup — following the docs and nothing else.
3. **A developer builds a module** from the published template, runs it in a Kern of their own, and
   sees its screens — following the docs and nothing else.

## The two weeks

**Where it stood on 2026-09-04**, from `TODO.md`: slice 1 is green everywhere; slice 2 has backups, a restore drill, an uptime
watch, sshd hardening and the mailboxes done, and is **blocked on two things only the owner can
buy** — a mail relay credential (no email has ever left the cloud) and Stripe keys; slice 3 is done,
the plan catalogue included; slice 4 has not been run on a clean VM yet, and is blocked on a
Hetzner Cloud API token; slice 5 is built and documented (`KERN_EXTRA_MODULES`, `KERN_IMAGE_*`) and verified by
building both images, not yet by a stranger; slice 6 has every module under a permission matrix and
an isolation test — which found `mod_mail` had no row-level security at all, now fixed — the edge
checked from outside, and the UX sweep green on every route; v1.0.0 is not cut.

Six slices. A slice is done when the sentence at its head is true and somebody outside this project
could confirm it; not when the code type-checks. Days are 2026-09-03 → 2026-09-16.

### 1. Nothing is red, and nothing is sitting unpushed — every day (all two weeks)

*The nightly release runs green, and the cloud is on it by morning.*

The release is automatic now, so a red `main` is the only thing that can stop it — and on
2026-09-02 every service's `main` was red without anyone knowing. Each morning: the nightly's
outcome, `/api/health` on app.kernaio.com against the feed, and `pnpm status` for work another
session left half-way (on 2026-09-02: 19 uncommitted files in `shell`, 7 unpushed commits in
`website`, a cross-tenant fix in `module-tracker` that sat unpushed for a day). Land it or revert
it; a repository is not allowed to carry work nobody has tested for more than a day.

### 2. Kern Cloud can take money safely — days 1–5

*A stranger signs up, upgrades to Team with a card, hits the seat limit, is invoiced, cancels, and
nothing about that surprised them or us.*

- Nightly `pg_dump` and an object-storage mirror to Hetzner S3, off the host, with retention; one
  restore drill onto a scratch database, documented. Today the only copies are the pre-upgrade
  dumps in `/var/backups/kern`, on the same disk.
- An external probe on `/api/health` and a failure notification on `release.yml` and
  `rollout.yml`. Tonight's nineteen-minute outage was noticed because somebody was watching.
- Stripe live: a real test purchase through checkout, the webhook route, the invoice, the
  suspension path (`billing-suspended.spec.ts` exists uncommitted in `shell`), and every
  entitlement the plan table advertises actually enforced — seats, storage, SSO, audit retention.
- Legal: `/privacy`, `/terms`, `/subprocessors` read by a careful hour; the DPA decision made; the
  five mailboxes receive mail.
- Password SSH login off on the cloud host; key auth is what the rollout uses.

### 3. Every page says only what ships — days 1–3

*Nowhere on kernaio.com, docs.kernaio.com or GitHub does a module that does not exist appear in
the present tense.*

The docs site describes Recruiting, CRM, Automation, Calls and AI as if built. The website marks
HR *planned* and Quire *building* while both ship, and its launch checklist still says the images
are private (they are public). The README, the docs sidebar, the website's module list and this
file have to agree, and `pnpm pricing` has to import a clean plan catalogue.

### 4. A self-hoster gets from zero to upgraded and back — days 4–9

*On a clean Ubuntu 24.04 VM, downloading and running `install.sh` gives a working Kern; a
release later, the timer upgrades it inside the window; `kern-rollback.sh` undoes it;
`kern-backup.sh` and a restore work.*

Done by running it, on a VM nobody has touched, following `docs.kernaio.com/self-hosting` and
nothing else — and the same on Coolify from the pasted Compose file. Every step that needed
knowledge not on the page is a docs bug; every step that failed is a product bug. The `db-init`
class of failure (a script that runs on every existing instance at every deploy) now has a CI test;
anything else found here gets one too.

### 5. A developer ships a module of their own — days 6–12

*`npx degit KernAIO/module-template` → build → test → run inside a local Kern → the module's
screens and settings appear, and its permissions, capabilities and strings work — following
`docs.kernaio.com/developers/module-development` and nothing else.*

Today a third-party module still needs a line in `shell`'s registry and a line in `core`'s
`featureModules`, which means forking both. v1.0 makes that a **build**, not a fork: `shell` and
`core` images accept a list of extra module packages at build time and generate those two lines,
and the docs show a self-hoster building their own image pair with a custom module in it. Runtime
loading stays out of scope (ADR 0002). Verified by an agent with no context following the page.

### 6. It is safe to sell — days 9–14

*The permission matrix and tenant isolation are tested in every module, not assumed; the
interface passes its own audit in four renderings; the security review has no open finding.*

`@kernhq/testing`'s permission matrix runs in every module; each module carries an isolation test
like `module-tracker`'s (two of the leaks it found shipped before it existed); rate limits and
security headers checked from outside; `ux.spec.ts` green on every route; a last pass over the
open audit findings. Then **v1.0.0** is cut by hand — the only version the nightly will not pick
on its own — with `schemaChanges` and `minPreviousVersion` set deliberately.

## v1.1 — Meetings, 2026-09-23

**Decided 2026-09-06, and building now.** `KernAIO/module-meet` exists and is deliberately empty of
features; the LiveKit config it will use ships corrected in v1.0 and claims nothing.

Four architects designed this independently and all four estimated nine to twelve focused days
against eleven calendar days that already carried the rest of v1.0. The alternative was a cut-down
version without persistent rooms, which is the half a customer least recognises. One week buys the
whole feature instead.

What v1.1 contains: call a colleague and their Kern rings wherever they are; camera and microphone
with a preview first; several people at once; screen sharing; a huddle started from a chat
conversation, with a message in the channel and a summary when it ends; named rooms a team walks
into; chat inside the meeting; and the call surviving navigation, so opening an issue does not hang
it up. Deferred deliberately: recording, dial-in, live captions, breakout rooms, and a guest door
for people with no account.

**Nothing says meetings exist until [item 13] passes** — two people, two machines, two networks,
seeing and hearing each other. Not when the code looks finished. Until then this file, the docs, the
website and `.env.example` all keep saying calls are not built. The plan's own rule is that the
acceptance test may never be cut; it is what separates a module from a claim.

## After v1.1

The modules above under *Not in v1.0*, in roughly the order a paying team asks for them:
Recruiting and CRM (both start from the workflow engine the tracker already uses), Automation,
Calendar, Drive, AI. Each ships as its own repository through the same nightly.

## How this file is kept true

Change it in the commit that changes what v1.0 contains. A slice is moved to *Shipped* when its
sentence is true, with the date; a slice that slips says so here rather than in a chat.
