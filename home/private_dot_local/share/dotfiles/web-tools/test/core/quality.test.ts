import { describe, expect, test } from "bun:test"
import { BOT_WALL_MARKERS, assessQuality, countWords } from "../../src/core/quality.ts"

const long = Array.from({ length: 40 }, (_, i) => `word${i}`).join(" ")

// Table-driven: each row is one bot-wall / quality case.
type Row =
  | { readonly name: string; readonly headers?: Record<string, string>; readonly body: string; readonly visible?: string; readonly expect: "good" | "thin" }
  | { readonly name: string; readonly headers?: Record<string, string>; readonly body: string; readonly visible?: string; readonly expect: "blocked"; readonly reason: string }

// A blocked row must name its reason; the type enforces it.
const rows: ReadonlyArray<Row> = [
  { name: "cf-mitigated header blocks even with words", headers: { "cf-mitigated": "challenge" }, body: long, visible: long, expect: "blocked", reason: "cloudflare-mitigated" },
  { name: "Cloudflare 'Just a moment' interstitial", body: "<title>Just a moment...</title>" + long, visible: long, expect: "blocked", reason: "cloudflare-challenge" },
  { name: "Cloudflare 'Attention Required'", body: "Attention Required! | Cloudflare " + long, visible: long, expect: "blocked", reason: "cloudflare-attention" },
  { name: "cf-browser-verification marker", body: `<div id="cf-browser-verification">${long}</div>`, visible: long, expect: "blocked", reason: "cloudflare-verification" },
  { name: "Akamai bot manager", body: "akamai bot manager " + long, visible: long, expect: "blocked", reason: "akamai-captcha" },
  { name: "PerimeterX captcha", body: "<div id=px-captcha>" + long, visible: long, expect: "blocked", reason: "perimeterx" },
  { name: "DataDome", body: "datadome " + long, visible: long, expect: "blocked", reason: "datadome" },
  { name: "enable JavaScript shell", body: "Please enable JavaScript to continue " + long, visible: long, expect: "blocked", reason: "js-required-shell" },
  { name: "enable JavaScript (cookies variant)", body: "Please enable JavaScript and cookies to continue " + long, visible: long, expect: "blocked", reason: "js-required-shell" },
  { name: "single-page-app shell", body: "You need to enable JavaScript to run this app.", visible: "You need to enable JavaScript to run this app.", expect: "blocked", reason: "js-required-shell-noscript" },
  { name: "enough words, no marker => good", body: long, visible: long, expect: "good" },
  { name: "below thinWords => thin", body: "short page", visible: "short page", expect: "thin" },
]

describe("assessQuality (bot-wall table)", () => {
  for (const row of rows) {
    test(row.name, () => {
      const v = assessQuality({
        headers: row.headers ?? {},
        body: row.body,
        visibleText: row.visible ?? row.body,
        thinWords: 25,
      })
      expect(v.kind).toBe(row.expect)
      if (row.expect === "blocked" && v.kind === "blocked") expect(v.reason).toBe(row.reason)
    })
  }

  test("a bot-wall signal wins over a high word count", () => {
    const v = assessQuality({ headers: {}, body: "Just a moment... " + long, visibleText: long, thinWords: 25 })
    expect(v.kind).toBe("blocked")
  })

  test("every marker in the table has a unique name", () => {
    const names = BOT_WALL_MARKERS.map((m) => m.name)
    expect(new Set(names).size).toBe(names.length)
  })
})

describe("countWords", () => {
  test("counts tokens that contain a letter or digit, ignores punctuation-only tokens", () => {
    expect(countWords("alpha beta, ... 42 -- gamma")).toBe(4)
  })
  test("empty and whitespace-only text is zero words", () => {
    expect(countWords("   \n\t ")).toBe(0)
  })
})
