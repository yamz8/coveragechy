# Changelog

## 1.0.0 - 2026-08-27

- Add live search of Medicare national (NCD) and local (LCD) coverage
  determinations.
- Route the search through the hosted CMS Coverage MCP server, because
  `api.coverage.cms.gov` is CloudFront-blocked by country.
- Copy a document id to the clipboard with Enter, keeping the panel open for
  the next lookup.
- Show issuing contractor, manual chapter, effective and updated dates, and a
  retirement warning per result.
- Resolve the site-relative URLs national results carry, and leave the
  absolute ones local results carry alone.
- Add `lookup`, `lookupIn`, and `copy` IPC methods so a keybinding or script
  can drive the widget; `lookupIn` picks the scope up front.
- Add native Omarchy components and a theme-aware Nerd Font bar icon.
- Clear the search field along with the rest of the panel state, so repeating
  a query after closing the panel searches instead of silently doing nothing.
- Replay a lookup that arrives while a request is in flight rather than
  dropping it, so the newest query wins.
- Clear query and results on close and show reference-use guidance.
