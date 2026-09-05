# TODO — to v1.0 on 2026-09-16

The working list behind [ROADMAP.md](ROADMAP.md). One line per thing somebody does; tick it in the
commit that does it, with the date. The roadmap says *why*; this says *what, next*. Issues
[#1–#5](https://github.com/KernAIO/app/issues) carry the same slices for anyone outside.

Written 2026-09-02 against what actually runs. Order inside a section is the order to do it in.

## Every day

- [ ] Read the nightly: `release.yml` green, `rollout.yml` green, and
      `curl -s https://app.kernaio.com/api/health | jq -r .version` equals the newest version in
      `releases/latest/download/releases.json`.
- [ ] `pnpm status` at the umbrella root — land or revert anything another session left
      uncommitted or unpushed. On 2026-09-02: 19 uncommitted files in `shell`, an uncommitted
      client change in `module-tracker`.
- [ ] Any red `main` in any repository is the first job of the day.

## 1. Kern Cloud can take money safely — by 2026-09-07 ([#1](https://github.com/KernAIO/app/issues/1))

Nothing below is code; it is configuration, ops and verification. Today the cloud sends no email,
takes no payment, and has no backup.

- [ ] **Outbound mail.** Set `SMTP_URL` (or a Mailgun/Postmark/SES/Resend relay) on the Coolify app
      and the `mail` service; sign up with a fresh address and receive the verification mail;
      invite somebody and receive the invitation; request a magic link and receive it. No email
      has ever left the instance. **Blocked on a relay credential** (2026-09-04): no Mailgun or
      Postmark account exists anywhere; buying one is the owner's call.
- [x] **Every cloud workspace is on a plan.** `kernaio` and `entropol` were created before
      `KERN_DEFAULT_PLAN_SLUG` existed, had no subscription row, and a workspace with no row is
      *unlimited* — so two of the three cloud workspaces were entitled to everything with no trial
      and no bill, for ever (found 2026-09-04 while chasing the "missing" invoice, which was on
      `dinalabs` all along). `module-billing` 0.5.14's nightly job enrols any workspace with no row
      on the default plan; both start their 14-day trial the first night it runs. A webhook for a
      workspace the instance does not have is skipped since 0.5.13 (the shared sandbox delivered a
      dev checkout to the cloud); the one orphan invoice row is deleted by hand.
- [x] **Backups off the host.** `kern-cloud-backup.timer` at 01:00 UTC: `pg_dump` plus a mirror of
      the `kernaio` bucket into a versioned `kernaio-backups` bucket on Hetzner, 30-day retention
      (2026-09-03).
- [x] **Restore drill.** Last night's dump restored into a scratch database on the host, 150
      tables matched against production (2026-09-03). The procedure still has to be written into
      `docs/self-hosting/backups.md` as it was run.
- [x] **Somebody is told when it breaks.** The `kern-watch` Cloudflare Worker probes `/api/health`
      every five minutes and mails the owner on down, recovery and version change, and when the
      backup heartbeat is older than 26 h (2026-09-03). `release.yml` and `rollout.yml` open an
      issue labelled `release-failure` when they end red (2026-09-04).
- [x] **Stripe, sandbox.** Decided 2026-09-04: v1.0 launches with the Stripe *sandbox* (the "ij
      sandbox" account the CLI is logged into; `sk_test` valid to 2026-11-02), live keys follow.
      Driven end to end against real Stripe with the Team and Business prices created there:
      hosted Checkout with the 4242 card → 12 webhooks → active on Team, invoice paid and
      mirrored; reprice Team ↔ Business in place; portal URL; admin suspend → every write refused
      with `billing.subscription.inactive`, reads still answer; cancel-at-period-end mirrored both
      ways; a failing card → `invoice.payment_failed` → `past_due` with a 14-day grace clock;
      the customer's fixed card paying the open invoice → active, clock cleared. Cloud endpoint
      `we_1UBvZWRxQj7Rxe4EL4l2SRY6`. **The cloud too** (2026-09-04 11:56 UTC): sandbox keys set
      on Coolify, Team chosen from app.kernaio.com's own billing screen, hosted Checkout with the
      test card, the webhook delivered to the cloud — *Payment received*, Team, trialing until
      2026-09-18, Stripe ids stored. And the rest (2026-09-04 12:15 UTC): grace expiry →
      `suspended` by `billing.close-grace-periods` (run by hand against the drill database —
      cron jobs run in the worker role, not the API) → every write 409 → choosing the plan again
      reactivated in place; a full Stripe-side cancel → `canceled` → 409 → a *fresh* Checkout
      (no reprice on a dead subscription) → active, third invoice mirrored. Nothing left untried.
- [x] **Entitlements enforced** (2026-09-04, sandbox drill): seats — the 11th acceptance on a
      10-seat plan refused with `billing.seats.limit_reached` (a single invitation is checked
      against members + that batch, acceptance against the live count); storage — an upload over
      the workspace total refused with `billing.storage.limit_reached`, one under it accepted;
      SSO — refused on a plan without it (`BILLING_SSO_NOT_INCLUDED`), and on a plan with it the
      registration itself answers 500 (KernAIO/core#1), so SSO is *not in v1.0*; audit retention
      — one nightly job (`retention.ts`), unchanged.
- [x] **Legal.** Read against what runs (2026-09-04): both pages said no backups were taken —
      corrected to nightly, 30 days, off-host, and that a deletion survives in them that long;
      Cloudflare added as the fourth subprocessor (every request and every mail to our own
      addresses passes through it). DPA: none for v1.0, and the subprocessors page says so plainly
      — a company that needs one writes to privacy@. The five mailboxes forward to the owner
      (2026-09-03).
- [x] **Host hygiene.** `PasswordAuthentication no` in sshd on 128.140.5.236 (2026-09-03).
      `KERN_CLOUD_PG_CONTAINER` stays unset on purpose: Coolify renames every container on each
      rollout, so `rollout.yml` finds Postgres by its compose label instead.
- [x] **Cloud on a firmer deploy.** Decided 2026-09-04: Coolify stays through v1.0; the reasons and
      the condition for reopening it are an addendum to ADR 0002.

## 2. Every page says only what ships — by 2026-09-05 ([#2](https://github.com/KernAIO/app/issues/2))

- [x] Docs: Recruiting, CRM, Automation, Calls and AI pages open with a *Planned* notice
      (2026-09-02).
- [x] Website: Quire and HR are shipped; the tracker's list names what it does today
      (2026-09-02).
- [x] Website launch checklist: the images are public (2026-09-02).
- [x] Docs sidebar: the five planned pages and Drive & Calendar sit under a collapsed *Planned
      modules* group; Tracker, Chat, HR and Mail describe what ships and name what does not;
      Inventory has a page (2026-09-04).
- [x] Every repository README agrees with the roadmap. `app`'s table called HR "not built" and
      warned the images were private; the template README promised `npm create kern-module`
      (2026-09-04). Email-to-issue was claimed in three places and is not built — corrected in
      the roadmap, the README, the docs and the website.
- [x] `pnpm pricing` on the website is clean (2026-09-04). It had refused seven highlights —
      storage "per user", backups "kept a year", support response times — and Admin → Plans had
      no field to fix them with and wiped them on every save (`module-billing` 0.5.1 adds the
      field). The six were corrected through the admin API; the backup rule in
      `gen-pricing.mjs` now refuses only what outruns the 30 nightly copies that exist.
- [x] The website's home page copy names the modules that exist and no others; Inventory joined
      the module list (2026-09-04).
- [x] Every one of the 67 routes screenshotted from the mock build and judged as a UI review
      (2026-09-04). Fixed: an invoice whose customer no subscription row knew yet was dropped as
      applied (`invoice.paid` arrives before `checkout.session.completed`; `module-billing` 0.5.9
      places it by the subscription metadata Stripe snapshots on the invoice and backfills
      nightly — the cloud's own purchase turned out *not* to have hit this, its row was there);
      a webhook for a workspace this instance does not have wrote an orphan invoice row with a 200
      (a dev checkout through the shared sandbox — guarded now, the orphan `J9ZNFK5L-0003` row on
      the cloud is still to delete by hand); the invoice list had no status column; the admin subscriptions table was wider than its pane; the HR
      reports page had a 160px blank band (a `.ctl` class shared with `Field`'s inner wrapper)
      and a clipped last column; an overnight shift printed two full dates; tracker Import used
      the browser's bare file input; Integrations called Email delivery "Coming soon" beside a
      mail settings page that exists; two icon buttons had no gap. Still open, all small:
      Integrations lists Webhooks and API tokens as coming soon (true — say so in the docs
      rather than build them before 1.0); Work that repeats shows the interval as "week" rather
      than "every week"; Quire's database view prints "Empty" in every empty cell, which reads
      as noise on a sparse table; the tracker Workflows list has an empty band under the one
      workflow. None blocks 1.0.

## 3. A self-hoster gets from zero to upgraded and back — by 2026-09-11 ([#3](https://github.com/KernAIO/app/issues/3))

Done by running it on a machine nobody has touched, following only
`docs.kernaio.com/self-hosting`. Every step that needed knowledge not on the page is a docs bug;
every failure is a product bug and gets a CI test where one is possible.

- [ ] Clean Ubuntu 24.04 VM: download and run `install.sh` (piping it into `bash` is refused by
      the script itself — the docs said `| bash` until 2026-09-04) → first admin signs in,
      creates a workspace, files an issue, sends a chat message, edits a page.
- [ ] `./kern-upgrade.sh --check` passes; the next nightly arrives; Admin → Updates shows it with
      the module diff.
- [ ] Admin → Updates on `auto` with a window ten minutes ahead; the timer upgrades it; the
      instance reports the new version; the admins get the notification.
- [ ] `./kern-rollback.sh` returns it to the previous version; `--database` restores the dump.
- [ ] `./kern-backup.sh` runs; a restore from its output works on a second VM.
- [ ] Coolify: paste `selfhost/coolify/docker-compose.yml`, deploy, sign in; set `KERN_VERSION`
      and redeploy to upgrade.
- [x] `get.kernaio.com` redirects (302) to `raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh`
      (2026-09-04; it pointed at the old `KernAIO/kern` path). It is still a script to download and
      run, never to pipe.
- [ ] `install.sh` and `kern-upgrade.sh` are the only two scripts a self-hoster runs; both are
      shellcheck-clean and tested in `selfhost.yml` — add whatever the VM run found.

## 4. A developer ships a module of their own — by 2026-09-14 ([#4](https://github.com/KernAIO/app/issues/4))

Today a third-party module needs a line in `repos/shell/src/lib/modules/registry.ts` and a line
in `repos/core/src/service.ts` (`featureModules`) — a fork of both. v1.0 makes it a build.

- [x] `shell` Dockerfile: `KERN_EXTRA_MODULES` installs the packages and
      `scripts/extra-modules.mjs` rewrites `src/lib/modules/extra.ts`; verified by building the
      image with `@kernhq/module-template@0.2.9` (2026-09-04).
- [x] `core` Dockerfile: the same argument, rewriting `src/extra-modules.ts`; the built image
      lists `template` among its modules (2026-09-04).
- [x] `selfhost/`: `KERN_IMAGE_SHELL` and `KERN_IMAGE_CORE` in all three stacks and
      `.env.example`; the drift check passes (2026-09-04).
- [x] `docs/developers/module-development.md` rewritten as a procedure (2026-09-04). Step 3 —
      the module linked into a local Kern through the same generator — was run against the
      template in both hosts. **Not yet** followed end to end by an agent with no other context.
- [x] `npx degit KernAIO/module-template` produces a module whose `pnpm test` passes on a clean
      machine with no umbrella around it (2026-09-04: degit into an empty directory,
      `pnpm install --ignore-workspace`, 11 tests green, registry packages only).
- [x] `npx degit KernAIO/module-template` is the one way; the README no longer promises
      `npm create kern-module` (2026-09-04).
- [x] `@kernhq/module-template` 0.2.9 and `@kernhq/workflow` 0.1.1 resolve from the public
      registry with no token (2026-09-04).

## 5. It is safe to sell — by 2026-09-16 ([#5](https://github.com/KernAIO/app/issues/5))

- [x] `@kernhq/testing`'s permission matrix runs in every first-party module and in the template
      (2026-09-04).
- [x] Every module carries an isolation test (2026-09-04: chat, quire, mail and billing joined
      tracker, hr and inventory). Doing it found that **`mod_mail` had no row-level security at
      all** and that chat's and mail's migration folders were not replay-safe; all three are
      fixed and guarded. Still deliberately unsecured, each with its reason in the module's test:
      billing's `subscriptions`, `overrides` and `workspace_usage` (instance records the
      entitlement resolver reads outside any workspace), tracker's `intake_tokens` and
      `workspaces` (looked up by a stranger's token and by the scheduler), and in core `files`,
      `invitations`, `mcp_codes`, `mcp_consents` and `mcp_tokens` — those five have explicit
      filters everywhere and are the next thing to put behind a policy.
      **This list said ten and the database says twelve** (2026-09-05). `mod_core.memberships` and
      `mod_core.notifications` carry `workspace_id` and no policy: deliberate, and named as global
      in `repos/core/CLAUDE.md` because both are read outside any workspace binding — but a list
      that omits the two a reader cares about most is not an inventory. Counted against the live
      catalogue rather than the migration text, which is the only source that settles it: 155
      tenant tables in `mod_*`, 143 with RLS enabled, forced and holding a policy, and these
      twelve without. Ask `pg_class`/`pg_policy` on a real database; a `create policy` grep over
      the SQL cannot see a table nobody wrote one for.
- [ ] **The guard that should catch a missing policy cannot see one.** Only `chat`'s and `mail`'s
      `migrations.test.ts` assert that no tenant table lacks a policy. The other five assert
      `FORCE` on tables that already have one, so a table with no policy passes by never being
      looked at — which is exactly how twelve went uncounted while every module's test was green.
      Copy chat's catalogue query into the other five, and make it fail on any `mod_*` table with a
      `workspace_id` column that is absent from the module's own declared exception list.
- [x] Rate limits and security headers checked from outside: `scripts/check-edge.sh`
      (2026-09-04). It found the shell sent no HSTS — Caddy now adds it; the cloud gets it at the
      next rollout.
- [x] `repos/shell/tests/e2e/ux.spec.ts` green on every route in all four renderings — 326
      checks — with the thirteen routes hr 0.23 and inventory 0.5 added (2026-09-04).
- [x] `.audit/FINDINGS.md`: 19 of 20 closed before today; #12 (the UX guard's route coverage)
      closed with the sweep above (2026-09-04).
- [x] `core-worker` reports healthy on the cloud — every container `(healthy)`, worker log clean
      for 24 h (verified 2026-09-03).
- [ ] Cut **v1.0.0** by hand: `gh workflow run release.yml --repo KernAIO/app --field bump=major`;
      then re-sign its feed with `schemaChanges` and `minPreviousVersion` set deliberately.

## Release machinery follow-ups (small, any day)

- [x] A `failure()` notification on `release.yml` and `rollout.yml` (2026-09-04).
- [x] A module's `!`/`BREAKING CHANGE` changeset marks the platform feed `breaking`: `release.yml`
      scans the service commits for a `!`/`BREAKING CHANGE` and each reached module's changelog
      section for "Major Changes", and hands the result to `release-feed.yml` instead of a
      literal `additive` (2026-09-04). First exercised by whichever release next breaks something.
- [x] `docs/developers/releases-and-migrations.md`: *When the nightly is red* (2026-09-04).
- [ ] Renovate: fix its onboarding or remove `renovate.json` from every repository; it has never
      opened a pull request. Solved 2026-09-04 from the Mend dashboard: Renovate *is* running —
      every repository is onboarded and jobs run hourly — but the org's engine setting
      "Dependency Updates (Renovate)" is **Silent**, which scans and opens nothing. Owner switches
      it to Interactive (developer.mend.io → KernAIO → Settings); the dashboards and Monday PRs
      follow by themselves. Not a launch item: the reach moves the `@kernhq/*` pins.
- [x] `repos/shell`'s 19 uncommitted files landed as the billing-suspension toast;
      `module-tracker`'s and `module-chat`'s client changes were widget strings looked up under
      the wrong prefix, landed as patches (2026-09-04).

## After v1.0

Recruiting and CRM (both start from the workflow engine), Automation, Calendar, Drive, Calls, AI,
the personal mail inbox, email-to-issue, outgoing webhooks — in the order a paying team asks.
