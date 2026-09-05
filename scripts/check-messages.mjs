/**
 * Fail when a `t()` key is not defined anywhere.
 *
 *   node scripts/check-messages.mjs [moduleDir ...]     (default: the current package)
 *   node scripts/check-messages.mjs --all-modules       every module repository in the workspace
 *
 * `--all-modules` reads scripts/repos.mjs rather than a list typed into package.json, which is
 * where the eight module directories used to be written out by hand — a ninth would have been
 * checked by nothing.
 *
 * `t()` returns the **key** when nothing defines it. That is deliberate — a missing string that
 * renders as `chat.nav` is visibly broken, where an empty one is a blank space nobody reports — but
 * it means a typo ships silently green: the build passes, the types pass, and a customer reads
 * `tracker.common.widget_issues_title` off the screen.
 *
 * That happened, at 164 call sites across six modules, from one bug in `scopedT`. Nothing caught it
 * because nothing was looking. This looks.
 *
 * A key resolves if it is in this module's own bundle (`src/client/i18n.ts`) or, when written
 * `common.x`, in the framework's shared bundle.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { MODULES } from './repos.mjs'

const here = dirname(fileURLToPath(import.meta.url))
let dirs = process.argv.slice(2)

if (dirs.includes('--all-modules')) {
  const wanted = MODULES.map((name) => join(here, '..', 'repos', name))
  const absent = wanted.filter((dir) => !existsSync(join(dir, 'package.json')))
  if (absent.length > 0) {
    // Never silently: a check that covers less than it claims to is the whole reason this file and
    // scripts/repos.mjs exist.
    console.error(
      `not checked out, so not checked: ${absent.map((d) => d.split('/').pop()).join(', ')} — run pnpm setup`,
    )
  }
  dirs = wanted.filter((dir) => !absent.includes(dir))
}

if (dirs.length === 0) dirs.push(process.cwd())

/** Keys the framework's `common` bundle defines. Quote style varies with the formatter. */
function commonKeys() {
  for (const p of [
    join(here, '..', 'repos', 'kernel', 'packages', 'ui', 'src', 'lib', 'common-messages.ts'),
    join(here, '..', 'node_modules', '@kernhq', 'ui', 'src', 'lib', 'common-messages.ts'),
    join(process.cwd(), 'node_modules', '@kernhq', 'ui', 'dist', 'common-messages.js'),
  ]) {
    if (!existsSync(p)) continue
    const src = readFileSync(p, 'utf8')
    return new Set([...src.matchAll(/['"]common\.([a-z0-9_]+)['"]/g)].map((m) => m[1]))
  }
  return null
}

const common = commonKeys()
if (!common) {
  console.error('Could not find the framework common bundle — cannot check message keys.')
  process.exit(1)
}

let failed = false
for (const dir of dirs) {
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
  const id = pkg.name.replace('@kernhq/module-', '')
  // A module keeps its strings in `i18n.ts`, or in `messages.ts` with `i18n.ts` as the wrapper —
  // hr and inventory do the latter, and reading only the first reported 1,897 keys "nothing
  // defines" in a module whose every screen was fine.
  const bundles = ['i18n.ts', 'messages.ts'].map((f) => join(dir, 'src', 'client', f)).filter(existsSync)
  if (bundles.length === 0) continue

  const bundle = bundles.map((p) => readFileSync(p, 'utf8')).join('\n')
  const own = new Set([...bundle.matchAll(new RegExp(`['"]${id}\\.([a-z0-9_]+)['"]`, 'g'))].map((m) => m[1]))

  const files = []
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const full = join(d, e.name)
      if (e.isDirectory()) walk(full)
      else if (/\.(ts|svelte)$/.test(e.name) && !bundles.includes(full)) files.push(full)
    }
  }
  walk(join(dir, 'src', 'client'))

  const missing = new Map()
  for (const file of files) {
    for (const m of readFileSync(file, 'utf8').matchAll(/\bt\(\s*['"]([a-z0-9_.]+)['"]/g)) {
      const key = m[1]
      const ok = key.startsWith('common.') ? common.has(key.slice(7)) : own.has(key)
      if (!ok) missing.set(key, (missing.get(key) ?? new Set()).add(file.slice(dir.length + 1)))
    }
  }

  if (missing.size === 0) {
    console.log(`✓ ${pkg.name}: every t() key resolves (${own.size} own, ${common.size} shared)`)
    continue
  }
  failed = true
  console.error(`\n${pkg.name}: ${missing.size} key(s) nothing defines — these render as themselves`)
  for (const [key, where] of [...missing].sort()) {
    console.error(`  ${key}`)
    for (const f of [...where].slice(0, 3)) console.error(`      ${f}`)
  }
}
process.exit(failed ? 1 : 0)
