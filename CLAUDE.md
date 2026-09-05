# CLAUDE.md — Kern project rules

Rules for anyone (human or AI agent) working on Kern repositories. These apply to every repo in the KernAIO org.

## We build in the open
The repositories are **public**, so every commit is visible the moment it is pushed:
- Never commit secrets, tokens, personal data, or machine-specific paths. Use `.env` (gitignored) + `.env.example`.
- Write READMEs, docs, and issue/PR text for external contributors, not for ourselves.
- Keep commit history clean and meaningful — it is part of what people judge the project by.
- Every repo carries LICENSE, CLA.md, CODE_OF_CONDUCT.md, SECURITY.md, CONTRIBUTING.md.
- **Two licences, split at the framework boundary.** The `kernel` repo and `modules`'
  `workflow` are **Apache-2.0**, as is `KernAIO/module-template` in its own repository, so anyone can
  write a closed module; the product —
  `shell`, `core`, `chat`, `mail`, `collab`, `docs`, this umbrella, the first-party modules — is
  **AGPL-3.0-only**. A new package inherits its repo's licence unless it is something a third-party
  module must import, and then it is Apache-2.0 with its own LICENSE file. Apache-2.0 packages take
  only permissive dependencies. If a module author has to import an AGPL package to get something
  done, move the API — never the licence. See `LICENSING.md` and
  `docs/adr/0005-licensing-and-the-module-boundary.md`.
- **A permissive licence nobody can reach is not a permissive licence.** `@kernhq/module-template`
  carried `private: true` for months, so the only way to get the Apache-2.0 template was to clone an
  AGPL repository containing six AGPL modules. It is published now. Anything on the Apache side a
  third party is *meant to start from* has to be installable, not merely licensed — check that before
  calling the boundary done. `@kernhq/workflow` is the other Apache-2.0 package here and it is
  genuinely used — `module-tracker` imports it for workflow definitions, approval state and status
  categories.

## Git
- Author identity: `Navid Mirzaaghazadeh <mirzaaghazadeh@icloud.com>` (already set in each repo's local git config — plain `git commit` is correct; do not override with `-c`).
- **Do not add `Claude-Session:`, `Co-Authored-By: Claude`, "Generated with", or any AI trailer/branding to commit messages, PRs, or code comments.**
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, with optional scope). Imperative mood, ≤ 72-char subject.
- Push to `origin main`. Never force-push. If `git pull --rebase` complains about unstaged files that aren't yours (parallel agents share worktrees), use `git -c rebase.autoStash=true pull --rebase`.
- **Never `git add -A` or `git add .`. Stage the paths you changed, by name.** Several agents share
  these checkouts, and another one is very often part-way through a new package in the same repo.
  `git add -A` sweeps their half-finished files into your commit and pushes them — under your commit
  message, without their lockfile entry, so CI fails at install for everyone. It happened on
  2026-08-24: a contact-address fix carried two unfinished modules into `main`. Run
  `git status --porcelain` first and stage from it; if you cannot name every path you are about to
  commit, you are not ready to commit. When it does happen, do not revert the other agent's files —
  they are still working on them; tell them instead, and repair what you broke.
- **`git checkout --` and `git restore` are as destructive as `git add -A`, and in the same way.**
  They act on a *path*, not on an author, so undoing your own edit to a file throws away whatever
  else is in it. On 2026-08-26 a range sweep over-bumped some versions and undid itself with
  `for d in repos/*/; do (cd $d && git checkout -- package.json); done` — fifteen repositories at
  once, without looking at any of them first. It discarded another session's uncommitted
  `exports["./contract"]` repoint and its new `pg` devDependencies, and only that one session lost
  work because the other fourteen files happened to be clean. Undo by re-editing the specific keys
  you changed. If you must discard, run `git status --porcelain` first and stop when the file is
  dirty for a reason that is not yours — the same sentence as the `git add -A` rule above, and it is
  the same mistake pointed the other way.
- **Never ask permission to commit, branch, push, pick a version bump, or cut a release** — all of
  it is yours, every time, and asking hands the work back. Release when the work is actually finished
  and green, then report what shipped; the bar for "finished" does not move because nobody is
  approving it. The only things still off-limits unasked are force-push, rewriting history, deleting
  a branch or repo, and changing org settings. See the `kern-ship` skill.

## Layout & workflow
- Umbrella dev workspace: `app/` with sibling repos cloned under `app/repos/<name>` (gitignored there). pnpm links all `@kernhq/*` packages via the umbrella workspace.
- Install dependencies ONLY via `app/scripts/pnpm-install-locked.sh` (serialises pnpm at the umbrella root).
- Node 24 (`nvm use 24`), pnpm 10, TypeScript ~5.9, ESM/NodeNext, Biome for lint+format (run `pnpm exec biome check --write <paths>` before committing), Vitest.
- Contracts first: changes to `@kernhq/contracts` / module contracts land (and build) before their consumers.
- **One version for the platform.** Every image and every module in an instance carries the same
  `KERN_VERSION`, baked in at build time; npm versions are a packaging unit, not something a customer
  installs. A module's manifest version comes from `packageVersion(import.meta.url)`, never a literal
  — the literals drifted for months and every admin was shown the wrong version. See
  `docs/adr/0002-platform-versioning-and-updates.md`.
- **`@kernhq/kernel` and `@kernhq/contracts` are `peerDependencies` of every module, not
  `dependencies`.** A plain dependency lets npm hand a module whatever kernel copy the host resolves,
  even one the module was never built against — the range existed but nothing read it. Declaring it a
  peer is what makes that combination *stateable*; it does not make anything check it. **pnpm does
  not enforce it, and we assumed for months that it did.** A clean registry install of `chat`'s
  manifest outside the workspace resolved `@kernhq/module-chat@0.4.8`, whose contracts peer is
  `^0.6.1`, against `contracts@0.5.2` — exit 0, no warning — in a repository setting
  `strict-peer-dependencies=true`, because `auto-install-peers=true` satisfies the peer from whatever
  the host already asked for. So the check lives in `check-ranges.mjs`: it reads the published peers
  of every `@kernhq/module-*` a package depends on and holds the package's own ranges to them. It
  reports *who is behind* — a module still peering last month's contracts is the thing to republish,
  never the host to move down, because a host installs one copy and lowering it drags every other
  module with it. `pnpm.overrides`
  still forces one resolved kernel copy per process — that is a different job (no two kernel
  instances) from the peer check (is the one instance right for what depends on it), and both are
  still needed. This is also what makes `renovate.json`'s existing `@kernhq/*` automerge safe to lean
  on: a module version bump merges the day it is compatible with the kernel already pinned, and stays
  red — not silently wrong — until the kernel catches up. See
  `docs/adr/0009-independent-kernel-and-module-release-cadence.md`.
- **Every migration must leave the database readable by the image before it.** Add nullable columns
  and new tables; drop and rename one release later. This is what makes rolling an image back work
  without restoring a dump, and on cloud a rolling deploy runs both images against one schema on
  purpose. A release that cannot follow it is marked `schemaChanges: breaking` in the release feed.
- **Every migration must survive being applied twice, and the test has to replay the SQL.**
  `create policy` and `add constraint` have no `if not exists` at all; `create table` and
  `create index` do not get one unless you write it. So a replay throws — and a module migration
  that throws takes down the **whole host service**, not just its own module. `core` hosts five, so
  one module's replay is an outage for the other four. A replay is not hypothetical: drizzle keys
  applied migrations by content hash, so *editing a migration file* makes every file in the folder
  run again against schemas that already have their objects. Every first-party module is guarded now
  and each carries `src/server/migrations.test.ts`, which applies the folder to a database created
  from nothing, applies it a second time, and asserts each policy exists once. Calling
  `migrateModule` twice proves nothing: the second call reads `__migrations`, sees the work is done
  and returns.
  Two things a blanket edit gets wrong, both found by doing it: a migration already made idempotent
  with a `do $$ … end $$` catalogue check must not have a `--> statement-breakpoint` inserted into
  its dollar-quoted body, and `ALTER TABLE … ADD PRIMARY KEY` needs a name and a
  `drop constraint if exists` like any other constraint.
  When a migration is wrong, **regenerate it from the drizzle schema rather than patching the SQL by
  hand** — that is what puts a composite primary key inline in `CREATE TABLE IF NOT EXISTS`, where it
  inherits the guard, instead of emitting the unguarded `ALTER TABLE … ADD PRIMARY KEY` that a hand
  patch produces. `mod_inventory.counters` avoided repeating its own defect this way and only by
  luck: the fix for "multiple primary keys are not allowed" would otherwise have shipped as a second
  unguarded primary key on the same table.
- **A stale snapshot makes `db:generate` re-emit what hand-written migrations already built.**
  Every hand-written migration (RLS, a sequence, a repair) leaves `migrations/meta` where it was, so
  the next generate diffs `schema.ts` against a snapshot several migrations old and emits an
  unguarded `CREATE UNIQUE INDEX` and `ADD COLUMN` for objects every existing database already has
  — a 42P07 during the module's own migration, which is a host service that never binds its port.
  `module-inventory`'s 0009 came out of the generator three objects too long. Keep the snapshot the
  generator wrote (it is the first current one), cut the SQL down to what is actually new, guard
  it, and run `scripts/check-snapshot-drift.mjs` — that check is the only thing that proves the
  snapshot and the database describe the same thing, and every module that hand-writes a migration
  should carry it (`module-hr` and `module-inventory` do).
- **Idempotent is not the same as effective, and the second one has no guard.** A replayed
  `create table if not exists` reports success and changes nothing, so a *rewritten* migration
  silently leaves an existing schema exactly as it was — the boot failure is gone and the change
  never happened. Nothing detects this: the migration is recorded as applied and the service starts.
  Rewriting a migration rather than adding a new one means `drop schema mod_<id> cascade` on every
  database that already ran it, which is only acceptable before anyone depends on the data. After
  that, add a migration.
- **A migration that has only ever run against your dev database has not been tested.**
  `module-inventory`'s `0001_rls.sql` copied HR's custody exclusion constraint
  (`exclude using gist (asset_id with =, tstzrange(...) with &&)`) without HR's
  `CREATE EXTENSION IF NOT EXISTS btree_gist`. On any clean database that fails with "data type uuid
  has no default operator class for access method gist" — and it fails during the module's own
  migration, so the *service does not start*. It was invisible because every database it had ever
  run against already had the extension. Core's `0000_init.sql` creates `pg_trgm`, `pgcrypto`,
  `ltree` and `vector`, and `btree_gist` is not among them: a module reaching for a gist exclusion
  constraint declares the extension itself. Verify a migration on a scratch database created from
  nothing.
- **A module migration that is not idempotent takes down every module in the host service.** The
  kernel migrates each module at boot, so one that throws does not degrade its own feature — `core`
  hosts five and never binds :4000. `create policy` has no `if not exists`, so **no** module's
  `0001_rls.sql` can be re-run today; inventory is only the one that got caught, because
  regenerating `migrations/meta/_journal.json` gives every entry a `when` newer than the rows in
  `mod_<id>.__migrations` and drizzle therefore replays files that have already been applied. Put a
  `drop policy if exists` before every `create policy` and a `drop constraint if exists` before
  every `add constraint`, and prove it by applying the whole folder **twice in a row** to one
  database. Note the second half of the trap: a replay of `0000_init.sql` is all `create … if not
  exists`, so it reports success and adds nothing — an old schema stays old, silently. A rewritten
  migration needs `drop schema mod_<id> cascade` on every existing database, and after the first
  tagged release it is not an option at all.
- **Two column-level `.primaryKey()` calls are not a composite key.** Drizzle emits `PRIMARY KEY` on
  both columns and Postgres refuses the table — "multiple primary keys for table are not allowed",
  SQLSTATE 42P16. Because a module's migration is the first thing the kernel runs, the symptom is
  not a broken table but a host service that will not boot: `core` never binds :4000 and everything
  that talks to it is down. Use `primaryKey({ columns: [...] })` in the table's second argument.
  `mod_inventory.counters` had this.
- **A descending index column is `t.at.desc()`, never `desc(t.at)`.** They read identically and only
  one is an index definition: `desc()` is the *query* helper, so drizzle records it in the snapshot
  as a SQL expression — `("created_at" desc)` — which Postgres will not build. The emitted
  `CREATE INDEX` is valid either way, so the migration applies and the database is right; it is the
  snapshot that is wrong, which means `db:generate` proposes the index again for ever and nothing
  else notices. `check-snapshot-drift.mjs` is the only thing that catches it, because it asks
  Postgres to build what the snapshot describes — which is the whole reason that script exists.
  `mod_hr.sensitive_access_log` shipped with it in review.
- **A migration journal entry's `when` must exceed every entry before it.** Drizzle reads the highest
  `created_at` already in `__migrations` **once**, before its loop, then applies every entry above
  it — so an entry with a lower timestamp is not applied late, it is skipped permanently, silently,
  and *only on databases that already exist*. A fresh database has no floor to fall below, so every
  developer machine, all of CI and every new install agree that nothing is wrong.
  `0009_beyond_cap_minutes` sat a day below `0007` and would never have reached a deployed instance;
  `module-hr`'s `src/server/journal.test.ts` is the guard, and is worth copying into any module that
  hand-edits a journal.
- Modules own their data: Postgres schema `mod_<id>`, `workspace_id` + RLS on every tenant table, cross-module access only via `kernel.call()` and events. See `modules` repo `packages/_template`.
- **"Every first-party module is guarded" was true of five.** `chat` and `mail` had no
  `migrations.test.ts` at all, and both folders threw on replay — eleven bare `CREATE TABLE`s in
  chat, seven statements in mail — while the sentence above this one said otherwise. And `mod_mail`
  had **no row-level security on any table**: `0001_notes.sql` argued that nullable `workspace_id`
  and hand-written `where` clauses made it unnecessary. Both found on 2026-09-04 by writing the
  tests rather than reading the claim. The catalogue is the only honest audit: ask `pg_class` for
  every table in `mod_*` with a `workspace_id` column and no forced policy — on a database created
  from nothing, because the dev database's schema was built before half the policies existed and
  says `counters` is unsecured when the migration secures it. Each module's `migrations.test.ts`
  asks that question now. The tables still deliberately outside a policy, with the reason, are in
  `TODO.md` slice 5.
- **A table that legitimately serves every workspace at once binds `'*'`, never nothing.** Chat's
  policies admit `app.workspace_id = '*'` for the gateway's cross-workspace checks, and mail's do
  the same for the send job, the provider webhooks and the suppression check. The alternative —
  a policy that admits an *unbound* transaction — makes forgetting to bind a leak instead of a
  refusal. A consumer that has to work against the module version from before the policy (the
  `mail` service did, for one nightly) writes the sentinel locally rather than importing it.
- **A hand-typed count in a mock manifest breaks `main` the day the reach moves the module.**
  Shell's `mock.ts` said inventory had five permissions; the nightly reached 0.5.0, which has six,
  and `mock-manifests.test.ts` went red on `main` with nobody having touched the file. Read counts
  off the module contracts (`inventoryPermissions.length`); the test that pins them exists so the
  demo does not lie, not so a literal can be maintained by hand.
- **A third-party module is a build argument, not a fork.** `KERN_EXTRA_MODULES` on the `shell` and
  `core` Dockerfiles installs the packages and `scripts/extra-modules.mjs` rewrites the one
  committed file each host reads them from (`src/lib/modules/extra.ts`, `src/extra-modules.ts`);
  both entry points of a module export it as `default`, which is what the generator imports.
  `KERN_IMAGE_SHELL` / `KERN_IMAGE_CORE` in `.env` point a stack at the pair. Locally the same
  generator wires a module linked under `repos/`; `core` reads its `dist/`, so build the module
  first. Verified by building both images with `@kernhq/module-template@0.2.9` inside.
- **A module ships its own screens, and `shell` ships only the shell.** Contract, server, pages,
  widgets, strings and manifest are one package; deleting it removes the feature completely. The
  wiring outside it is two lines — `featureModules` in a host service, `registerModule` in shell's
  registry. A module cannot import `shell`, so everything its screens need comes from `@kernhq/ui`:
  **stateless things are exported** (`t`, formatters, query keys, components, charts) and **stateful
  things are read from a singleton the shell fills** (`session`, `navigation`, `getHost`). Three
  mistakes compile while you edit inside `shell` and fail the moment the package builds alone, and
  all three shipped: importing `$app/state`, importing your own barrel, and a local called `t`
  shadowing the message function. Each module package type-checks its own client — that is the only
  thing that sees them. See `docs/adr/0008-a-module-ships-its-own-screens.md`.
- **A local named after a rune deletes the rune.** `const state = $derived(query.data)` and then
  `let busy = $state(false)` in the same file: Svelte reads the second `$state` as a store
  subscription to the first, and `svelte-check` says "Cannot use 'state' as a store", which sounds
  like a store problem and is not. Same shape as the `t` shadowing above — `state`, `props`,
  `derived` and `effect` are all names worth avoiding for a local in a component.
- **`disabled={mutation.isPending}` does not stop the second click.** The attribute reaches the
  button on the next render, and two quick clicks are one render apart — so a double-click on
  *clock in* files two punches, and on an approval files two decisions. Set a plain `$state` flag in
  the same tick as the click, guard on it before calling `mutate`, and clear it in `onSettled`.
- **A page's class name can land on a component's inner element, and a `flex-basis` becomes a
  height.** `ReportsPage` styled its filters with `.controls :global(.ctl) { flex: 0 1 160px }`,
  and `Field` names its own control wrapper `.ctl` — a column — so every filter was 160px tall and
  a blank band sat between the filters and the report. Nothing fails: it is a valid layout. Name
  page-level classes for the page (`.filter`), and when a screenshot shows empty space, measure the
  element's children rather than reading the CSS.
- **Stripe sends `invoice.paid` for a new subscription's first invoice *before*
  `checkout.session.completed`.** A checkout started here writes the Stripe customer onto the
  subscription row before Checkout opens, so a customer lookup holds on the normal path — the
  cloud's first purchase was diagnosed as having lost its invoice on this theory and had not; the
  row was there, 7 ms after the event. Read the cloud's tables before naming a cause. The order
  still matters for a subscription made in the Stripe dashboard or an instance whose row is behind:
  the invoice carries `parent.subscription_details.metadata` (`kern_workspace_id` included), so
  read that first, and never answer 2xx to an event you did not apply. And one Stripe sandbox
  delivers every event to every endpoint on the account — a dev-machine checkout wrote an invoice
  for a workspace the cloud does not have, with a 200 and no log line, because nothing checked the
  workspace existed. `Intl.DateTimeFormat.formatRange` is the other trap of the day: given two instants
  on different days it prints both dates in full even when asked only for hours, which is how an
  overnight shift read "1/1/2024, 10:00 PM – 1/2/2024, 6:00 AM".
- **Disabling the control somebody is standing on throws their focus to `<body>`.** The browser
  blurs a focused element the moment it becomes disabled and hands focus nowhere; nothing gives it
  back, so a keyboard user who toggles a switch loses their place on the page and has to tab from
  the top. Measured on the capabilities switchboard, on every toggle. Where a control must not be
  pressed twice, guard the handler rather than disabling the control — `aria-busy` says the same
  thing to a screen reader without moving anything.
- **A module is the coarse switch; a capability is the one below it.** A module different customers
  want *different amounts* of declares capabilities — named sub-features with dependencies that a
  workspace switches, off for everyone rather than for one person. A disabled one answers **404, not
  403**: `forbidden` says the surface exists and you may not have it, which is false for a workspace
  that never enabled the feature, and it contradicts a shell that already hid the navigation.
  Switching one off must never destroy data — it is a flag in module settings, so anything needing a
  migration to reverse is not a capability. It is neither a permission (about a person) nor an
  entitlement (about a plan): a self-hosted instance has unlimited entitlements and still needs the
  switchboard. See `docs/adr/0007-module-capabilities.md`.
- **A widened shared contract is additive for *parsing* and breaking for *constructing*.** A new
  field with `.default([])` keeps every already-published manifest validating, which is the test
  everyone applies — but zod's inferred **output** type makes it required, so every service that
  builds one of those objects stops compiling. `capabilities` did exactly that to core, and CI
  could not see it because core's range said `^0.2.0` and a caret on 0.x does not cross a minor:
  CI resolved 0.2.x while every local build used 0.5.0. When you widen a contract, grep for the
  places that *construct* the type, and bump the consumer's range in the same change — green CI on
  a stale range is not evidence.
- **Below 1.0.0, one optional field in `@kernhq/contracts` costs thirteen repositories as a minor
  and nothing as a patch.** Adding `archivedAt` to `WorkspaceSummary` is as additive as a change
  gets, and "new field → minor" is the correct semver reflex and the wrong answer here: the
  changeset said minor, contracts published 0.8.0, and because a caret on 0.x does not cross a
  minor that one word invalidated **every** `contracts` range in the organisation at once. It went
  red in all eight `module-*` repos and all five services — and those repos are not merely red but
  *untested*, because `lint` runs first and `typecheck`, `test` and `build` never execute. The
  repair is the whole graph in order: republish all eight modules peering `^0.8.0` (2026-09-05:
  tracker 0.12.1, quire 0.17.1, hr 0.23.7, inventory 0.5.3, billing 0.5.16, chat 0.5.1, mail 0.6.2,
  template 0.2.12), *then* bump core, chat, mail, collab and shell — the module moves and the host
  never moves down, because a host installs one copy and lowering it drags every other module with
  it. Released as **0.7.1** the identical field would have been reached by every existing `^0.7.0`
  peer and every service range, and the fan-out would have been zero.
  **The exception, so nobody over-corrects:** a field consumers *construct* rather than merely parse
  is genuinely breaking and deserves the minor — zod's inferred output type makes a required field
  mandatory at every construction site. `.nullish()` is precisely what kept this one additive, and
  it is the thing to reach for when the intent is "new data flowing outward". Ask what a bump costs
  the graph before picking it.
- **A cache that is down must cost latency, never correctness.** `Authz.effective()` awaited the
  cache directly, so an unreachable Valkey threw ioredis' `MaxRetriesPerRequestError` out through
  `can()` and `core.workspaces.myPermissions` answered **500** — while `/api/health` stayed green,
  because nothing there touches Valkey. Shell fills `session.permissions` from that one call, so
  every permission-gated screen in the product rendered empty on an instance reporting itself
  healthy, which is the worst possible pairing for whoever is diagnosing it. Every cache call now
  goes through one guard: a failed read is a miss and the answer is computed, a failed write is a
  no-op, a failed invalidation is survivable because a cache nobody can reach serves nothing stale
  either. It deliberately does not narrow to connection errors — any throw from a cache is a cache
  that is not working, and a permission check is the last place to be clever about which. Test this
  class by **stopping the container**, not by stubbing a throw: the real client's error arrives from
  a different place than a hand-written one, and running it is what proves the stub was honest.
- **A row that is right and a list that hides it is a feature nobody can reach.**
  `scheduleWorkspaceDeletion` archives the workspace immediately, and `workspaceSummaries` filtered
  archived rows out — so the workspace vanished from `users.me()` the instant Delete was pressed,
  shell could no longer resolve the slug, and a sole-workspace owner returning a minute later was
  shown "Create your first workspace". The cancel route worked the whole time and the 30-day undo
  the terms promise was unreachable from inside the product. The existing test asserted on
  `workspaces.archivedAt` in the database and passed throughout. **Assert on what the session is
  told, not on what the table holds** — the two answer different questions, and only one of them is
  what the customer experiences.
- **A capability, a permission key and an entitlement key are all lies until something enforces
  them.** `kernel.entitlements` declares what a plan may limit — seats, storage, modules, SSO, audit
  retention, API rate — and each key has exactly one place in core that checks it. Plan *values* are
  data an admin edits; the key set is not. Adding a key means adding its enforcement in the same
  commit, or the pricing page starts promising things again. When nothing answers
  `billing.entitlements.get`, every workspace is unlimited: that is what every self-hosted instance
  does on every request, so it is the default path and must not throw.
  A capability nothing checks `requiresCapability` for, and a permission key no procedure asks
  about, fail the same way and for the same reason: a switchboard full of switches that change
  nothing teaches an administrator that the switchboard does not mean anything. Declare each of the
  three in the change that puts something behind it — `module-inventory` declares one capability,
  `core`, and adds none of the rest until something sits behind it.
  See `docs/adr/0003-billing-entitlements-and-cloud.md`.
- **Every module is its own repository, and `KernAIO/modules` is archived.** `module-tracker`,
  `module-chat`, `module-quire`, `module-hr`, `module-mail`, `module-billing`, `module-inventory`
  and `module-template` each hold one package with its own history, CI and release. The first-party
  seven are the ones Kern ships with and are meant to be read as much as run — a reference
  implementation that lives somewhere structurally special is not a reference, so they have the same
  shape as one written outside this organisation. `@kernhq/workflow` was never a module
  (Apache-2.0, depends only on zod) and moved into the `kernel` repo with the rest of the framework.
- **Range drift is now checked, because there is no single place left to fix it.** `check-ranges.mjs`
  runs in the `lint` of every repository that depends on `@kernhq/*` — all fourteen; it ran in eight
  of them until 2026-08-26, and `chat`, `collab`, `core`, `mail`, `shell` and `module-template` were
  the six where a range could drift unseen. It asks four questions, and they fail in four different
  places: can the range reach what is published (a caret on 0.x never crosses a minor, so `^0.7.0`
  stops reaching the framework the moment it becomes 0.8.0 — invisible locally, because the umbrella
  pins the workspace copies); is there anything published for it to install at all (a floor raised
  *past* the registry used to pass and then die at `ERR_PNPM_NO_MATCHING_VERSION`); does the
  committed lockfile still agree with the manifest; and do the modules this package hosts agree with
  the framework it declares. This broke CI twice on 2026-08-25 before the check existed, and the
  check found two more the first time it ran.
- **A version published minutes ago is invisible to `pnpm install` for a while, and `relock.sh`
  used to say nothing about it.** npm's CDN serves the abbreviated package document pnpm fetches
  stale after a publish (the full document at `registry.npmjs.org/@kernhq%2f<pkg>` already lists
  the version), and pnpm caches that stale copy in `~/Library/Caches/pnpm/metadata*`. So a reach
  right after a publish fails with `ERR_PNPM_NO_MATCHING_VERSION … latest release is <previous>`.
  On 2026-09-04 `relock.sh` swallowed that error, printed nothing, and a range bump was pushed to
  three services without its lockfile — CI red at install in all three. The script now fails
  loudly; when it does, evict the cached document and retry, or wait for the nightly, which
  reaches with fresh metadata. Never push a range bump whose relock did not print "refreshed".
- **Taking that advice is what breaks the lockfile, so the two go in one commit.** Editing a range in
  a repository that commits a `pnpm-lock.yaml` leaves it out of date with itself, and
  `--frozen-lockfile` compares *specifiers*, not resolved versions — so the next publish dies at
  install having built nothing, even though the tree did not change. On 2026-08-26 eight of the nine
  lockfile-committing repositories were in exactly that state at once and four module publishes had
  failed on it, each one caused by the range fix that preceded it. `check-ranges.mjs` checks the
  lockfile now, so the fix cannot cause the next failure.
- **The module template is its own repository.** `KernAIO/module-template` is Apache-2.0 and
  published as `@kernhq/module-template`; it was a package inside the AGPL `modules` repo, which
  meant the only way to get the permissive starting point was to clone six copyleft modules with it.
  `pnpm new-module` fetches the published package rather than keeping a second copy, so `pnpm
  new-module` and `npx degit KernAIO/module-template` produce the same module by construction. It is
  cloned into `repos/` and linked, so a platform change that breaks the template breaks it here
  first — which is what `kern-platform`'s checklist depends on.
- **The realtime socket exists at `welcome`, not at `onopen`.** A client sends `hello` and its
  `sub` back to back, so both frames arrive in one read and are dispatched while the gateway is
  still awaiting core for the principal — and a gateway that closes anything arriving before
  authentication rejects a *valid* session, at a rate set by network timing rather than by anything
  in the code. The client answered that by reconnecting, and because it reset its backoff on
  `onopen` it reconnected about twice a second, so shell wore a flashing "Reconnecting…" banner
  for ten to twenty seconds on every load until a lucky read arrived. Both halves are fixed
  (`chat/src/gateway.ts` holds pre-auth messages, `@kernhq/sdk` waits for `welcome`); the rule
  behind them is that an accepted TCP socket is not an authenticated session, so nothing may be
  sent, counted or reported as connected until the server says so.
- **A check that reads the request only covers the service that has the request, and core is not
  the only host.** The MCP scope check — an AI client's `kmt_…` token held to the
  `<module>:<read|write>` its consent screen named — was written inside core's `resolve()`, off the
  `FastifyRequest`. It therefore covered the modules core hosts and *nothing else*: `chat`, `mail`
  and `collab` have no such request, they hand the bearer to `core.users.principal` and act on the
  answer, and that call passed the token alone — so the very same read-only token came back as its
  owner's **full** principal and could write there. Not an internal matter either, which is the part
  that makes it a breach rather than a wrinkle: the shipped Caddyfiles route `/api/chat/*`,
  `/api/mail/*` and `/collab*` **from the edge** to those services, so the token holder reaches them
  without passing through core at all. The fix is that the caller states the need
  (`{ module, write }`) and core refuses a `kmt_` token that arrives without one — optional on the
  wire, mandatory in effect, so an older image in a rolling deploy loses MCP rather than keeping the
  hole open. `collab` refuses them outright: a CRDT socket is not a module API call and is in no
  tool catalogue, so there is no need it could state. Whenever a rule is enforced from a request
  object, ask which processes have that object — and check the reverse proxy, because a service you
  think of as internal may be one hostname away.
- **A cache keyed on less than the question makes a new check decorative.** Both `chat` and `mail`
  cached the principal under the token alone. Adding the scope check without touching that key would
  have let the first `GET` answer every later `POST` from its entry: core asked once, about a read,
  and the write waved through on the cached answer — the fix passing its own tests and holding
  nothing. Any time a lookup gains an input, the cache key gains it in the same edit; the test that
  catches this asserts *two* calls reached the dependency, not that the second answer was right.
- Ports: shell 5173 · core 4000 · chat 4100 · mail 4200 · collab 4300 · docs 4400. The live
  allocation, the next free number, and the map of every repository are generated —
  `node .claude/skills/kern-repos/scripts/sync.mjs`, then read the `kern-repos` skill.
- Dev DB on this machine: Homebrew Postgres 18 at `localhost:5432` (`kern`/`kern`); the compose Postgres listens on `${KERN_PG_PORT:-5432}` (5433 here).

## CI
Every service repository's CI runs the real suites, so the workflow starts the infrastructure they
need as service containers: Postgres (`pgvector/pgvector:pg18`) everywhere, Valkey for `chat`,
Mailpit for `mail`. Things learned the hard way:
- Address a service container as **127.0.0.1**, never `localhost` — a runner resolves `localhost` to
  `::1` first, where the published port is not listening, and `fetch` does not retry over IPv4.
- Do not set `registry-url` on `actions/setup-node` in an install job. It writes an `.npmrc` with a
  placeholder token, and npm answers a bad token with **404**, so public packages appear to vanish.
- A repository is built **standalone** in CI. `workspace:*` only resolves inside the umbrella
  workspace; depend on the published version instead.
- **Each repository's own `pnpm-lock.yaml` is what CI installs from, and you cannot refresh it from
  inside the umbrella.** Add a dependency to a package and the umbrella install updates the *umbrella*
  lockfile, leaving the repo's committed one stale — CI then fails every job at
  `ERR_PNPM_OUTDATED_LOCKFILE`, install-time, before a single test runs. Plain `pnpm install` in
  `repos/<name>` walks up and attaches to the umbrella; `--ignore-workspace` skips `packages/*` and
  cheerfully reports nothing to do. Clone the repo somewhere outside the workspace and run
  `pnpm install --lockfile-only` there, then copy the lockfile back.
- **Every repository that builds something commits a lockfile: `kernel`, all eight `module-*`, and
  since 2026-09-02 the five services too.** `docs` is the one without. CI is
  `if [ -f pnpm-lock.yaml ]; then --frozen-lockfile; else pnpm install; fi`, so a repo with one
  fails at *install* the moment its lockfile drifts — before a single test. The services got theirs
  from the nightly release's reach (see below), and for a reason worth knowing: without one,
  Docker's dependency layer is keyed on `package.json` alone, so five releases in a row shipped
  modules resolved on 2026-08-27 while npm was six versions ahead — the image reported 0.1.4 and
  ran code a week old. Editing a range now means `scripts/relock.sh <repo>` in the same commit;
  `pnpm lint` (`check-ranges.mjs`) refuses a manifest its lockfile disagrees with. The refresh still
  cannot be done from inside the umbrella — `relock.sh` clones the repo elsewhere, resolves there,
  and copies the lockfile back.
- Skipping a test because its infrastructure is missing is fine on a laptop and dishonest in CI.
  Fail when `process.env.CI` is set.
- **A workflow that creates a release with `GITHUB_TOKEN` does not fire this repository's own
  `release:` event.** GitHub suppresses events caused by a run's own token — that is why
  `release-feed.yml` sat untriggered through months of releases while its `on.release` looked
  perfectly correct. `workflow_dispatch` via the API is the escape hatch, but it needs the job's
  token to hold **`actions: write`** — with the default `contents: write` the API answers
  `403 Resource not accessible by integration`, which is how the first forced release died at its
  last step. So `release.yml` carries `actions: write` and dispatches the feed by name after
  publishing; `release-feed.yml` had the permission all along, which is why its rollout dispatch
  always worked.

## Writing
Documentation — READMEs, guides, runbooks, `docs/`, ADRs, and any procedure someone follows — uses
the `kern-writing` skill in `.claude/skills/`: decide where it belongs first, goal before steps, one
action per step, conditions before commands, an observable result after every important action, and
never the present tense for something that is not built. It governs documents for readers. Code
comments and commit messages keep the voice they have; user-facing strings belong to `kern-language`.

## Quality bar
- `pnpm typecheck && pnpm lint && pnpm test && pnpm build` must pass before pushing.
- UI follows `shell/DESIGN.md` (Ink/paper design system) and must work in RTL (fa/ar) and dark mode.
- All user-facing strings go through i18n (Paraglide) — no hardcoded English in components.
- **A mock that models a state transition must model its side effects, or the sweep certifies a
  screen nobody can reach.** Scheduling a workspace deletion archives the workspace *immediately*,
  which drops it from `users.me()`, which makes the shell unable to resolve the slug — so the owner
  landed on "Create your first workspace" seconds after asking for a deletion the terms promise is
  undoable for thirty days. The undo route worked perfectly when called directly; nothing in the
  product could reach it. The mock did not archive on schedule, so the panel rendered beautifully
  and `ux.spec` swept a page that could not exist in production. The same evening produced two more
  of this shape: a test asserting on the database that could never see what `users.me()` returned,
  and a 2FA flow that walked correctly against fixture data. **Assert reachability — where a person
  lands after pressing the button, and whether the thing survives a reload on another route — not
  that a component renders when handed the right props.**
- **A consumer's assertion about another repository's copy goes stale in *that* repository, where
  no CI can see it.** `module-mail` changed "queued for" to "sent to" when the test send became
  synchronous; shell's assertion still held the old wording, so shell's `main` went red from a
  change made where nothing runs shell's tests. Same shape as the mock-manifest counts and the
  reserved-slug list: the check and the thing it checks live in different repositories. When you
  move a user-facing string that another repository asserts on, grep the workspace for it before
  you publish.
- **A screen that works is not finished; it has to be pleasant.** Kern is judged as a product, so
  the things that read as amateur are defects here, not polish: text nobody can read in dark mode,
  a blank browser tab, an icon button a screen reader calls "button", a control too small to hit, a
  page that scrolls sideways in Persian. None of that fails a build or a type-check, so it is
  guarded by a machine instead: `repos/shell/tests/e2e/ux.spec.ts` sweeps **every route in four
  renderings** — light and dark, LTR and RTL — against the rules in `ux-audit.ts`, and CI runs it.
  It is the only check that looks at the *rendered* interface. Adding a route means adding it there.
  What a machine cannot judge — whether the copy is kind, whether the layout has rhythm — is the
  `kern-ui` skill's job, and it is still yours to check.
- **`blur()` does not reset where the next Tab starts, so a test that walks the page twice walks
  from the wrong place.** Chrome keeps a *sequential focus navigation starting point* at the element
  that was last focused, and clearing focus leaves it there — so a second keyboard walk carries on
  from where the first one stopped rather than from the top. The symptom is not an error: the walk
  lands one control further on, the assertion fails against the control you meant, and the text you
  typed is sitting in the row below. Measured on a database test that tabbed to row 1's Notes cell
  twice and typed into row 2. Focus the root element first — `documentElement`, `tabindex="-1"`,
  focus, remove the attribute — before every walk. Any browser test that tabs more than once per
  page has this and will not know it.
- **Tailwind never scanned the module packages, so a module screen only had the utilities the
  shell happened to use too.** Tailwind v4's automatic source detection skips `node_modules`, and
  that is where every `@kernhq/module-*/src/client` lives — linked or installed. `p-5`,
  `content-between`, a two-column `grid-cols-2`: generated only if some file under `shell/src`
  used the same class, otherwise silently absent. The billing page had stacked its plan cards
  full-width, doubled its padding and lost the gap above its button for as long as it existed,
  and the UX sweep cannot see a missing class. `@source "../node_modules/@kernhq/module-*/src/client"`
  in `shell/src/app.css` fixed it on 2026-09-04 — and changed the look of every module screen at
  once, which is why the sweep ran before it shipped. Measure a computed style when a class seems
  to do nothing (`getComputedStyle(el).padding`), and remember `Card`'s own scoped `.p-md` beats
  a `p-4` passed in: use `padding="none"` and pad inside.
- **A screenshot taken for any reason is a UI review.** During the Stripe drill on 2026-09-04 the
  plan screen was captured three times to read the subscription state, and the picture also showed
  a *Choose* button flush against the highlight list with the card's padding pooled beneath it —
  `Card` is a block, so `grid gap-4` on it reached nothing. The owner saw it from the same image.
  Whenever you look at a rendered screen, judge spacing, alignment, direction and copy before you
  read the data off it, and fix what you see in the same session (`kern-ui` §13).
- **Two of these defects are invisible from the source, so measure rather than eyeball.** A colour
  pair's contrast is arithmetic, not taste: compute it against the surface the text actually sits on
  and against the *palest* one it could sit on. And `opacity` on a row fades its text against the
  page — a "muted" row at 0.5 is unreadable, whatever its colour token says. Mute with a colour.

## Keeping this file current
This file is how the next person — or the next agent — avoids repeating what we already worked out.
When you learn something durable, add it here **in the same commit as the change that taught you**:
- a trap that cost you time (a silent failure, a misleading error, a tool that lies about success)
- a convention you had to infer from reading several files
- a decision and the reason behind it, especially where the obvious choice is wrong
Keep it specific and short. Delete anything that stops being true — a stale note is worse than none.

---

# This repository: app (umbrella)

The project's face and the local development workspace. It holds the self-host distribution
(`selfhost/`), the docs and ADRs (`docs/`), and the scripts that clone every other repository into
`repos/` and link them with pnpm.

```bash
pnpm setup     # clone every repo into ./repos and install
pnpm infra     # Postgres 18, NATS, Valkey, MinIO, Mailpit
pnpm dev       # every service with hot reload
```

**Things worth knowing**
- `repos/` is gitignored: each subdirectory is its own git repository with its own remote.
- **The umbrella has no turbo task graph, and cannot have one.** Every repo carries its own
  `turbo.json`, and CI clones that repo alone — so the file has to be a *root* config, while a
  package inside this workspace would need `extends: ["//"]`, which turbo rejects at a root.
  `pnpm dev|build|lint|typecheck|test` therefore run `scripts/run-all.sh`, which calls each
  repo's own script in dependency order (kernel → modules → services → shell → docs). It reports
  every failure rather than stopping at the first, and `--parallel` is what `pnpm dev` uses.
- **Every aggregate command is only as complete as `scripts/repos.mjs`, and it was missing `shell`.**
  `dev-setup.sh` cloned `app` — this repository, into itself — and never cloned `shell`;
  `run-all.sh` left `shell` out of its build order. So `pnpm setup` produced a workspace with no
  user interface, `pnpm dev` started every backend and no front end, and `pnpm build`, `lint`,
  `test` and `typecheck` skipped the entire UI repository while reporting success. That is how
  shell defects cleared this quality bar for months, and it was invisible on the one machine whose
  `repos/` had been assembled by hand. The list is one file now, read by `dev-setup.sh`,
  `run-all.sh` and `check-messages.mjs` — but one list only stops the copies drifting from each
  other, and the list itself going stale is the failure that actually shipped. `pnpm check:repos`
  is what asks the organisation whether the set is complete: every repository must be in `ORDER`
  or in `OUTSIDE` with the reason, so a new one is a decision somebody records rather than an
  omission nobody sees. A hardcoded list in a `package.json` script is the same defect — that is
  where the eight module directories `check:messages` covered used to live.
- **`pnpm status` is the only honest answer to "is everything committed?"** Ten repositories means ten
  answers, and `website` is checked out *beside* the umbrella rather than inside `repos/`, so a loop
  over `repos/*` misses it — silently, which is the worst way to miss something. The script finds
  every checkout, lists every path (never a truncated `head`), and reports unpushed commits, stashes,
  a detached HEAD and any repository the organisation has that is not cloned here. It **exits 1** when
  anything is unpushed, so it can gate rather than only inform: `pnpm check:clean` is the same check
  without the detail. Run it before you tag anything.
- Dependencies are installed at this root, which is why every repo uses
  `scripts/pnpm-install-locked.sh` — several agents or terminals installing at once will corrupt the
  store otherwise.
- The dev Postgres container listens on `${KERN_PG_PORT:-5432}`. On a machine that already runs
  Postgres on 5432 (Homebrew, for instance), set `KERN_PG_PORT=5433` so the container stops shadowing
  it — and point `DATABASE_URL` at whichever one you actually mean.
- `selfhost/` is what users run. Changing a service's port, image name or env contract means changing
  `docker-compose.yml`, `Caddyfile`, `.env.example` and `coolify/docker-compose.yml` here too — and
  `install.sh`'s file list, which is what an existing instance never re-downloads.
  `scripts/check-selfhost-drift.py` is what notices when the Coolify copy is left behind; CI runs it.
- **`FOO: ${FOO:-}` does not mean "unset", it means the empty string — and zod tells the two apart.**
  Compose emits the key with an empty value, so a schema sees a *value* to validate: core parses
  `KERN_SIGNUP` with `z.enum(['open','invite']).optional()`, which answers "Invalid option" for `''`,
  throws in `loadCoreEnv` before :4000 is bound, and takes core-worker, chat, mail and collab down
  with it because they all wait on core being healthy. Every fresh self-host install after
  2026-08-28 came up with nothing running. The pass-through form is a **bare key with no value**
  (`KERN_SIGNUP:`, the mapping equivalent of a `- FOO` list entry): Compose then sets the variable
  only when it is actually set, and omits it otherwise. Verify by running a container, not by reading
  `docker compose config` — the config prints `null` for both a pass-through and a genuine absence.
  The other half of the trap is that **`FOO=` in `.env` defeats the pass-through**, because a blank
  assignment is still a value; `.env.example` has to comment the line out. A field with a
  `.default()` fails silently instead of loudly, since a default only fires for `undefined`.
- **Comparing the three stacks with each other cannot find a route missing from all three.**
  `check-selfhost-drift.py` only ever asked "has a copy fallen behind the host?", so three identical
  configs agreed perfectly while every one of them was wrong: core serves `/mcp` and the OAuth
  discovery documents at the **root** of its Fastify app — the paths are fixed by the MCP and
  RFC 8414/9728 specs, so they cannot move under `/api` — no stack routed them, all of them fell
  through to the catch-all, and MCP answered the SvelteKit app's HTML on every topology since it
  shipped. `REQUIRED_ROUTES` in that script is the half that does not depend on the three agreeing:
  a run of directives that must appear, in order, above `handle {`, in the host Caddyfile and both
  inline copies. Add an entry whenever a service starts answering on a path outside an existing
  prefix. Prove a routing change by running the real Caddyfile in a `caddy` container against stub
  upstreams and curling each path to see which upstream answers — `caddy validate` only says the
  file parses, and the drift check only says the three match.
- **An upgrade brings the stack files forward now, and until 2026-09-05 it never did.** `install.sh`
  fetches a distribution file only when it is absent (`[ -f "$f" ] || curl`) and `kern-upgrade.sh`
  only changed `KERN_VERSION` and pulled images, so an existing instance kept the
  `docker-compose.yml`, `Caddyfile` and `postgres-init/` it was installed with **for ever** — the MCP
  Caddy route never arrived, a blank `KERN_SIGNUP=` kept core from booting after the release that
  fixed it, and `MAIL_WEBHOOK_TOKEN` was handed to a mail service by a compose file the instance did
  not have. Every fix living in one of those files reached new installs only.
  `kern-upgrade.sh` now fetches the file from **both** `v$CURRENT` and `v$TARGET` and compares:
  identical to target is already current, identical to current is untouched since install and safe
  to replace (the old copy goes to `snapshots/stack-<stamp>/`), anything else is an operator's edit —
  left alone, with the release's diff written out and the run ending in a **⚠ and exit 1** rather
  than the green tick it used to print either way. `.env.example`, `kern-backup.sh` and
  `kern-rollback.sh` come forward the same way. Two things still do not: **`kern-upgrade.sh` cannot
  replace itself** while running (bash reads a script incrementally, so the interpreter would resume
  at a byte offset in different text) — it is saved as `kern-upgrade.sh.new` and the operator is
  told; and the `systemd/` units are not in the list. `KERN_RAW_BASE` points the fetch at a local
  directory laid out as `<ref>/selfhost/<file>`, which is how CI tests the whole thing with no Docker
  and no Kern (`--stack-files` is the refresh on its own).
- **A blank `.env` value is not an absent one, and only one of them can be repaired by adding.**
  The backfills in `install.sh` and `kern-upgrade.sh` handle a key that is *missing* by generating
  it. The opposite case needs the opposite fix: `KERN_SIGNUP=` defeats the compose pass-through and
  stops core booting, so the upgrade **comments the line out**. And when you write a guard for either,
  read the value rather than pattern-matching the line — `grep -q "^KEY='.\+'"` matched only a
  single-quoted value, so an unquoted `KEY=abc` read as unset and the installer appended a *second*
  assignment; Compose takes the last one, so re-running `install.sh` rotated `MAIL_WEBHOOK_TOKEN` and
  silently invalidated the webhook URL already registered with the provider. `grep -q "^KEY="` is the
  same mistake reversed: it matches a blank line, which is what `.env.example` ships, so the
  `KERN_DIR` backfill it guarded never ran on any instance.
- **A prune glob decides what counts as a backup, so anything else you put in that directory is at
  risk.** `kern-backup.sh` created its directory under the final name and never renamed it, so a run
  killed by the timer's 6h `TimeoutStartSec`, a reboot or a Ctrl-C left a `<stamp>/` holding a
  truncated dump that sorted newest, listed as a backup and was counted by the prune while a real one
  was deleted. It writes to a dot-prefixed `.<stamp>.partial` and `mv`s into place after `RESTORE.txt`
  now; the dot is what keeps it out of both globs. `kern-upgrade.sh`'s snapshot prune had the mirror
  image of the problem — `ls -1dt "$SNAPSHOT_DIR"/*/` would have swept the new `stack-<stamp>/`
  directories holding the diffs an operator was just told to merge, and evicted a real snapshot to
  make room — so it globs `*-to-*/`, the snapshot naming pattern. And under `set -e` an `EXIT` trap
  whose last command fails **takes the script's exit status with it**: end a cleanup handler in
  `return 0` or systemd reports every successful backup as a failure.
- **`return 0` is right for `EXIT` and catastrophic for `INT` and `TERM`, and one handler served all
  three.** A *signal* handler that returns hands control back to the line after the interrupted one,
  so a Ctrl-C or the timer's `TimeoutStartSec` deleted the working directory, the script carried on,
  `mkdir -p` made it again, and the publish moved a directory holding **no database dump** into place
  under a green "Backup complete" — then the prune counted it and deleted a real backup to stay under
  the limit. Strictly worse than the truncated dump that fix replaced, and it shipped hours after it.
  `trap cleanup EXIT` and `trap 'cleanup; exit 130' INT` are two different jobs. Then check the
  artefacts before publishing rather than inferring them from "no step reported a failure": that is
  precisely the claim the interrupted run was still able to make. Prove this class by *sending the
  signal*, at each phase, from a stub whose command then still exits 0 — `selfhost.yml` does, and
  note that a backgrounded run would pass it for the wrong reason, because an asynchronous command
  in a non-interactive shell inherits `SIGINT` ignored and a script cannot trap what was ignored on
  entry.
- **A new kind of entry in a shared directory means fixing every reader of it, not the one you were
  looking at.** The `stack-<stamp>/` diffs an upgrade leaves in `snapshots/` were kept out of the
  snapshot *prune* and not out of `kern-rollback.sh`'s auto-select, which took the newest
  **directory** — and the stack directory is created after the snapshot, so it always sorts first.
  `./kern-rollback.sh` with no argument then died with "has no from-version file" while a perfectly
  good snapshot sat beside it: `install.sh` prints that command as the way out of a bad upgrade, so
  the documented recovery path was broken by the change that made upgrades safer. Select on the
  property you actually need — here a `from-version` file — rather than on a naming convention.
- **A `Type=oneshot` unit's exit code is something an operator reads every night.** `kern-upgrade.sh`
  recorded the auto-update outcome *before* the stack-file verdict and then exited 1 on it, so
  Admin → Updates showed the release applied while `kern-auto-update.service` showed failed, for an
  upgrade that worked, every night for as long as one file stayed edited — which is how the night one
  genuinely fails goes unread. Record an outcome after the verdict it describes, and keep a non-zero
  exit for what a person's *shell* is the right place to learn. Recording `failed` instead would have
  been worse than the red unit: the timer stands down until an admin clears it, and the operator's
  edited Caddyfile is still edited tomorrow night, so automatic updates would have ended for good.
- **The images are `amd64` only.** `docker.yml` in each service repo has no `platforms:`, so
  `build-push-action` builds for the runner. Every requirement we publish says x86-64 because of
  that one omission — adding `platforms: linux/amd64,linux/arm64` (and QEMU) is what changes it.
- **The memory figures in the docs and on the website are measured, not estimated.** Idle RSS of the
  real containers, plus `node dist/main.js` for `core` run against them. Re-measure before changing
  the numbers rather than adjusting them by feel; `core` is the largest Kern service, so it is the
  one worth measuring.
- **Do not override a Kern service's healthcheck in Compose.** Every service image already carries
  one, and it is the only shape that works: the images are `node:24-slim`, which has neither `wget`
  nor `curl`, and the services listen on IPv4 only, so `localhost` resolves to `::1` and is refused.
  All three compose files carried `test: ["CMD","wget","-qO-","http://localhost:4000/api/health"]`
  for `core`, which failed on both counts — so `core` was permanently unhealthy, and `core-worker`,
  `chat`, `mail` and `collab` all wait on `condition: service_healthy` and therefore never started.
  A stack that looks like it booted with four services missing is this. The image probes
  `127.0.0.1` with `node -e "fetch(...)"`; let it.
- **There are now three copies of the stack, and `cloud/` is the third.** `selfhost/` is the bare
  host, `selfhost/coolify/` is what a customer pastes into their own Coolify, and `cloud/` is the
  instance we run at app.kernaio.com. It differs in exactly one thing: `S3_PUBLIC_ENDPOINT` points
  at its own hostname, because Cloudflare's Free and Pro plans reject a request body over 100 MB
  while `UPLOAD_MAX_PUT_BYTES` signs single-PUT URLs up to 500 MB — proxy the storage path and every
  large upload dies as a 413 the browser reports as a network error. So MinIO gets `files.` on a
  DNS-only record and shell keeps the CDN. `scripts/check-selfhost-drift.py` checks all three:
  a copy may differ in a variable's *value*, never in the set of keys or the Caddy routes.
- **Coolify deploys `cloud/docker-compose.yml` from `main`, so a compose change reaches the cloud at
  the next rollout, having run nowhere first.** `selfhost.yml` used to parse the file and stop.
  On 2026-09-02 an ownership-handover `db-init` landed on `main` in the afternoon and met the cloud
  at 18:04 in the nightly rollout: it ran `ALTER SEQUENCE … OWNER` on a serial's sequence apart from
  its table (Postgres refuses), exited 3, every container stayed `Created`, and the automatic
  rollback to 0.1.4 failed the same way — nineteen minutes of 503 until the ownership was fixed on
  the database by hand and the containers started. The same script had *always* skipped pg-boss's
  two partitioned tables, because a partitioned parent carries an internal (`i`) `pg_depend` row on
  **itself** and the query excluded anything with an `i` dependency — so the moment the services
  first ran as `kern_app` (0.2.0) every queue poll failed with `permission denied for table job`
  for two hours while `/api/health` stayed green (`mod_hr.punches`, partitioned the same way, was
  one `ALTER` from the same failure). And `ALTER TABLE … OWNER` on a partitioned parent does
  **not** recurse to its partitions. The rule now: skip only
  extension members and column-owned sequences; move every other relation, partitions included.
  `selfhost.yml` runs `db-init` twice against a database that already has superuser-owned tables, a
  serial, a standalone sequence, and a partitioned table with a partition. Anything in `db-init`
  runs on every instance at every deploy; test it on a database that already exists, not on an
  empty one — and when a query decides what to skip, print what it skipped.
- **`selfhost/coolify/` mounts nothing.** A Compose file pasted into Coolify has no files beside it,
  so the Caddy config is a heredoc inside the container's command and the Postgres init script is
  gone (core's first migration creates the extensions anyway). Keep the heredoc free of `$` —
  Compose interpolates the command string before the shell ever sees it.
- **A `HEALTHCHECK` with no `--start-period` fails a Coolify deploy, on a container that works.**
  Coolify gates a release on Docker's health status and polls it about ten times. Docker's default
  interval is 30s and the first probe fires almost immediately — before the server has bound — so
  every poll re-reads that same stale failure (identical `Start` timestamp in the log is the tell)
  and the release is rolled back. Give every image `--interval=10s --start-period=15s`.
  And probe **127.0.0.1, not localhost**: `nginx.conf` replacing nginx's `default.conf` means
  `10-listen-on-ipv6-by-default.sh` never patches it, so nginx is IPv4-only while busybox wget
  tries `::1` first and is refused. Same trap as the CI note above, one layer down.
- **Caddy behind another proxy rewrites `X-Forwarded-Proto` to `http` and replaces the client IP**
  unless the proxy in front is trusted. On Coolify that turns every request into one the services
  believe arrived unencrypted. `servers { trusted_proxies static private_ranges }` in the global
  block is what preserves them; the host install does not need it, because there it is the edge.
- **Run `docker compose config` after editing `docker-compose.yml`.** A bare `${VAR}` inside a YAML
  *flow* mapping (`environment: { A: ${A} }`) opens a nested mapping and the whole document stops
  parsing — the file shipped that way and `docker compose config` failed on it, which no test
  covered because nothing parsed it. Quote every interpolation inside `{ }`.
- **A standalone repo needs its own `pnpm.overrides` too, for the same reason the umbrella has one.**
  A published module whose range still says `@kernhq/kernel: ^0.2.0` drags a second kernel into a
  consumer's tree, and a caret on 0.x never crosses a minor — so `core` installed kernel 0.2.0 for
  `billing` and 0.6.0 for itself and `tracker`. Two structurally distinct declarations of
  `ServerModule`, so `[trackerModule, billingModule]` stopped being assignable to `ServerModule[]`
  even though both packages export exactly the same type. Invisible locally, because the umbrella
  already pins these. `"overrides": { "@kernhq/kernel": "$@kernhq/kernel" }` forces one copy, which
  is the honest model: there is only ever one kernel at runtime. Reproduce this class of bug with a
  registry install in a clone outside the workspace — a local build resolves differently and proves
  nothing.
- **`pnpm.overrides` pins `@kernhq/contracts|kernel|sdk|ui` to `workspace:*`.** Without it a repo
  whose dependency range excludes the local version (shell wanted `module-tracker@^0.3.0`, the
  workspace had 0.2.1) installs the published module, which drags a published `@kernhq/contracts`
  into the tree. Two copies of the contracts then coexist, and `svelte-check` resolves the stale one
  while plain `tsc` resolves the linked one — so shell reports errors for procedures that exist,
  in files nobody touched. Plain `tsc` passing is not evidence here; `pnpm typecheck` is.
- **A release is one act across six repositories, and `release.yml` here is the only thing that
  performs it.** Nightly (or by hand) it first *reaches*: `scripts/reach.mjs` advances every
  service to the newest compatible `@kernhq/*` set — one version per module across `core` and
  `shell`, because a module's server and client must agree — commits it with a lockfile on
  `release/reach`, waits for each repository's CI, and lands all five on `main` or none. Then it
  tags one version in `core`, `shell`, `chat`, `mail` and `collab`, waits for each image to appear
  in GHCR — `release-feed.mjs` reads the images to find out what modules a release contains, so the
  feed cannot be built before they exist — writes notes that include each module's changelog, and
  creates the umbrella release **as a draft**. It dispatches `release-feed.yml`, which extends the
  *previous* release's feed (never `releases/latest`, which is the draft-less new release and 404s
  — that is how the feed forgot every earlier release for five releases), signs it, publishes the
  draft, and dispatches `rollout.yml`. The cloud is the canary: it takes the release that night with
  a migration dry run, snapshot, maintenance mode and rollback; self-hosters on `auto` follow after
  their settling period. Nothing in the chain needs a hand after `git push`, which is the point:
  main moves all day and the cloud moves once. A reach that fails CI does not stop the release — it
  goes out from `main` as it is and the run ends red naming the module to republish. Tagging
  another repository's `main` needs `KERN_RELEASE_TOKEN`; `GITHUB_TOKEN` cannot, and the
  fine-grained PAT cannot see the umbrella — a step that touches both needs one token for each.
- **`if: inputs.x != false` is false on a `schedule` run, so the step is skipped.** Every
  `inputs.*` is null when a workflow fires from cron, and GitHub's expression language coerces null
  and false to the same number before comparing — so a step guarded that way runs on a hand dispatch
  and never on the nightly, while the run still reports success. The reach in `release.yml` sat
  behind exactly that condition and was skipped on every scheduled release it was ever part of
  (two of them, 2026-09-02 and -03: `hr` 0.21.0 was on npm five hours before the run and v0.2.1
  shipped 0.20.3). Guard on the event instead: `github.event_name == 'schedule' || inputs.x ==
  true`. And when a step's absence is invisible in a green run, read the run's *step conclusions*
  (`gh run view --json jobs`) rather than its conclusion — that is where "skipped" shows.
- **A release is a claim that every image agrees, and only the reach used to make it true.**
  A reach that fails releases main as it is, and main is edited by hand — shell reached
  `module-hr` 0.22.0 on 2026-09-03 while core sat on 0.20.3, and the next release would have
  shipped a client calling procedures the server did not have, every one a 404. `release.yml`
  reads the lockfiles and refuses to tag when any `@kernhq/module-*` or `@kernhq/contracts`
  resolves differently across them; the fix is always to move the one that is behind, never to
  release the set.
  **It read `core` and `shell` alone until 2026-09-05, and core is not the only host.** `chat`
  carries module-chat's server and `mail` carries module-mail's, both clients living in shell — so
  the two modules whose server and client sit in *different* repositories were exactly the two the
  guard could not see. It reads all five services now. The first run found `module-mail` at 0.6.1
  in shell against 0.5.2 in mail on `main`, which had been invisible for as long as the check
  existed. When you write a guard over a set, enumerate the set from the same place the workflow
  does (`SERVICES`), never from the two examples that prompted it.
- **Renovate is installed and has never opened a pull request here.** ADR 0009 leaned on its
  `@kernhq/*` automerge for months; zero PRs and zero dependency dashboards in any repository. Do
  not lean on it for anything a release depends on; the reach is what moves module pins.
- **Reading a workflow run's `conclusion` right after a push sees `null`.** The old red-main check
  read the latest run's conclusion once and called a commit that was still testing "missing".
  `.github/scripts/wait-green.sh` waits for a completed run and accepts a green twin over a
  cancelled one; use it anywhere a workflow gates on another repository's CI.
- **Nothing picks a version number by hand any more, and nothing needs a changeset written by hand
  except a breaking change.** `release.yml` reads the bump out of the commit subjects and out of
  how far each module moved (a module that crossed a minor makes the release a minor), so
  Conventional Commits stopped being a style rule and became the input to the release; below 1.0.0 a
  breaking change is demoted to a minor rather than declaring a stability nobody meant. `publish.yml`
  infers a missing changeset the same way. The one thing neither will guess is a **major**: whether
  an exported type changed shape is invisible in a subject line, and publishing that as a patch is
  what a consumer's caret range installs silently — so a `!` or a `BREAKING CHANGE` trailer with no
  changeset fails, in CI and at publish.
- **The cloud rollout is the one workflow that holds a credential for a machine, and it used to
  post it in the clear.** `COOLIFY_URL` is `http://128.140.5.236:8000`, so every nightly rollout
  sent `COOLIFY_TOKEN` — a full Coolify API token, not deploy-only — as a bearer header across the
  public internet, twice per run. There is no HTTPS to switch to and checking that first is the
  point: :8000 speaks no TLS at all, the instance has no FQDN, and Traefik holds certificates for
  kernaio.com, www, docs, app and files only, so pointing the workflow at `https://` would have
  broken every release rather than secured one. The fix needed nothing from the owner, because the
  rollout is **already** connected to that exact host by SSH — it dry-runs migrations and dumps the
  database there — so `.github/scripts/coolify-endpoint.sh` forwards a port down that connection
  and the API call becomes a local one. Over `https://` it changes nothing; it **refuses** rather
  than falling back to cleartext, because a fallback nobody sees is how the credential returns to
  the wire. Before reaching for DNS and a certificate, check whether you already hold an encrypted
  channel to the same machine. Still open, and owner-side: ufw allows only 22/tcp but Docker
  publishes :8000 straight through iptables, so the Coolify API is on the internet regardless of
  this workflow.
- **`curl ... || echo 000` cannot be compared with `"000"`.** A curl that cannot connect prints
  `000` on stdout *and* exits non-zero, so the `||` appends a second one: the variable holds
  `000000`, `[ "$code" = "000" ]` is false, and the health check you just wrote reports success for
  a dead endpoint. It was written that way twice in one file on 2026-09-05 and caught only by
  pointing the tunnel at a port with nothing behind it. Match the shape instead —
  `case "$code" in [1-5][0-9][0-9])` — and test a probe against something that is genuinely down.
- **Green is not shipped.** A push builds an image; it does not move the cloud. `app.kernaio.com`
  has auto-deploy off on purpose — main moves all day and the cloud moves once, on a release. The
  honest check for "is my change live" is `/api/health` reporting the version, not `git log`.
- Release feed: `node scripts/release-feed.mjs --keygen` makes the ed25519 pair. The public half goes
  in core's `updates` service, the private half in the `KERN_FEED_PRIVATE_KEY` org secret. Until both
  exist, instances report "no signing key is configured" rather than claiming to be current.
- **A workspace package can silently resolve to a registry copy, and then local edits do nothing.**
  `link-workspace-packages=true` links a package the first time the workspace version satisfies the
  range; pnpm does not re-evaluate a resolution that still satisfies, so once the lockfile records
  a registry version it keeps it. Today `@kernhq/module-mail` is linked while chat and tracker are
  registry copies, in the same install. Check with
  `readlink repos/shell/node_modules/@kernhq/module-<id>` before wondering why an edit to a module's
  client had no effect — the answer is that shell never read your file. This lockfile is
  gitignored, so the linking state is per machine: two people on the same commit can disagree about
  which packages are linked, and only one of them sees the bug.
- **Editing a module's client means a publish round trip, and it is worth checking that first.**
  `./client` ships as source, so an edit is visible immediately *if* the package is linked and not
  at all if it is not. Either way the consumer's CI installs from the registry, so the change has to
  publish before the consumer's commit can go green: module changeset and push, wait for the version
  to appear on npm, then bump shell.
- **`tsx watch` processes pile up, and the oldest one owns the port.** Seven `core` watchers were
  running at once from earlier sessions; the first to bind :4000 keeps it, and every later one
  reloads your edits into a process nobody can reach. The symptom is a service that ignores a change
  it has definitely seen — `curl localhost:4000/api/core/openapi.json` shows the old surface while
  the log shows a reload. Check with `ps -eo pid,command | grep "tsx/dist/cli.mjs watch"` before
  concluding a change did not take, and expect one pid per service.
