// The CMS coverage API at api.coverage.cms.gov is served through a CloudFront
// distribution that refuses whole countries outright, so a direct request
// answers 403 from much of the world. This plugin goes through the hosted MCP
// server published by anthropics/healthcare instead, which reaches the API
// from its own network and needs no key, no session, and no account.
var MCP_URL = "https://hcls.mcp.claude.com/cms_coverage/mcp"
var DATABASE_URL = "https://www.cms.gov/medicare-coverage-database/search.aspx"
// National results carry a site-relative url; local results carry an absolute
// one. Anything relative is resolved against this.
var DATABASE_BASE = "https://www.cms.gov/medicare-coverage-database"

// National coverage is set by CMS for the whole country; local coverage is set
// by the Medicare contractor for a region. The two live in separate tools and
// return different fields.
var SCOPES = {
  national: {
    tool: "search_national_coverage",
    label: "National (NCD)"
  },
  local: {
    tool: "search_local_coverage",
    label: "Local (LCD)"
  }
}

function scopeKey(value) {
  var normalized = String(value || "").toLowerCase()
  return SCOPES.hasOwnProperty(normalized) ? normalized : "national"
}

function scopeLabel(value) {
  return SCOPES[scopeKey(value)].label
}

function clampResultLimit(value) {
  var parsed = Number(value)
  if (!isFinite(parsed)) return 8
  return Math.max(5, Math.min(12, Math.round(parsed)))
}

// The server speaks JSON-RPC over a single POST. Building the body here rather
// than in QML keeps it under test, and JSON.stringify is what escapes the
// keyword - it is never pasted into a string by hand.
function buildRequestBody(query, scope, resultLimit) {
  var normalized = String(query || "").trim()
  if (normalized === "") return ""

  return JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: SCOPES[scopeKey(scope)].tool,
      arguments: {
        keyword: normalized,
        limit: clampResultLimit(resultLimit),
        count_total: true
      }
    }
  })
}

function resolveUrl(value) {
  var url = String(value || "").trim()
  if (url === "") return ""
  if (url.indexOf("http://") === 0 || url.indexOf("https://") === 0) return url
  return DATABASE_BASE + (url.charAt(0) === "/" ? url : "/" + url)
}

// A contractor arrives as "Palmetto GBA\r\n(MAC - Part A, MAC - Part B)" -
// a name and its contract types split by a carriage return that would render
// as a box in a PlainText label.
function cleanContractor(value) {
  var text = String(value || "").replace(/\s+/g, " ").trim()
  return text === "" || text === "null" ? "" : text
}

function cleanDate(value) {
  var text = String(value || "").trim()
  return text === "" || text === "N/A" || text === "null" ? "" : text
}

// Only national results carry document_type. A local result is identified by
// the letter its display id starts with: L for a determination, A for the
// billing article attached to one.
function documentType(item, scope) {
  var declared = String((item && item.document_type) || "").trim()
  if (declared !== "") return declared

  var displayId = String((item && item.document_display_id) || "").trim().toUpperCase()
  if (displayId.charAt(0) === "L") return "LCD"
  if (displayId.charAt(0) === "A") return "Article"
  return scopeKey(scope) === "local" ? "LCD" : "NCD"
}

function parseDocument(item, scope) {
  var contractor = cleanContractor(item && item.contractor_name_type)
  if (contractor === "") contractor = cleanContractor(item && item.contractor_name)

  return {
    displayId: String((item && item.document_display_id) || "").trim(),
    title: String((item && item.title) || "").replace(/\s+/g, " ").trim() || "Untitled document",
    type: documentType(item, scope),
    contractor: contractor,
    // National documents are grouped into manual chapters; local ones are not.
    chapter: String((item && item.chapter) || "").trim(),
    effective: cleanDate(item && item.effective_date),
    // The two searches spell the same idea differently.
    updated: cleanDate(item && item.updated_on) || cleanDate(item && item.last_updated),
    retired: cleanDate(item && item.retirement_date),
    url: resolveUrl(item && item.url)
  }
}

// The MCP server wraps its answer twice: a JSON-RPC envelope, whose single
// text content block holds the payload as a JSON string. Both layers are
// parsed here, and a JSON-RPC error or a tool-level isError is turned into a
// thrown message rather than an empty result.
function parseSearchResponse(raw, scope) {
  var envelope = JSON.parse(String(raw || ""))
  if (!envelope || typeof envelope !== "object") throw new Error("unexpected response shape")

  if (envelope.error) {
    var message = String((envelope.error.message || "")).trim()
    throw new Error(message === "" ? "the coverage service refused the request" : message)
  }

  var result = envelope.result || {}
  var content = Array.isArray(result.content) ? result.content : []
  var block = null
  for (var index = 0; index < content.length; index++) {
    if (content[index] && content[index].type === "text") {
      block = content[index]
      break
    }
  }
  if (!block) throw new Error("the coverage service returned no content")

  if (result.isError) throw new Error(String(block.text || "").slice(0, 200))

  var payload = JSON.parse(String(block.text || ""))
  var items = Array.isArray(payload.items) ? payload.items : []

  return {
    // total is null when the caller does not ask for it, so the number of
    // rows actually returned is the honest fallback.
    totalCount: payload.total === null || payload.total === undefined ? items.length : Number(payload.total) || 0,
    documents: items.filter(function(item) {
      return item && (item.document_display_id || item.title)
    }).map(function(item) {
      return parseDocument(item, scope)
    })
  }
}

function formatCount(value) {
  var digits = String(Math.max(0, Math.round(Number(value) || 0)))
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}
