// Pure HTML -> markdown extractor for the direct tier. No DOM library: a small
// tokenizer that is good enough for article-shaped pages and that is fully
// testable without I/O.
//
// Prompt-injection hygiene (required): HTML comments, elements hidden with
// `hidden`, `aria-hidden="true"`, or inline `display:none` / zero-size styles,
// and all script/style/template content are dropped before any text is kept.

const DROP_TAGS = new Set([
  "script",
  "style",
  "noscript",
  "template",
  "svg",
  "canvas",
  "iframe",
  "object",
  "embed",
  "nav",
  "header",
  "footer",
  "aside",
  "form",
  "button",
  "select",
  "textarea",
  "input",
  "dialog",
])

const VOID_TAGS = new Set(["br", "img", "hr", "meta", "link", "input", "source", "wbr", "col", "area", "base"])

interface Token {
  readonly kind: "open" | "close" | "text"
  readonly name: string
  readonly attrs: Readonly<Record<string, string>>
  readonly text: string
  readonly selfClosing: boolean
}

const ENTITIES: Readonly<Record<string, string>> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  mdash: "—",
  ndash: "–",
  hellip: "…",
  copy: "©",
  reg: "®",
  trade: "™",
  rsquo: "’",
  lsquo: "‘",
  rdquo: "”",
  ldquo: "“",
}

export const decodeEntities = (s: string): string =>
  s.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (m, body: string) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X"
        ? Number.parseInt(body.slice(2), 16)
        : Number.parseInt(body.slice(1), 10)
      if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) return ""
      return String.fromCodePoint(code)
    }
    return ENTITIES[body.toLowerCase()] ?? m
  })

const ATTR_RE = /([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g

const parseAttrs = (raw: string): Record<string, string> => {
  const out: Record<string, string> = {}
  for (const m of raw.matchAll(ATTR_RE)) {
    out[(m[1] ?? "").toLowerCase()] = m[2] ?? m[3] ?? m[4] ?? ""
  }
  return out
}

/** Tokenise HTML into open/close/text tokens. Comments and doctype are dropped. */
export const tokenize = (html: string): ReadonlyArray<Token> => {
  const tokens: Token[] = []
  let i = 0
  const n = html.length
  while (i < n) {
    const lt = html.indexOf("<", i)
    if (lt === -1) {
      tokens.push({ kind: "text", name: "", attrs: {}, text: html.slice(i), selfClosing: false })
      break
    }
    if (lt > i) {
      tokens.push({ kind: "text", name: "", attrs: {}, text: html.slice(i, lt), selfClosing: false })
    }
    if (html.startsWith("<!--", lt)) {
      const end = html.indexOf("-->", lt + 4)
      i = end === -1 ? n : end + 3
      continue
    }
    if (html.startsWith("<!", lt) || html.startsWith("<?", lt)) {
      const end = html.indexOf(">", lt)
      i = end === -1 ? n : end + 1
      continue
    }
    const close = html[lt + 1] === "/"
    const start = close ? lt + 2 : lt + 1
    const m = /^([a-zA-Z][a-zA-Z0-9:-]*)/.exec(html.slice(start, start + 64))
    if (!m) {
      tokens.push({ kind: "text", name: "", attrs: {}, text: "<", selfClosing: false })
      i = lt + 1
      continue
    }
    const name = (m[1] ?? "").toLowerCase()
    const gt = findTagEnd(html, start + name.length)
    if (gt === -1) {
      i = n
      break
    }
    const inner = html.slice(start + name.length, gt)
    const selfClosing = /\/\s*$/.test(inner)
    tokens.push({
      kind: close ? "close" : "open",
      name,
      attrs: close ? {} : parseAttrs(inner.replace(/\/\s*$/, "")),
      text: "",
      selfClosing,
    })
    i = gt + 1
    // Raw-text elements: consume until the matching close tag so script/style
    // content is never tokenised as markup.
    if (!close && (name === "script" || name === "style")) {
      const endRe = new RegExp(`</${name}\\s*>`, "i")
      const rest = html.slice(i)
      const found = endRe.exec(rest)
      const body = found ? rest.slice(0, found.index) : rest
      if (body.length > 0) tokens.push({ kind: "text", name: "", attrs: {}, text: body, selfClosing: false, })
      i = found ? i + found.index + found[0].length : n
      tokens.push({ kind: "close", name, attrs: {}, text: "", selfClosing: false })
    }
  }
  return tokens
}

// Find the closing '>' of a tag, skipping quoted attribute values.
const findTagEnd = (html: string, from: number): number => {
  let quote: string | null = null
  for (let k = from; k < html.length; k++) {
    const c = html[k]
    if (quote) {
      if (c === quote) quote = null
    } else if (c === '"' || c === "'") {
      quote = c
    } else if (c === ">") {
      return k
    }
  }
  return -1
}

/** True when an element is hidden from a reader and must be dropped with its subtree. */
export const isHidden = (attrs: Readonly<Record<string, string>>): boolean => {
  if (attrs["hidden"] !== undefined) return true
  if ((attrs["aria-hidden"] ?? "").toLowerCase() === "true") return true
  const style = (attrs["style"] ?? "").toLowerCase().replace(/\s+/g, "")
  if (style.includes("display:none")) return true
  if (style.includes("visibility:hidden")) return true
  if (/(^|;)(width|height):0(px)?(;|$)/.test(style)) return true
  if (/font-size:0(px)?(;|$)/.test(style)) return true
  if (/opacity:0(;|$)/.test(style)) return true
  return false
}

const BLOCK_TAGS = new Set([
  "p",
  "div",
  "section",
  "article",
  "main",
  "li",
  "ul",
  "ol",
  "tr",
  "table",
  "blockquote",
  "figure",
  "figcaption",
  "dl",
  "dt",
  "dd",
  "br",
  "hr",
])

const HEADING_LEVEL: Readonly<Record<string, number>> = { h1: 1, h2: 2, h3: 3, h4: 4, h5: 5, h6: 6 }

/**
 * Walk the tokens and emit markdown. `main`/`article` take precedence when
 * present (the caller decides; see `extractMarkdown`). Dropped subtrees are
 * skipped by depth counting.
 */
const render = (tokens: ReadonlyArray<Token>): string => {
  const out: string[] = []
  let skipDepth = 0
  let skipName = ""
  let inPre = false
  let inCode = false
  let listDepth = 0
  const ordered: boolean[] = []
  let linkHref: string | null = null
  let linkText: string[] = []
  let inTable = false
  let cellFirst = true

  const push = (s: string) => {
    if (linkHref !== null) linkText.push(s)
    else out.push(s)
  }

  for (const tok of tokens) {
    if (tok.kind === "open" && skipDepth === 0 && (DROP_TAGS.has(tok.name) || isHidden(tok.attrs))) {
      if (!tok.selfClosing && !VOID_TAGS.has(tok.name)) {
        skipDepth = 1
        skipName = tok.name
      }
      continue
    }
    if (skipDepth > 0) {
      if (tok.kind === "open" && tok.name === skipName && !tok.selfClosing && !VOID_TAGS.has(tok.name)) skipDepth++
      else if (tok.kind === "close" && tok.name === skipName) skipDepth--
      continue
    }
    if (tok.kind === "text") {
      if (inPre) {
        push(decodeEntities(tok.text))
      } else {
        const collapsed = decodeEntities(tok.text).replace(/\s+/g, " ")
        if (collapsed.trim() === "" && !inCode) {
          if (collapsed.length > 0 && out.length > 0) push(" ")
          continue
        }
        push(collapsed)
      }
      continue
    }
    const name = tok.name
    if (tok.kind === "open") {
      if (HEADING_LEVEL[name]) {
        out.push("\n\n" + "#".repeat(HEADING_LEVEL[name]) + " ")
      } else if (name === "pre") {
        inPre = true
        out.push("\n\n```\n")
      } else if (name === "code" && !inPre) {
        inCode = true
        push("`")
      } else if (name === "li") {
        const indent = "  ".repeat(Math.max(0, listDepth - 1))
        const marker = ordered[ordered.length - 1] ? "1. " : "- "
        out.push("\n" + indent + marker)
      } else if (name === "ul" || name === "ol") {
        listDepth++
        ordered.push(name === "ol")
        out.push("\n")
      } else if (name === "a" && tok.attrs["href"]) {
        linkHref = safeHref(tok.attrs["href"])
        linkText = []
      } else if (name === "tr") {
        inTable = true
        cellFirst = true
        out.push("\n")
      } else if (name === "td" || name === "th") {
        out.push(cellFirst ? "| " : " | ")
        cellFirst = false
      } else if (name === "img") {
        const alt = (tok.attrs["alt"] ?? "").trim()
        if (alt) push(`[image: ${alt}]`)
      } else if (BLOCK_TAGS.has(name)) {
        out.push("\n")
      }
    } else if (tok.kind === "close") {
      if (HEADING_LEVEL[name]) {
        out.push("\n")
      } else if (name === "pre") {
        inPre = false
        out.push("\n```\n")
      } else if (name === "code" && !inPre) {
        inCode = false
        push("`")
      } else if (name === "ul" || name === "ol") {
        listDepth = Math.max(0, listDepth - 1)
        ordered.pop()
        out.push("\n")
      } else if (name === "a" && linkHref !== null) {
        const text = linkText.join("").replace(/\s+/g, " ").trim()
        const href = linkHref
        linkHref = null
        linkText = []
        if (text) out.push(href === "" ? text : `[${text}](${href})`)
      } else if (name === "tr") {
        if (inTable) out.push(" |\n")
        inTable = false
      } else if (BLOCK_TAGS.has(name)) {
        out.push("\n")
      }
    }
  }
  return out.join("")
}

// Keep the href only when it is not a script-bearing scheme. Returns "" to mean
// "render the link text without a target".
const safeHref = (raw: string): string => {
  const href = raw.trim()
  return /^(javascript|data|vbscript):/i.test(href) ? "" : href
}

/** Collapse runs of blank lines and trim each line's trailing spaces. */
export const tidyMarkdown = (s: string): string =>
  s
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/g, ""))
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()

/**
 * Pick the main-content subtree if the document has one. Returns the tokens
 * between the first `<main>` or `<article>` open and its matching close; falls
 * back to the whole document.
 */
export const selectMain = (tokens: ReadonlyArray<Token>): ReadonlyArray<Token> => {
  for (const wanted of ["main", "article"]) {
    const start = tokens.findIndex((t) => t.kind === "open" && t.name === wanted)
    if (start === -1) continue
    let depth = 0
    for (let k = start; k < tokens.length; k++) {
      const t = tokens[k]
      if (t === undefined) break
      if (t.kind === "open" && t.name === wanted && !t.selfClosing) depth++
      else if (t.kind === "close" && t.name === wanted) {
        depth--
        if (depth === 0) return tokens.slice(start, k + 1)
      }
    }
    return tokens.slice(start)
  }
  return tokens
}

/** Extract main-content markdown from an HTML document. Pure. */
export const extractMarkdown = (html: string): { readonly title?: string; readonly markdown: string } => {
  const tokens = tokenize(html)
  const titleTok = tokens.findIndex((t) => t.kind === "open" && t.name === "title")
  const title = titleTok === -1
    ? undefined
    : decodeEntities(tokens.slice(titleTok + 1).find((t) => t.kind === "text")?.text ?? "").trim() || undefined
  const main = selectMain(tokens)
  const markdown = tidyMarkdown(render(main))
  return title === undefined ? { markdown } : { title, markdown }
}

/** Visible text of extracted markdown, used by the quality gate. */
export const visibleText = (markdown: string): string =>
  markdown.replace(/```[\s\S]*?```/g, " ").replace(/[`#*_>|[\]()-]/g, " ")
