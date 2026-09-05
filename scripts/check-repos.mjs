#!/usr/bin/env node
/**
 * Fail when the workspace's repository list and the KernAIO organisation disagree.
 *
 *   node scripts/check-repos.mjs
 *
 * `scripts/repos.mjs` is the one list: `dev-setup.sh` clones it, `run-all.sh` builds it in order,
 * and `check-messages.mjs` reads the module half of it. Making it one list stops the copies
 * drifting from each other — it does nothing about the list itself going stale, which is the
 * failure that actually shipped. `shell` was missing from every copy, and nothing anywhere was
 * asking whether the set was complete: a repository absent from the list is absent from `pnpm
 * setup`, `pnpm dev`, `pnpm build`, `pnpm lint`, `pnpm test` and `pnpm typecheck` at once, and
 * every one of them still reports success.
 *
 * So this asks the organisation. Every repository it has must be either in ORDER, where the
 * workspace clones and builds it, or in OUTSIDE with the reason it stays out. A new repository is
 * then a decision somebody records rather than an omission nobody sees.
 *
 * `gh` is the source of truth. The inventory the `kern-repos` skill generates is the offline
 * stand-in, so this still checks something on a machine with no GitHub credentials — and it would
 * have caught the missing `shell`, because the inventory lists it.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ORDER, OUTSIDE } from './repos.mjs'

const umbrella = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const ORG = process.env.KERN_ORG || 'KernAIO'

/** The scripts that must read the list rather than keep a copy of it. */
const CONSUMERS = ['scripts/dev-setup.sh', 'scripts/run-all.sh', 'scripts/check-messages.mjs']

function fromGh() {
  const out = execFileSync('gh', ['repo', 'list', ORG, '--limit', '200', '--json', 'name,isArchived'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const repos = JSON.parse(out)
  if (repos.length === 0) throw new Error('gh listed no repositories')
  return { source: `the ${ORG} organisation`, repos }
}

function fromInventory() {
  const path = join(umbrella, '.claude', 'skills', 'kern-repos', 'references', 'inventory.md')
  if (!existsSync(path)) return null
  const names = [...readFileSync(path, 'utf8').matchAll(/^\| \[`([a-z0-9._-]+)`\]/gm)].map((m) => m[1])
  if (names.length === 0) return null
  // The inventory does not record whether a repository is archived, so nothing here is treated as
  // archived — an archived one still has to be named in OUTSIDE, which is where its reason belongs.
  return {
    source: 'the committed repository inventory (gh was not available)',
    repos: names.map((name) => ({ name, isArchived: false })),
  }
}

let org = null
try {
  org = fromGh()
} catch {
  org = fromInventory()
}
if (!org) {
  console.error('Could not read the repository list from gh or from the committed inventory.')
  console.error('Sign in with `gh auth login`, or regenerate the inventory:')
  console.error('  node .claude/skills/kern-repos/scripts/sync.mjs')
  process.exit(1)
}

const problems = []
const notes = []

const seen = new Set()
for (const name of ORDER) {
  if (seen.has(name)) problems.push(`${name} is in ORDER twice`)
  seen.add(name)
  if (name in OUTSIDE) problems.push(`${name} is in both ORDER and OUTSIDE — it cannot be both`)
}

for (const file of CONSUMERS) {
  const path = join(umbrella, file)
  if (!existsSync(path)) {
    problems.push(`${file} is gone, and something has to read the repository list`)
  } else if (!readFileSync(path, 'utf8').includes('repos.mjs')) {
    problems.push(`${file} no longer reads scripts/repos.mjs — it is keeping its own copy of the list again`)
  }
}

const known = new Map(org.repos.map((r) => [r.name, r]))

for (const name of ORDER) {
  const repo = known.get(name)
  if (!repo) problems.push(`ORDER has ${name}, which ${ORG} does not have — was it renamed or deleted?`)
  else if (repo.isArchived) problems.push(`${name} is archived, and the workspace still clones and builds it`)
}

for (const { name, isArchived } of org.repos) {
  if (ORDER.includes(name) || name in OUTSIDE) continue
  problems.push(
    `${ORG}/${name} is in neither ORDER nor OUTSIDE${isArchived ? ' (it is archived)' : ''}. ` +
      'Add it to ORDER, in the position it builds in, so pnpm setup/dev/build/lint/test/typecheck ' +
      'all see it — or to OUTSIDE with the reason it stays out of the workspace.',
  )
}

for (const name of Object.keys(OUTSIDE)) {
  if (!known.has(name)) notes.push(`OUTSIDE mentions ${name}, which ${ORG} no longer has`)
}

for (const note of notes) console.log(`  note: ${note}`)

if (problems.length > 0) {
  console.error(`\nThe repository list disagrees with ${org.source}:\n`)
  for (const problem of problems) console.error(`  ✗ ${problem}`)
  console.error('\nThe list is scripts/repos.mjs. Everything else reads it.')
  process.exit(1)
}

console.log(
  `✓ ${ORDER.length} repositories in the workspace, ${Object.keys(OUTSIDE).length} deliberately outside it — ` +
    `agrees with ${org.source}`,
)
