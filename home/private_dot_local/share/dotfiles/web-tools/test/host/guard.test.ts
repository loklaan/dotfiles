// Structural guard over src/host. Extends the core's rule: no globalThis.fetch,
// bare fetch(, raw timers, child_process, or bare Promise orchestration in host
// code, and no process.env or node:fs outside the ONE allow-listed config loader.
//
// The allow-list is explicit and documented. There are exactly two native seams:
//   - src/host/config.ts reads process.env (the one env read) and reads the rendered
//     config file through the Effect FileSystem service. It imports NO node:fs.
//   - src/host/dns.ts is the one module that imports node:dns (the resolver).
// entry.ts reads no process state at all; it calls config.ts.

import { describe, expect, test } from "bun:test"
import { readdirSync, readFileSync, statSync } from "node:fs"
import { join, relative, resolve } from "node:path"

const HOST_DIR = resolve(import.meta.dir, "../../src/host")

/** Files allowed to use process.env / node:dns. Each has a stated reason. node:fs is allowed nowhere. */
export const ALLOW = {
  // The one config seam: the only process.env read. The file is read via the FileSystem service, not node:fs.
  "config.ts": ["process.env"],
  // The one resolver seam: the only module that imports node:dns.
  "dns.ts": ["node:dns"],
} as const

export const BANNED: ReadonlyArray<{ readonly pattern: RegExp; readonly why: string; readonly token: string }> = [
  { pattern: /globalThis\.fetch\(/, why: "use HttpClient, not the global fetch", token: "globalThis.fetch(" },
  { pattern: /(^|[^.\w])fetch\(/, why: "bare fetch(); use HttpClient", token: "fetch(" },
  { pattern: /setTimeout\(/, why: "no raw timers; use Effect.sleep / Schedule", token: "setTimeout(" },
  { pattern: /setInterval\(/, why: "no raw timers; use Effect.repeat / Schedule", token: "setInterval(" },
  { pattern: /child_process/, why: "child processes live in the key lane", token: "child_process" },
  { pattern: /new Promise/, why: "no bare Promise orchestration; use Effect", token: "new Promise" },
  { pattern: /process\.env/, why: "process.env only in an allow-listed seam", token: "process.env" },
  { pattern: /node:fs/, why: "node:fs only in an allow-listed seam", token: "node:fs" },
  { pattern: /node:dns/, why: "node:dns only in an allow-listed seam", token: "node:dns" },
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

/** Strip comments, then report banned tokens not allow-listed for this file. */
export const scan = (source: string, allowed: ReadonlyArray<string> = []): Array<{ line: number; why: string; text: string }> => {
  const hits: Array<{ line: number; why: string; text: string }> = []
  let inBlock = false
  source.split("\n").forEach((raw, idx) => {
    let line = raw
    if (inBlock) {
      const end = line.indexOf("*/")
      if (end === -1) return
      inBlock = false
      line = line.slice(end + 2)
    }
    line = line.replace(/\/\*[\s\S]*?\*\//g, "")
    const open = line.indexOf("/*")
    if (open !== -1) { inBlock = true; line = line.slice(0, open) }
    const code = line.replace(/\/\/.*$/, "")
    for (const b of BANNED) {
      if (allowed.includes(b.token)) continue
      if (b.pattern.test(code)) hits.push({ line: idx + 1, why: b.why, text: raw.trim() })
    }
  })
  return hits
}

describe("structural guard over src/host", () => {
  test("no banned pattern outside the allow-listed seams", () => {
    const violations: string[] = []
    for (const file of sourceFiles(HOST_DIR)) {
      const name = relative(HOST_DIR, file)
      const allowed = (ALLOW as Record<string, ReadonlyArray<string>>)[name] ?? []
      for (const hit of scan(readFileSync(file, "utf8"), allowed)) {
        violations.push(`${name}:${hit.line} ${hit.why}: ${hit.text}`)
      }
    }
    expect(violations).toEqual([])
  })

  test("the allow-list is exact: each seam file really uses what it is allowed", () => {
    for (const [name, tokens] of Object.entries(ALLOW)) {
      const src = readFileSync(join(HOST_DIR, name), "utf8")
      for (const t of tokens) expect(src.includes(t), `${name} should use ${t}`).toBe(true)
    }
  })

  test("node:fs is not imported anywhere in src/host (the file read goes through FileSystem)", () => {
    // scan() strips comments, so prose that mentions node:fs is not a violation.
    const offenders = sourceFiles(HOST_DIR).filter((f) => scan(readFileSync(f, "utf8"), []).some((h) => h.why.includes("node:fs")))
    expect(offenders.map((f) => relative(HOST_DIR, f))).toEqual([])
  })

  test("the scanner fires on a violating fixture (proves the guard is live)", () => {
    const fixture = [
      "const a = globalThis.fetch('x')",
      "const b = process.env.SECRET",
      "import { promises } from 'node:dns'",
      "import { readFileSync } from 'node:fs'",
      "setTimeout(() => {}, 1)",
      "const c = new Promise((r) => r(1))",
    ].join("\n")
    const whys = new Set(scan(fixture).map((h) => h.why))
    expect(whys.has("use HttpClient, not the global fetch")).toBe(true)
    expect(whys.has("process.env only in an allow-listed seam")).toBe(true)
    expect(whys.has("node:dns only in an allow-listed seam")).toBe(true)
    expect(whys.has("node:fs only in an allow-listed seam")).toBe(true)
    expect(whys.has("no raw timers; use Effect.sleep / Schedule")).toBe(true)
    expect(whys.has("no bare Promise orchestration; use Effect")).toBe(true)
  })

  test("an allow-listed token is not reported for the seam that owns it", () => {
    expect(scan("const home = process.env.HOME", ["process.env"])).toEqual([])
  })
})
