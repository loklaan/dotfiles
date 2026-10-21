// Structural guard over src/key and src/summariser. These are owned lanes: they
// must not use ambient fetch, process.env, raw timers, child_process, bare Promise
// orchestration, or exec. Real fixtures prove the scanner catches violations.

import { describe, expect, test } from "bun:test"
import * as fs from "node:fs"
import * as path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const pkgRoot = path.resolve(here, "../..")

/** Tokens banned in owned key and summariser code. Each is a regex with a label. */
export const BANNED: ReadonlyArray<{ readonly label: string; readonly pattern: RegExp }> = [
  { label: "globalThis.fetch", pattern: /globalThis\.fetch\b/ },
  { label: "process.env", pattern: /\bprocess\.env\b/ },
  { label: "raw setTimeout", pattern: /\bsetTimeout\s*\(/ },
  { label: "child_process", pattern: /\bchild_process\b/ },
  { label: "bare new Promise", pattern: /\bnew\s+Promise\b/ },
  { label: "exec(", pattern: /(^|[^A-Za-z0-9_.])exec\s*\(/m },
]

/** Strips // line comments and block comments so documentation can name the banned tokens. */
// A line comment starts at a line start or after whitespace, so a URL such as
// "https://x" is not mistaken for a comment and cannot hide a violation later on the line.
export const stripComments = (src: string): string =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/[^\n]*/gm, "$1")

export const scan = (src: string): Array<string> => {
  const code = stripComments(src)
  return BANNED.filter((b) => b.pattern.test(code)).map((b) => b.label)
}

const collect = (dir: string): Array<string> => {
  if (!fs.existsSync(dir)) return []
  return fs.readdirSync(dir, { recursive: true, withFileTypes: false })
    .map(String)
    .filter((f) => f.endsWith(".ts"))
    .map((f) => path.join(dir, f))
}

const ownedFiles = (): Array<string> => [
  ...collect(path.join(pkgRoot, "src/key")),
  ...collect(path.join(pkgRoot, "src/summariser")),
]

describe("structural guard: owned key and summariser code", () => {
  test("owned src files exist and are scanned", () => {
    const files = ownedFiles()
    expect(files.length).toBeGreaterThan(0)
  })

  test("no banned ambient or raw-Promise patterns in src/key or src/summariser", () => {
    const violations: Array<string> = []
    for (const file of ownedFiles()) {
      const hits = scan(fs.readFileSync(file, "utf8"))
      for (const h of hits) violations.push(`${path.relative(pkgRoot, file)}: ${h}`)
    }
    expect(violations).toEqual([])
  })

  test("the scanner rejects a deliberate violating fixture (guard proves itself)", () => {
    const fixture = [
      "import { exec } from 'node:child_process'",
      "const k = process.env.EXA_API_KEY",
      "await globalThis.fetch('https://x')",
      "setTimeout(() => {}, 10)",
      "new Promise((r) => r(1))",
      "exec('ls')",
    ].join("\n")
    const hits = scan(fixture)
    expect(hits).toEqual(expect.arrayContaining([
      "globalThis.fetch",
      "process.env",
      "raw setTimeout",
      "child_process",
      "bare new Promise",
      "exec(",
    ]))
  })

  test("a URL on the same line cannot hide a later violation", () => {
    expect(scan("const u = \"https://x\"; const k = process.env.EXA_API_KEY")).toEqual(["process.env"])
  })

  test("banned tokens inside comments are not violations", () => {
    expect(scan("// uses process.env and fetch in prose\n/* exec('x') */ const x = 1")).toEqual([])
  })
})
