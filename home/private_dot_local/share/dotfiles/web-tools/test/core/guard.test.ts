// Structural guard: src/core/** must not reach for ambient host capabilities.
// The banned patterns are scanned line by line. The fixture test proves the
// scanner actually fires, so a green run means the rule was really checked.

import { describe, expect, test } from "bun:test"
import { readdirSync, readFileSync, statSync } from "node:fs"
import { join, resolve } from "node:path"

const CORE_DIR = resolve(import.meta.dir, "../../src/core")

/** Patterns forbidden in core. Each has a reason, shown when it fires. */
export const BANNED: ReadonlyArray<{ readonly pattern: RegExp; readonly why: string }> = [
  { pattern: /globalThis\.fetch\(/, why: "use HttpClient, not the global fetch" },
  { pattern: /(^|[^.\w])fetch\(/, why: "bare fetch(); use HttpClient" },
  { pattern: /process\.env/, why: "no ambient environment; config is injected" },
  { pattern: /setTimeout\(/, why: "no raw timers; use Effect.sleep / Schedule" },
  { pattern: /setInterval\(/, why: "no raw timers; use Effect.repeat / Schedule" },
  { pattern: /child_process/, why: "child processes live in the key lane, not core" },
  { pattern: /new Promise/, why: "no bare Promise orchestration; use Effect" },
]

const sourceFiles = (dir: string): string[] => {
  const out: string[] = []
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) out.push(...sourceFiles(full))
    else if (name.endsWith(".ts")) out.push(full)
  }
  return out
}

/** Scan source text, ignoring line comments and block-comment bodies. */
export const scan = (source: string): Array<{ line: number; text: string; why: string }> => {
  const hits: Array<{ line: number; text: string; why: string }> = []
  let inBlock = false
  source.split("\n").forEach((raw, idx) => {
    let line = raw
    if (inBlock) {
      const end = line.indexOf("*/")
      if (end === -1) return
      inBlock = false
      line = line.slice(end + 2)
    }
    // Strip block comments that open and close on this line, and a trailing open.
    line = line.replace(/\/\*[\s\S]*?\*\//g, "")
    const open = line.indexOf("/*")
    if (open !== -1) {
      inBlock = true
      line = line.slice(0, open)
    }
    const code = line.replace(/\/\/.*$/, "")
    for (const b of BANNED) {
      if (b.pattern.test(code)) hits.push({ line: idx + 1, text: raw.trim(), why: b.why })
    }
  })
  return hits
}

describe("structural guard: src/core/** is host-independent", () => {
  test("no banned pattern appears in any core source file", () => {
    const violations: string[] = []
    for (const file of sourceFiles(CORE_DIR)) {
      for (const hit of scan(readFileSync(file, "utf8"))) {
        violations.push(`${file}:${hit.line} ${hit.why}: ${hit.text}`)
      }
    }
    expect(violations).toEqual([])
  })

  test("the scanner fires on a violating fixture (proves the guard is live)", () => {
    const fixture = [
      "const a = globalThis.fetch('x')",
      "const b = fetch('y')",
      "const c = process.env.SECRET",
      "setTimeout(() => {}, 1)",
      "import { spawn } from 'child_process'",
      "const d = new Promise((r) => r(1))",
    ].join("\n")
    const hits = scan(fixture)
    const whys = new Set(hits.map((h) => h.why))
    expect(hits.length).toBeGreaterThanOrEqual(6)
    expect(whys.has("use HttpClient, not the global fetch")).toBe(true)
    expect(whys.has("bare fetch(); use HttpClient")).toBe(true)
    expect(whys.has("no ambient environment; config is injected")).toBe(true)
    expect(whys.has("no raw timers; use Effect.sleep / Schedule")).toBe(true)
    expect(whys.has("child processes live in the key lane, not core")).toBe(true)
    expect(whys.has("no bare Promise orchestration; use Effect")).toBe(true)
  })

  test("a banned pattern inside a comment is ignored (no false positive)", () => {
    expect(scan("// we never call fetch( here\n/* process.env is banned */\nconst x = 1")).toEqual([])
  })

  test("a method call named fetch on a service is not flagged as bare fetch", () => {
    expect(scan("const r = yield* wf.fetch(url)").length).toBe(0)
    expect(scan("const r = client.fetch(url)").length).toBe(0)
  })
})
