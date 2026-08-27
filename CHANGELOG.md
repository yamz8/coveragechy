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
- Add `lookup` and `copy` IPC methods so a keybinding or script can drive the
  widget; `lookup` takes an optional scope as its second argument.
- Add native Omarchy components and a theme-aware Nerd Font bar icon.
- Clear query and results on close and show reference-use guidance.
