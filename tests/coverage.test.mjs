import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../Coverage.js", import.meta.url), "utf8")
const context = vm.createContext({
  Array,
  Error,
  JSON,
  Math,
  Number,
  String,
  isFinite
})
vm.runInContext(source, context)

// The MCP server wraps its payload twice: a JSON-RPC envelope whose text
// content block holds the real answer as a JSON string.
function envelope(payload, extra = {}) {
  return JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    result: {
      content: [{ type: "text", text: JSON.stringify(payload) }],
      ...extra
    }
  })
}

const nationalPayload = {
  count: 2,
  total: 4,
  next_page_token: null,
  items: [
    {
      document_id: 11,
      document_version: 2,
      document_display_id: "30.3",
      document_type: "NCD",
      title: "Acupuncture",
      chapter: "30",
      last_updated: "05/25/2022",
      url: "/data/ncd?ncdid=11&ncdver=2"
    },
    {
      document_id: 373,
      document_display_id: "30.3.3",
      document_type: "NCD",
      title: "Acupuncture for Chronic  Lower Back Pain (cLBP)",
      chapter: "30",
      last_updated: "10/28/2024",
      url: "/data/ncd?ncdid=373&ncdver=1"
    }
  ]
}

const localPayload = {
  count: 1,
  total: 3,
  items: [
    {
      document_id: 37873,
      document_display_id: "L37873",
      title: "Topical Oxygen Therapy",
      contractor_name: null,
      contractor_name_type: "Palmetto GBA\r\n(MAC - Part A, MAC - Part B)",
      effective_date: "04/16/2026",
      retirement_date: "N/A",
      updated_on: "04/07/2026",
      url: "https://www.cms.gov/medicare-coverage-database/view/lcd.aspx?lcdid=37873&ver=18"
    }
  ]
}

test("buildRequestBody targets the national tool by default", () => {
  const body = JSON.parse(context.buildRequestBody("acupuncture", "national", 8))
  assert.equal(body.method, "tools/call")
  assert.equal(body.params.name, "search_national_coverage")
  assert.equal(body.params.arguments.keyword, "acupuncture")
  assert.equal(body.params.arguments.limit, 8)
  assert.equal(body.params.arguments.count_total, true)
})

test("buildRequestBody targets the local tool for local scope", () => {
  const body = JSON.parse(context.buildRequestBody("oxygen", "local", 8))
  assert.equal(body.params.name, "search_local_coverage")
})

test("an unknown scope falls back to national", () => {
  const body = JSON.parse(context.buildRequestBody("oxygen", "nonsense", 8))
  assert.equal(body.params.name, "search_national_coverage")
})

// The keyword is escaped by JSON.stringify, never pasted into a string.
test("buildRequestBody escapes a keyword containing quotes", () => {
  const body = JSON.parse(context.buildRequestBody('say "ah"', "national", 8))
  assert.equal(body.params.arguments.keyword, 'say "ah"')
})

test("buildRequestBody refuses a blank keyword", () => {
  assert.equal(context.buildRequestBody("   ", "national", 8), "")
})

test("clampResultLimit holds the panel between five and twelve rows", () => {
  assert.equal(context.clampResultLimit(2), 5)
  assert.equal(context.clampResultLimit(40), 12)
  assert.equal(context.clampResultLimit("not a number"), 8)
})

test("parseSearchResponse unwraps both layers of a national answer", () => {
  const parsed = context.parseSearchResponse(envelope(nationalPayload), "national")
  assert.equal(parsed.totalCount, 4)
  assert.equal(parsed.documents.length, 2)
  const first = parsed.documents[0]
  assert.equal(first.displayId, "30.3")
  assert.equal(first.type, "NCD")
  assert.equal(first.chapter, "30")
  assert.equal(first.updated, "05/25/2022")
})

// National results carry a site-relative url; local ones are already absolute.
test("parseSearchResponse resolves a relative document url", () => {
  const parsed = context.parseSearchResponse(envelope(nationalPayload), "national")
  assert.equal(
    parsed.documents[0].url,
    "https://www.cms.gov/medicare-coverage-database/data/ncd?ncdid=11&ncdver=2"
  )
})

test("parseSearchResponse leaves an absolute document url alone", () => {
  const parsed = context.parseSearchResponse(envelope(localPayload), "local")
  assert.equal(
    parsed.documents[0].url,
    "https://www.cms.gov/medicare-coverage-database/view/lcd.aspx?lcdid=37873&ver=18"
  )
})

test("parseSearchResponse collapses the run of whitespace in a title", () => {
  const parsed = context.parseSearchResponse(envelope(nationalPayload), "national")
  assert.equal(parsed.documents[1].title, "Acupuncture for Chronic Lower Back Pain (cLBP)")
})

// The contractor field arrives with a carriage return that would render as a
// box in a PlainText label.
test("parseSearchResponse flattens the contractor field", () => {
  const parsed = context.parseSearchResponse(envelope(localPayload), "local")
  assert.equal(parsed.documents[0].contractor, "Palmetto GBA (MAC - Part A, MAC - Part B)")
})

test("parseSearchResponse drops the N/A placeholder dates", () => {
  const parsed = context.parseSearchResponse(envelope(localPayload), "local")
  assert.equal(parsed.documents[0].retired, "")
  assert.equal(parsed.documents[0].effective, "04/16/2026")
  assert.equal(parsed.documents[0].updated, "04/07/2026")
})

// Local results omit document_type; the display id prefix carries it instead.
test("documentType is derived from the display id when absent", () => {
  assert.equal(context.documentType({ document_display_id: "L37873" }, "local"), "LCD")
  assert.equal(context.documentType({ document_display_id: "A56789" }, "local"), "Article")
  assert.equal(context.documentType({ document_display_id: "30.3" }, "national"), "NCD")
  assert.equal(context.documentType({}, "local"), "LCD")
})

// total is null unless the caller asks for it, so the rows returned are the
// honest fallback rather than reporting zero.
test("a null total falls back to the number of rows returned", () => {
  const parsed = context.parseSearchResponse(
    envelope({ count: 2, total: null, items: nationalPayload.items }),
    "national"
  )
  assert.equal(parsed.totalCount, 2)
})

test("parseSearchResponse treats an empty answer as no matches", () => {
  const parsed = context.parseSearchResponse(
    envelope({ count: 0, total: 0, next_page_token: null, items: [] }),
    "national"
  )
  assert.equal(parsed.totalCount, 0)
  assert.equal(parsed.documents.length, 0)
})

test("parseSearchResponse raises a JSON-RPC error", () => {
  assert.throws(
    () => context.parseSearchResponse('{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"bad argument"}}', "national"),
    /bad argument/
  )
})

test("parseSearchResponse raises a tool-level error", () => {
  assert.throws(
    () => context.parseSearchResponse(envelope({}, { isError: true }), "national"),
    /Error/
  )
})

test("parseSearchResponse rejects a body with no content block", () => {
  assert.throws(() => context.parseSearchResponse('{"jsonrpc":"2.0","id":1,"result":{}}', "national"))
  assert.throws(() => context.parseSearchResponse("not json", "national"))
})

test("scopeLabel names both scopes", () => {
  assert.equal(context.scopeLabel("national"), "National (NCD)")
  assert.equal(context.scopeLabel("local"), "Local (LCD)")
  assert.equal(context.scopeLabel("nonsense"), "National (NCD)")
})

test("formatCount groups thousands", () => {
  assert.equal(context.formatCount(2431), "2,431")
  assert.equal(context.formatCount("nope"), "0")
})
