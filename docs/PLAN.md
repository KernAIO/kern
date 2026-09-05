# Kern — Project Setup & Architecture Plan

## 1. Context

Kern is a new open-source, self-hostable **all-in-one work platform**: Jira-class issue tracking & process/workflows, Mattermost-class chat, Nextcloud-class docs/drive, Huly-class HR/Recruiting/CRM, automation, per-user mail inbox, video calls and an AI assistant — multi-workspace, modular ("plug-and-play" modules), Svelte PWA frontend, Node backend, Docker install. Target: **1–2 months to a feature-complete v1.0 release** (not an MVP), built mostly by Navid + Claude Code. Self-host is free; **Kern Cloud** (hosted) is the commercial product.

Decisions already made by the owner:
- **Frontend:** Svelte (SvelteKit), installable PWA that feels like a native app, RTL/i18n (fa/ar) from day one.
- **Backend:** Node.js. **Multi-repo microservices from day 1** under GitHub org **`KernAIO`** (owner will transfer `mirzaaghazadeh/Kern` → `KernAIO/app`; I create the other repos).
- **v1 must include:** issues/projects/process, chat, docs/drive, HR, automation, mail (per-workspace SMTP/providers + per-user IMAP/SMTP inbox), multi-workspace w/ cross-workspace notifications, roles/groups/permissions, **video/audio calls (LiveKit), Recruiting/ATS + CRM/Leads, AI assistant (BYO key), time tracking**.
- **Design:** I decide (not based on existing files in the folder).

> **Superseded on 2026-08-24 by [ADR 0005](adr/0005-licensing-and-the-module-boundary.md):** the
> framework (`kernel`, plus `_template` and `workflow`) is Apache-2.0 so that anyone can write a
> closed module; the product stays AGPL-3.0-only. The CLA is what made that possible. The original
> note is kept below.

Decision I'm making on the open question (license): **AGPL-3.0 for all public repos + a CLA** (contributors grant KernAIO relicensing rights). AGPL lets everyone self-host/modify, forces SaaS competitors to open their changes, and the CLA keeps the door open for Kern Cloud / enterprise add-ons in a private repo later (same model as Plane, Twenty, Mattermost-ish). Easy to change before the first public release.

> Honest note on multi-repo microservices: it is the owner's call and the plan follows it. The cost (contract versioning, cross-repo changes, more containers) is mitigated by (a) a **small number of services with real runtime reasons**, (b) one shared **`kernel`** runtime so "which module runs in which service" is configuration, (c) an **umbrella dev workspace** that links all repos locally so day-to-day it feels like one monorepo, (d) automated prerelease publishing of shared packages.

---

## 2. Research takeaways that shape the design (condensed)

- **Huly**: model-driven plugins (ids-only pkg + lazily loaded resources + server triggers), append-only **tx/activity log**, `Space`-based access, ~10 containers (its #1 complaint: self-host complexity). SaaS shutting down → opening for Kern. EPL-2.0.
- **Plane** (AGPL): its *paid* list = what users consider premium: custom work-item types, epics/initiatives, time tracking, workflows/approvals, automations, teamspaces, wiki, SSO, RBAC, audit. Kern ships all of it free.
- **Jira** model to cover: issue types + hierarchy levels, custom fields, workflows (statuses/transitions/conditions/validators/post-functions), boards as saved queries (scrum/kanban, WIP, swimlanes), sprints, backlog rank, versions, components, JQL, permission/notification schemes, automation rules w/ branches + smart values, service-desk queues/SLAs, reports.
- **Mattermost/Zulip**: thread + per-member read-state tables; per-channel `last_read` + counters (not per-message receipts); typed extension-point registry for plugins; Mattermost's cross-team gap → Kern does **cross-workspace inbox** natively.
- **Twenty**: runtime metadata-driven custom objects/fields → Kern custom fields/types.
- **Stack (Aug 2026)**: Fastify 5 + **oRPC** (types + OpenAPI 3.1), Drizzle + Postgres 18 (RLS, uuidv7, pgvector, pg_trgm, ltree, pg_partman), pg-boss jobs, Better Auth 1.7 (org/SSO/SAML/SCIM/passkeys/API keys), SvelteKit 2.70 (→3), shadcn-svelte/Bits UI 2 + Tailwind v4, TanStack Query 6 + WS invalidation (no sync engine in v1), Tiptap 3 + Yjs + Hocuspocus, @vite-pwa/sveltekit, Paraglide i18n, LayerChart, Biome, Vitest/Playwright, Caddy.

---

## 3. Product scope — v1.0 feature checklist (by module)

Legend: **(core)** always on · others enable/disable per workspace. "v1.x" = right after release.

**Platform (core)**
- Accounts (global identity): email+password, magic link, Google/GitHub/Microsoft OAuth, 2FA/passkeys, sessions on many devices, SSO (OIDC/SAML) per workspace, SCIM (v1.x), API tokens & service accounts, personal settings (locale, theme, notification prefs).
- Workspaces: create/many per instance; members (owner/admin/member/guest + custom roles), groups/teams, invitations by email **or pick from users you share a workspace with**, join requests, domain auto-join, transfer ownership, archive/delete, branding (logo/colors), workspace-level integrations & secrets (SMTP/provider, AI key, LiveKit), module enable/disable, audit log, data export/import.
- Permissions: permission keys registered by modules; roles = sets of keys; **bindings** at workspace / project / space / object scope; per-project "permission schemes" (Jira-like); guests limited to explicit projects/channels.
- Notifications: unified inbox **across all workspaces** (one WS connection; per-workspace badges), per event-type channel prefs (in-app/push/email), mention/assign/watch rules, digests, Web Push (VAPID + iOS declarative), Badging API.
- Search: global cmd-K search across modules (Postgres FTS + trigram; pgvector semantic via AI module).
- Files: S3/MinIO, resumable uploads (tus), previews/thumbnails, virus-scan hook (v1.x), attach anywhere.
- Activity/audit: append-only activity stream per object (Huly-style) powering history, feeds, and automation triggers.
- Admin console (instance): users, workspaces, modules, default mail, limits, health, versions.
- Public REST API (OpenAPI 3.1), webhooks (outgoing, signed), incoming webhooks, importers (Jira, Linear, CSV; Trello/Asana v1.x).

**Tracker (issues & projects)** — Jira + Linear
- Projects (key, lead, members, icon), **work item types** w/ hierarchy levels (Initiative › Epic › Story/Task/Bug › Sub-task; customizable), custom fields (text, number, date, select/multi, user, label, URL, checkbox, relation, formula-lite), field layouts per type.
- **Workflows**: statuses w/ categories (backlog/todo/in-progress/done/cancelled/triage), transitions (from→to/global), conditions, validators, post-functions (set field, assign, notify, webhook, create sub-item, run automation), **approvals**; workflow schemes per type.
- Issues: title, rich description (Tiptap), assignees, reporter, priority, labels, components, versions/releases, estimates (points/time), start/due, relations (blocks/duplicates/relates/parent), watchers, comments w/ threads & reactions, attachments, links, templates, recurring issues, sub-issues, bulk edit, keyboard-first (Linear-style), sequential keys `KRN-123`, branches/PR links via GitHub/GitLab integration (v1.x).
- Views: List, Board (scrum/kanban: columns↔statuses, WIP limits, swimlanes), Calendar, Timeline/Gantt (dependencies), Spreadsheet; saved + shared views; **KQL** query language (JQL-like) + visual filter builder; personal views ("My issues", "Triage").
- Planning: backlog ranking, **cycles/sprints** (auto-roll, carry-over), milestones, releases, roadmap; reports: burndown/burnup, velocity, CFD, created-vs-resolved, time reports.
- Intake/triage: in-app triage queue, public forms, **email-to-issue** (via Mail module).
- Service-desk lite: queues (saved KQL), SLAs (goal + pause conditions), customer/org field (v1.x full portal).
- **Time tracking**: worklogs, timers, estimates vs logged, timesheets (per user/project/week), approvals (v1.x).
- Per-issue chat channel (opt-in) + "discuss in chat" link.

**Chat** — Mattermost/Slack
- Channels: public/private/DM/group DM/**object channels** (per issue/project/candidate/deal), sections & favorites, threads, reactions, mentions (@user/@group/@channel), read-state & unread counters, pins, bookmarks, search, edits/deletes, file sharing w/ previews, link unfurls, code blocks, typing, presence/status, mute/DnD, message formatting, slash commands, bots/webhooks, message → issue/doc actions, huddles (calls), channel export. Cross-workspace shared channels (Slack Connect) = v1.x.

**Docs (wiki)** — Notion/Outline-style
- Spaces/collections, nested pages, real-time collab (Yjs), comments, mentions, embeds (issues, files, diagrams), templates, version history, publish/public link, export (MD/PDF), search. Whiteboards (v1.x).

**Drive**
- Folders/files, resumable upload, versions, share links (expiry/password), previews (image/video/PDF/office via Gotenberg optional), trash/restore, quotas, link files to objects. WebDAV read-only (v1.x).

**Calendar**
- Personal/team calendars, events (all-day/recurring), reminders, call link, shows sprints/leaves/interviews overlays, ICS export; CalDAV/Google sync (v1.x).

**HR** — Huly-like
- Employees (profile, employment, manager, department/position), **org chart** (ltree), departments, positions, leave types & balances, PTO requests + approvals (HR workflow uses the workflow engine), holidays calendar, work schedules, onboarding/offboarding checklists, employee documents, attendance/check-in (v1.x), reviews (v1.x).

**Recruiting / ATS**
- Vacancies, candidates/talent pool, applications → **pipeline stages** (kanban), interviews (calendar + call), scorecards, offers, public career page + apply form, resume upload + parsing (AI), email to candidate (Mail), GDPR retention (v1.x).

**CRM / Leads**
- Contacts, companies, leads, deals + pipelines (kanban), activities/notes/tasks, link emails (Mail) & calls, custom fields, web-to-lead form, imports (CSV), reports (pipeline/forecast lite).

**Automation & Process**
- Rules: trigger (object created/updated/transitioned/commented/scheduled/manual/incoming webhook/email received) → conditions (field/KQL/user/compare) → actions (registered by each module: edit, transition, assign, comment, create, send message, send email, webhook, AI step, run script) → branches (for sub-items/related/KQL) + smart values `{{issue.key}}`; scope workspace/project; run log & retry; rule templates; sandboxed JS (isolated-vm). Visual builder UI.

**Mail**
- Outbound per workspace: SMTP / Mailgun / SES / Postmark / Resend provider, from-domain, templates (MJML), queue, bounces/suppression, test send; platform default fallback.
- **Personal inbox**: users add IMAP/SMTP (+ Gmail/Microsoft OAuth) accounts → folders, threaded conversations, compose/reply/forward, attachments (to Drive), labels, search, link email to issue/contact/candidate, "create issue from email"; headers-first sync + on-demand bodies.
- Intake addresses (`intake+token@…`) → tracker/recruit/CRM.

**Calls** — LiveKit
- 1:1 & group audio/video from chat/calendar/interview, screen share, huddle in channel, virtual office rooms (v1.x), recording (v1.x).

**AI assistant (BYO key)** — OpenAI/Anthropic/OpenAI-compatible/Ollama
- Summaries (thread/issue/doc/email), drafting (issue, reply, doc), semantic search (pgvector), `@kern` chat bot, triage suggestions, resume parsing, automation "AI step". Per-workspace keys & toggles; no data leaves unless configured.

---

## 4. Architecture

### 4.1 Repos & services (GitHub org `KernAIO`)

> This table is the layout as planned, and the names moved: the umbrella is `app`, the front end is
> `shell`, `KernAIO/modules` was split into one repository per module and archived on 2026-08-25,
> and `KernAIO/cloud` was never created. For what exists today, read the table in `README.md` or run
> `node scripts/repos.mjs`.

| Repo | Type | Purpose |
|---|---|---|
| `KernAIO/kern` | umbrella | Project face: README, **self-host** (`docker-compose.yml`, profiles, `install.sh`, Caddyfile), architecture/ADR docs, **dev workspace** (`pnpm-workspace.yaml` linking sibling clones), release manifests, issue templates, CLA. |
| `KernAIO/app` | service | SvelteKit PWA (moved from `mirzaaghazadeh/Kern`). Hosts every module's `client` part. |
| `KernAIO/core` | service | Fastify + kernel runtime. Hosts: identity/auth (Better Auth), workspaces, members, roles/permissions, notifications, settings, files, search, webhooks, importers + modules: tracker, hr, recruit, crm, time, calendar, automation, docs(meta), drive(meta), ai, calls. Also ships `worker` entrypoint (pg-boss). |
| `KernAIO/chat` | service | Kernel runtime hosting **chat** module + **realtime gateway** (WebSocket hub for ALL modules, presence, typing, push fan-out). |
| `KernAIO/mail` | service | Kernel runtime hosting **mail** module: IMAP sync (imapflow, IDLE), outbound providers, inbound intake. |
| `KernAIO/collab` | service | Hocuspocus (Yjs) server for docs/rich text; persists Y.Doc to Postgres, snapshots for search. |
| `KernAIO/kernel` | library | `@kernhq/kernel` (module SDK/runtime, event bus, authz, jobs, settings, search/file/mail provider interfaces), `@kernhq/contracts` (Zod schemas, oRPC contracts, event types, permission keys), `@kernhq/ui` (Svelte design system), `@kernhq/sdk` (typed API client for app & 3rd parties), `@kernhq/testing`. |
| `KernAIO/modules` | library | First-party modules monorepo: `@kernhq/module-<id>` each exporting `/contract`, `/server`, `/client` (+ `/migrations`). Community modules follow the same shape in their own repos. |
| `KernAIO/docs` | site | docs.kern… (SvelteKit/Starlight), module dev guide, API reference (from OpenAPI). |
| `KernAIO/cloud` (private, later) | — | Billing/SaaS control plane, enterprise features. Out of v1 scope. |

**Why these service boundaries**: chat/realtime (persistent WS connections, different scaling), mail (long-lived IMAP connections, crashes isolated), collab (CRDT WS, CPU profile). Everything else shares one process in `core` (split later by moving a module to a new host — the kernel makes this config).

### 4.2 Kernel & module system (plug-and-play)

- `defineModule({ id:'kern.tracker', version, dependsOn, permissions, settingsSchema, events, ... })` → one manifest per module; JSON-exportable (admin UI, CLI).
- **Server extension points** (`/server`): oRPC routers (mounted at `/api/<module>`, auto-OpenAPI), Drizzle schema in **own Postgres schema `mod_<id>`** + migrations, event handlers (subscribe), event emitters, jobs (pg-boss handlers + cron), permission keys, search indexers, automation triggers/conditions/actions, notification types/renderers, webhooks, importers/exporters, object types (for mentions/links/object channels).
- **Client extension points** (`/client`): routes under `/(app)/[workspace]/<module>`, nav items, command-palette actions, object presenters (Huly-style: how an issue/candidate renders inline anywhere), slots (sidebar widgets, right-panel tabs, settings pages, notification renderers, chat message actions), i18n messages, keyboard shortcuts.
- **Loading**: build-time static registry in each host (`kern.modules.ts` lists packages) → tree-shaken, typed. **Per-workspace enable/disable** via `workspace_modules` (gates routes→403, nav, jobs, search). Core modules always on. **No runtime-loaded 3rd-party code in v1**; 3rd parties get: the same package shape (custom build), public API + webhooks + OAuth apps, and an iframe/web-component "remote UI" slot.
- **Cross-module access only through contracts**: `kernel.call('kern.core.users.get', …)` = in-process when co-hosted, NATS request/reply when remote (transport-transparent). Each module's DB role is granted only its own schema → no cross-schema SQL; microservices-ready boundaries inside one Postgres.

### 4.3 Data & tenancy

- Postgres 18 (single cluster; default one DB `kern`; chat/mail can be pointed to their own DBs via config). Per-module schemas. Every tenant table has `workspace_id` (uuidv7 PKs) + **RLS** (`SET LOCAL app.workspace_id`) as defense-in-depth; composite indexes `(workspace_id, …)`.
- Global (non-RLS) tables: `users`, `sessions`, `workspaces`, `memberships`, `notifications(user_id, workspace_id)`, `push_subscriptions`, `api_keys`.
- Custom fields: metadata tables (`field_defs`) + JSONB `custom` column + expression indexes; KQL compiles to SQL over both.
- Activity log (`activity_events`, partitioned by month, pg_partman) is the source for history, feeds, automation, webhooks, search indexing (outbox pattern).
- Extensions: pgvector, pg_trgm, ltree, pg_partman. Jobs: pg-boss. Cache/presence/rate-limit: Valkey. Inter-service bus: **NATS JetStream** (events `kern.<ws>.<module>.<event>`, req/reply, KV for presence).
- Files: MinIO/S3, presigned GET, tus for uploads; thumbnails via sharp/ffmpeg in worker; Gotenberg optional.
- Search: `SearchProvider` interface; v1 = Postgres FTS + trigram; Meilisearch provider v1.x.

### 4.4 Auth & permissions

- Better Auth in `core` (Drizzle adapter): email/password, magic link, OAuth, passkeys, 2FA, organization(=workspace)/invitations, multi-session, API keys, SSO (OIDC/SAML), JWT plugin → JWKS. Other services verify JWTs (claims: user id, workspace memberships/roles version) — no shared session store needed; membership changes bump a `perm_version` so tokens refresh.
- Authz engine in kernel: `can(user, 'tracker.issue.edit', {workspace, project, object})` resolving bindings along the scope chain + object-level overrides; effective sets cached in Valkey per (user, workspace) & invalidated on change. Modules declare keys; UI gets a `permissions` snapshot for conditional rendering. OpenFGA swap-in kept possible via the interface.

### 4.5 Realtime, notifications, PWA

- One WS (`/ws`) to `chat` service per client; server-side subscription = user's workspaces; events `{ws, module, entity, id, op, patch?}` → client TanStack Query invalidation/patching; chat messages/presence/typing streamed directly. NATS fan-out between instances.
- Notifications: module emits typed notification → rules/prefs → in-app row + push (web-push; declarative payload for iOS) + email digest (Mail module) → unified inbox UI.
- PWA: `@vite-pwa/sveltekit`, app-shell precache, API NetworkFirst, install CTA + iOS sheet, badge counts, deep links, offline read cache for recent issues/chats (v1), Capacitor/Tauri wrappers post-v1 (client built to also run as static SPA).

### 4.6 Automation & workflow engines (kernel services used by modules)

- **Workflow engine** (generic state machine: statuses, transitions, conditions/validators/post-functions, approvals) used by Tracker, HR leave, Recruit pipeline, CRM deals.
- **Rule engine**: JSON DSL persisted per scope; activity events → NATS → `automation` evaluator (worker) → actions via module registries; scheduled triggers via pg-boss cron; runs table w/ idempotency; isolated-vm for scripts with CPU/mem limits and capability-scoped API.

### 4.7 Mail architecture

- `MailProvider` (smtp/mailgun/ses/postmark/resend), per-workspace config encrypted (AES-256-GCM envelope keys; master key from env), send queue w/ retries, provider webhooks → `email_events` + suppression.
- Inbox: `mail` service keeps one IDLE connection per active account (capped; polling fallback), stores folders/envelopes/flags/UID/MODSEQ in Postgres, bodies/attachments on demand → MinIO cache; OAuth2 Gmail/Microsoft; compose via account SMTP. Intake: plus-address tokens + `In-Reply-To/References` threading → comments; Message-ID dedupe.

### 4.8 Frontend design (decided)

- **Look**: Linear/Huly-class density; neutral zinc palette + single accent (Kern indigo), light/dark/system; Inter (Latin) + Vazirmatn (fa/ar) with logical CSS props for RTL; 12px/13px UI type scale; subtle borders, no heavy shadows.
- **Shell**: workspace rail (switcher w/ badges) › module sidebar › content › optional right panel (details/thread); global cmd-K (navigate, create, actions, search); single-key shortcuts; right-click context menus; drag-and-drop boards; virtualized lists; optimistic updates; skeletons not spinners; toasts w/ undo.
- **Stack**: Svelte 5 runes, SvelteKit 2.70 (→3 when stable), Tailwind v4, shadcn-svelte/Bits UI 2, TanStack Query 6, `@tanstack/svelte-virtual`, `svelte-dnd-action`, Tiptap 3 (+Yjs), LayerChart, Paraglide (en, fa, ar, de initially), `@internationalized/date`.

### 4.9 Self-host (what everyone installs)

`KernAIO/kern`: `install.sh` (generates `.env` secrets, domain, pulls images) + `docker compose` profiles:
- base: `caddy, app, core, core-worker, chat, mail, collab, postgres(18, pgvector image), nats, valkey, minio`
- `--profile calls`: livekit (+turn) · `--profile preview`: gotenberg · `--profile search`: meilisearch (v1.x) · `--profile observability`: glitchtip + otel collector
- Caddy routes: `/` → app, `/api/chat/*`,`/ws` → chat, `/api/mail/*` → mail, `/collab` → collab, `/api/*` → core. Single domain, auto-HTTPS.
- Images published to GHCR per repo on tag; `kern` repo pins versions per release.

### 4.10 Dev workflow (solo + Claude, multi-repo)

- `KernAIO/kern` = dev workspace: `scripts/dev-setup.sh` clones `app core chat mail collab kernel modules docs` into `repos/` (gitignored); root `pnpm-workspace.yaml` = `repos/*`, `repos/kernel/packages/*`, `repos/modules/packages/*` → pnpm links everything; `docker compose -f dev/compose.yml` runs infra only; `turbo dev` runs services with hot reload. Each repo also builds standalone in CI using published `@kernhq/*` (`^0.x`).
- Shared libs: Changesets + automated prerelease publish to npm (`@kernhq`) on every merge to `main` in `kernel`/`modules`; Renovate keeps consumers bumped.
- Tooling everywhere: Node 24, pnpm 10, Turborepo, TypeScript strict, Biome, Vitest, Playwright (app), Testcontainers (core), Conventional Commits, GitHub Actions (lint/test/build/image), Dependabot/Renovate.

---

## 5. Roadmap (8 weeks + 2 buffer) — milestones are demoable

**Phase 0 (days 1–3) — Org & skeleton** ← immediate next steps on approval
1. Verified: `gh` is logged in as `mirzaaghazadeh` with `admin:org`; org `KernAIO` exists; `KernAIO/app` already exists (private, empty). Create the remaining repos (`kern, core, chat, mail, collab, kernel, modules, docs`) via `gh repo create KernAIO/<name> --private` (private while building; flip all to public at v1.0 or whenever the owner says), each with AGPL-3.0 `LICENSE`, README, `CLA.md`, `.github/` (issue/PR templates, CI), `main` branch protection. Push the initial skeleton to `KernAIO/app`. Claim npm org `kernaio` (owner does this on npmjs.com; `@kernhq/*` currently unpublished).
2. `kernel`: `@kernhq/kernel` (defineModule, registry, event bus w/ in-proc+NATS, authz, jobs, settings, provider interfaces), `@kernhq/contracts`, `@kernhq/ui` (tokens, primitives), `@kernhq/sdk`; Changesets + publish workflow.
3. `core`: Fastify + oRPC + Drizzle + Better Auth; migrations runner (per-module schemas); users/workspaces/memberships/invites/roles/permissions; OpenAPI at `/api/docs`; worker entrypoint.
4. `app`: SvelteKit shell, auth flows, workspace switcher, cmd-K, i18n+RTL, PWA manifest/SW, theme; module client loader.
5. `kern`: dev workspace scripts, infra compose, self-host compose + Caddy + install.sh; CI templates for all repos.

**Week 1 — Platform core**: notifications (inbox + prefs), realtime gateway in `chat` (WS + NATS), files (MinIO/tus), search provider, activity log, admin console, settings pages, audit log, webhooks, API tokens.

**Weeks 2–3 — Tracker**: types/hierarchy, custom fields, workflow engine, issues CRUD + rich editor, list/board/calendar/timeline/spreadsheet views, KQL + saved views, cycles/milestones/releases, relations, comments, watchers, triage/intake, reports, time tracking, templates, bulk ops, keyboard-first UX, Jira/Linear/CSV import. *(largest module; highest bar)*

**Week 4 — Chat**: channels/DM/threads/reactions/mentions/read-state/pins/search/files/presence/typing/push, object channels (per issue etc.), slash commands, bots/webhooks, calls entry points.

**Week 5 — Docs, Drive, Calendar, Automation**: collab service + Tiptap/Yjs docs, versions, publish; drive (folders/versions/share/previews); calendar events + overlays; rule engine + visual builder + scheduled rules + scripts.

**Week 6 — HR, Recruiting, CRM**: employees/org chart/leave w/ approvals/onboarding; vacancies/candidates/pipeline/interviews/career page; contacts/companies/deals/activities; custom fields reuse; object channels & docs links.

**Week 7 — Mail, AI, Calls**: outbound providers + templates + bounces; IMAP/OAuth inbox + compose + link-to-objects + intake→issue; AI module (providers, summaries, drafting, semantic search, @kern bot, automation step); LiveKit calls/huddles.

**Week 8 — Release hardening**: perf (virtualization, N+1, indexes), security review (RLS tests, authz matrix tests, rate limits, CSRF/headers, secrets), e2e suites, a11y pass, fa/ar RTL QA, docs site (install, admin, module dev guide, API), demo data seeder, upgrade/backup scripts, v1.0.0 tag + GHCR images + install one-liner.

**Buffer (weeks 9–10)**: v1.x items above (shared channels, Meilisearch, WebDAV, CalDAV/Google sync, SCIM, GitHub integration, virtual office/recording, whiteboards), Capacitor/Tauri shells.

---

## 6. Verification (how we know each phase works)

- Every repo: `pnpm lint && pnpm typecheck && pnpm test` in CI; `core` integration tests with Testcontainers (Postgres/NATS/MinIO), authz matrix tests (role × permission × scope), RLS leak tests (query as ws A, expect zero rows of ws B).
- `app`: Playwright e2e per module (create workspace → invite → create issue → move on board → chat mention → notification appears in other workspace's inbox → email sent via Mailpit); Lighthouse PWA ≥ 90; RTL screenshot tests.
- Self-host: `docker compose up` on a clean VM from `KernAIO/kern` → onboarding wizard → all modules smoke-tested; upgrade path `v1.0.0 → v1.0.1` runs migrations; backup/restore script tested.
- Load: k6 on chat WS (5k connections/instance) & tracker list queries (<150 ms p95 at 100k issues/workspace).

---

## 7. Risks & open items

- Scope vs time: tracker + chat + mail inbox are each multi-week products; the plan sequences them so that at any checkpoint there's a coherent, releasable subset. If week 8 slips, release with clearly flagged "preview" badges on the least mature modules rather than cutting them.
- Multi-repo friction: mitigated by umbrella workspace + automated prereleases; rule: **change contracts first, publish, then consumers** (Claude will follow this order).
- npm scope `@kernhq` and GHCR namespace must be claimed early (Phase 0).
- iOS push limits (install required) — handled with declarative push + email fallback.
- Licensing of deps: all chosen libs are MIT/Apache/BSD (Valkey BSD, NATS Apache, LiveKit Apache, Hocuspocus MIT, Better Auth MIT, Drizzle Apache). EmailEngine (commercial) deliberately avoided → imapflow directly.
