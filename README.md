# coveragechy

`coveragechy` is a native Omarchy bar plugin for searching the **Medicare
Coverage Database** — the national coverage determinations (NCDs) CMS sets for
the whole country, and the local ones (LCDs) each Medicare contractor issues
for its region.

Each result shows the document id, its title, the issuing contractor or manual
chapter, and its effective and updated dates. Pressing Enter copies the
document id to the clipboard and leaves the panel open.

## Why this one goes through an MCP server

The obvious route, `api.coverage.cms.gov`, is served through a CloudFront
distribution that **blocks whole countries outright**. From a machine outside
the permitted region every request answers:

```
403 — The Amazon CloudFront distribution is configured to block access
      from your country.
```

There is no header or parameter that changes that, and the other CMS routes
carry no coverage data: `cms.gov/medicare-coverage-database/api/v1/*` redirects
to a 404 page, and `data.cms.gov` has no LCD or NCD dataset among its 159.

So the plugin queries the **hosted CMS Coverage MCP server** published by
[anthropics/healthcare](https://github.com/anthropics/healthcare) instead. It
reaches the CMS API from its own network and needs no key, no account, and no
session — a single JSON-RPC `POST`, stateless. Sibling plugins like `npichy`
talk to CMS directly because `npiregistry.cms.hhs.gov` is a different host and
is not blocked.

## Scope

| Scope | What it searches |
|---|---|
| **National** (default) | NCDs — coverage CMS sets nationwide, grouped by manual chapter |
| **Local** | LCDs — coverage a Medicare Administrative Contractor sets for its region |

The two are separate tools on the server and return different fields, so the
scope control switches between them rather than merging them.

## Keywords are matched close to literally

A long phrase finds nothing where its head word finds plenty — `continuous
glucose monitor` returns **0** national matches, while `glucose` returns
**3**. Prefer a single distinctive word.

## Keys

| Key | Action |
|---|---|
| `Enter` | Copy the selected document id (runs the search first if the query changed) |
| `Ctrl+Enter` | Open the determination on cms.gov |
| `↑` `↓` | Move the selection |
| `Esc` | Close the panel |

Left-clicking a result copies it; right-clicking opens it. Right-clicking the
bar icon opens the coverage database search page.

## Scripting

```bash
omarchy-shell yamz8.coveragechy lookup "acupuncture"       # opens the panel and searches
omarchy-shell yamz8.coveragechy lookupIn "oxygen" local     # ... in the local scope
omarchy-shell yamz8.coveragechy copy                   # copies the selected id, echoes it
omarchy-shell yamz8.coveragechy toggle                 # open / close
```

`lookupIn` takes the scope (`national` or `local`) as a second argument;
Quickshell requires every declared IPC parameter, so the one-argument form is
its own method rather than an optional argument. Both return `ok`, or `empty
query` when handed nothing. `copy` returns the
id it put on the clipboard, or `no selection`.

## Omarchy integration

The widget uses Omarchy's native `Panel`, `BarIconButton`, `KeyboardPanel`,
`PanelHero`, `ButtonGroup`, and theme tokens. Its shield mark is a monochrome
Nerd Font glyph, so it follows the active bar foreground color and font instead
of falling back to a colored emoji.

Runtime dependencies are `curl`, `wl-copy`, and network access to
`hcls.mcp.claude.com`. No API key is needed.

## Privacy

The plugin writes no cache, history, or analytics, and clears the query and
results whenever the panel closes. Keywords are sent to the hosted MCP server
and on to CMS, so do not enter patient names, record numbers, or other personal
identifiers.

This is a policy reference aid. A coverage determination is not a benefit
decision for any individual.

## Settings

| Setting | Values | Default |
|---|---|---|
| Coverage scope searched first | `national`, `local` | `national` |
| Results shown | 5–12 | 8 |

## Install

```bash
omarchy plugin add https://github.com/yamz8/coveragechy.git --enable
```

`omarchy plugin add` clones the repository, validates the manifest, and installs
it as `yamz8.coveragechy`. Update later with `omarchy plugin update yamz8.coveragechy`.

## Install from a local checkout

```bash
cp -R ./coveragechy ~/.config/omarchy/plugins/yamz8.coveragechy
omarchy plugin validate ~/.config/omarchy/plugins/yamz8.coveragechy
omarchy plugin enable yamz8.coveragechy
```

Plugin files hot reload. If the widget does not appear immediately, run:

```bash
omarchy-shell shell rescanPlugins
```

## Remove

```bash
omarchy plugin disable yamz8.coveragechy
omarchy plugin remove yamz8.coveragechy
```

Removing the plugin takes the widget out of the bar and deletes
`~/.config/omarchy/plugins/yamz8.coveragechy`. The plugin writes nothing outside that
folder and never modifies your Omarchy configuration, so nothing is left behind.

## Use

- Left-click the shield icon to open the coverage finder.
- Right-click it to open the Medicare Coverage Database search page.
- Press `Enter` to search, then `Enter` again to copy the selected document id.
- Press `Ctrl+Enter` to open the determination on cms.gov.
- Press `Up`/`Down` to choose a result, `Esc` to close, or `Tab` to switch
  bar panels.

The bar editor exposes every setting below. For example:

```bash
omarchy bar set yamz8.coveragechy defaultScope local
omarchy bar set yamz8.coveragechy resultLimit 10
```

## Validate

```bash
omarchy plugin validate .
node --test tests/coverage.test.mjs
/usr/lib/qt6/bin/qmlformat Coveragechy.qml >/dev/null
```

## Data source

- [Medicare Coverage Database](https://www.cms.gov/medicare-coverage-database/search.aspx)
- [CMS Coverage MCP server](https://github.com/anthropics/healthcare), hosted at
  `https://hcls.mcp.claude.com/cms_coverage/mcp`

Coverage determinations are published by the U.S. Centers for Medicare &
Medicaid Services. The plugin reads them through the hosted MCP server
above rather than `api.coverage.cms.gov`, which is CloudFront-blocked by
country. No API key or account is required.

## License

MIT
