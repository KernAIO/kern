#!/usr/bin/env node
/**
 * The one list of Kern repositories, in the order everything builds.
 *
 *   node scripts/repos.mjs             # every workspace repository, one per line, in build order
 *   node scripts/repos.mjs --modules   # only the module repositories
 *   node scripts/repos.mjs --paths     # as repos/<name>, skipping anything not checked out
 *
 * It is one list because it was three, and they disagreed. `dev-setup.sh` cloned the umbrella
 * into `repos/app` instead of cloning `shell`, and `run-all.sh` left `shell` out of its build
 * order entirely — so `pnpm setup` produced a workspace with no user interface, `pnpm dev`
 * started every backend and no front end, and `pnpm build|lint|test|typecheck` skipped the whole
 * UI repository without saying so. That is how shell defects cleared a quality bar for months.
 *
 * `scripts/check-repos.mjs` holds this list against the organisation, so a repository that is
 * created and never added here fails a check instead of being quietly absent from every command.
 */
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const umbrella = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/**
 * Build order: the framework, then the modules that peer it, then the services that host them,
 * then the app shell that carries their screens, then the documentation site.
 *
 * `run-all.sh` walks this in order and `dev-setup.sh` clones it. A repository with no script for
 * the task being run is skipped, so an entry costs nothing but is never silently missing.
 */
export const ORDER = [
  'kernel',
  'module-tracker',
  'module-chat',
  'module-quire',
  'module-hr',
  'module-mail',
  'module-billing',
  'module-inventory',
  'module-meet',
  'module-template',
  'core',
  'chat',
  'mail',
  'collab',
  'shell',
  'docs',
]

/**
 * Repositories the organisation has that deliberately do not belong in `repos/`, and why.
 *
 * Every one of these is a decision, not an oversight — which is the point of writing them down:
 * `check-repos.mjs` fails on anything in the organisation that is in neither list, so a new
 * repository forces someone to say which of the two it is.
 */
export const OUTSIDE = {
  app: 'the umbrella itself — this repository. Cloning it into repos/ makes a second, pointless copy of the workspace.',
  website:
    'kernaio.com — private, and checked out beside the umbrella rather than inside repos/ (scripts/status.sh looks for it there).',
  brand: 'the logo and its usage rules. Nothing here builds it or imports it.',
  modules: 'archived — every module has had its own repository since 2026-08-25.',
  '.github': "the organisation's profile and shared community files, not a package.",
}

/** The module repositories, in build order. */
export const MODULES = ORDER.filter((name) => name.startsWith('module-'))

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2)
  let names = args.includes('--modules') ? MODULES : ORDER

  if (args.includes('--paths')) {
    const missing = names.filter((name) => !existsSync(join(umbrella, 'repos', name, 'package.json')))
    if (missing.length > 0) {
      // Not fatal — a caller asking for paths wants to run over what is here — but never silent:
      // a check that quietly covers less than it says it does is the defect this file exists for.
      console.error(`not checked out, so not covered: ${missing.join(', ')} — run pnpm setup`)
    }
    names = names.filter((name) => !missing.includes(name)).map((name) => `repos/${name}`)
  }

  console.log(names.join('\n'))
}
