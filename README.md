# snippet-tools.nvim

A standalone, pure Lua snippet engine for Neovim 0.11+. No LuaSnip dependency,
native build, or background process is required.

- LSP-style tabstops, defaults, mirrors, nested placeholders, choices and variables.
- Lua function nodes and dynamic nodes with editable local placeholders.
- Nested expansion with navigation back to the enclosing session.
- Choice alternatives and regenerated dynamic fields retain user input by local index.
- Literal triggers, Lua pattern captures, conditions, priorities and automatic expansion.
- Filetype inheritance, lazy Lua collections, explicit reload and lifecycle diagnostics.
- An optional completion-tools adapter for both user snippets and LSP insertion.

## Setup

Add this directory to your plugin manager or `runtimepath`, then call `setup()`.
Requiring the module alone installs no mappings or automatic expansion handlers.

```lua
local s = require("snippet_tools")
s.setup({
  paths = { vim.fn.stdpath("config") .. "/snippet-tools" },
  keymap = {
    ["<Tab>"] = "expand_or_jump",
    ["<S-Tab>"] = "jump_backward",
    ["<A-j>"] = "choice_next",
    ["<A-k>"] = "choice_prev",
  },
})

s.add("lua", {
  {
    trigger = "fn",
    description = "Function definition",
    body = "function ${1:name}(${2:args})\n\t$0\nend",
  },
})
```

Type `fn`, press Tab, fill the name and arguments, then press Tab to reach the
body. Unhandled keys fall back to their previous global mappings or native keys;
buffer-local mappings retain normal Neovim precedence. `dispose()` restores
previous mappings when they are still owned by this plugin.

Defaults are `{ auto = true, paths = {}, keymap = {} }`. Mappings are opt-in.
Use `auto = false` to disable automatic triggers or `keymap = false` when a
completion engine owns the keys.

`enabled = function(ctx) return ... end` gates automatic and manual trigger
matching per buffer, allowing another engine to own triggers while disabled.
It does not prevent explicit `expand()` calls or navigation of existing sessions.

Use `vim.keymap.set("x", "`", s.cut_selection)` to cut a Visual selection for the
next expansion. `ctx.selected_text` and `TM_SELECTED_TEXT` receive that text.
`get_selection(buf?)` and `clear_selection(buf?)` inspect/reset this buffer-local
selection. Cutting uses the black-hole register and preserves named registers.

## Lua definitions

`body` accepts an LSP-style string or a list of nodes. Helpers have short aliases:

```lua
local s = require("snippet_tools")
s.add("tex", {
  {
    trigger = "widths",
    body = {
      s.i(1, "49"), s.t(" / "),
      s.f(function(args)
        return tostring(98 - (tonumber(args[1]) or 49))
      end, { 1 }),
      s.i(0),
    },
  },
  {
    trigger = "wrap",
    body = {
      s.c(1, {
        { s.t("["), s.i(1, "text"), s.t("]") },
        { s.t("{"), s.i(1, "text"), s.t("}") },
      }),
      s.i(0),
    },
  },
})
```

| Helper | Meaning |
| --- | --- |
| `s.t(text)` / `text(text)` | Literal text |
| `s.i(index, default)` / `insert(...)` | Editable field; `0` is the final stop |
| `s.rep(index)` / `mirror(index)` | Mirror a field in the same scope |
| `s.c(index, alternatives)` / `choice(...)` | Alternatives containing strings or nodes |
| `s.f(fn, dependencies)` / `func(...)` | Computed, read-only text |
| `s.d(index, fn, dependencies)` / `dynamic(...)` | Generated nodes with their own local indices |

`fn(args, ctx)` receives dependency contents as strings and the expansion context.
`ctx.match.captures` contains Lua pattern captures. Function nodes return a string;
dynamic nodes return nodes or a literal string. Keep callbacks deterministic and
declare every field dependency. Callback errors terminate the active session and
report an error, rather than continuing with partially updated state.

Each choice branch and dynamic node has a separate index scope. Its dependencies
refer to the enclosing scope; generated children refer to their own local fields.
LSP nested placeholders share the LSP string's scope. Fields are visited in numeric
order, with branch fields after their container and the root `$0` last. A dynamic
container is skipped in favor of its editable children.

Changing a choice preserves edits to that alternative. Dynamic regeneration keeps
edited fields with the same local index, including fields temporarily removed by
a smaller generated structure. Use stable indices for semantically stable fields.

See [examples/tex.lua](examples/tex.lua) for Beamer columns and
[examples/markdown.lua](examples/markdown.lua) for generated tables.

## Triggers and conditions

```lua
local s = require("snippet_tools")
s.add("lua", {
  { trigger = "mk", body = "[$1]$0", auto = true },
  {
    trigger = "item(%d+) ", pattern = true, auto = true,
    condition = function(ctx, match)
      return match.start_col == 0
    end,
    body = {
      s.d(1, function(_, ctx)
        local result = {}
        for index = 1, math.min(32, tonumber(ctx.match.captures[1])) do
          result[#result + 1] = s.t("- ")
          result[#result + 1] = s.i(index)
          result[#result + 1] = s.t("\n")
        end
        return result
      end),
      s.i(0),
    },
  },
})
```

Definitions support `trigger` (`prefix` is an alias), `body`, `description`,
`preview`, `priority` (default 1000), `word` (default true), `auto`, `hidden`,
`pattern`, `condition(ctx, match)` and `show_condition(ctx)`.

Patterns use Lua patterns, not ECMAScript regex. Triggers match the end of the
text before the cursor. `word = true` requires a keyword boundary before the
match. `condition` gates trigger expansion; `show_condition` gates completion
visibility. The completion adapter also evaluates `condition` for its literal
candidate. `hidden` affects completion visibility, not trigger expansion.

`ctx` contains `bufnr`, `filetype`, zero-based byte `row`/`col`, `before`, `line`,
`tick` and a `cache` table for sharing work among conditions in one query.
Context fields describe the expansion/query snapshot, rather than a live buffer.

Automatic expansion handles typed characters, including input bursts and macros.
Pasted text and arbitrary API edits do not automatically trigger snippets. Each
expansion starts an undo block; one undo restores its trigger. Matching without
an expansion does not create per-character undo blocks.

## Collections and reload

`setup({ paths = { directory } })` lazily loads `directory/<filetype>.lua` and
`directory/all.lua`. Each file returns a list of definitions, using the same
format as `add()`. Other filetypes are not executed.

```lua
-- ~/.config/nvim/snippet-tools/lua.lua
return {
  { trigger = "fn", body = "function ${1:name}()\n\t$0\nend" },
}
```

`s.filetype_extend("markdown", { "tex" })` also loads inherited collections.
Inheritance cycles are deduplicated. `:SnippetToolsReload` replaces collections
for the current filetype and its parents; deleting a collection removes its
definitions on reload. `s.add(ft, definitions, { key = "project" })` replaces a
named collection atomically. Omitting `key` replaces the `default` collection.

## completion-tools.nvim

The adapter lives in this plugin. It uses completion-tools' public provider and
custom snippet engine interfaces; no changes to completion-tools are necessary.

```lua
local s = require("snippet_tools")
s.setup({ keymap = false, paths = { vim.fn.stdpath("config") .. "/snippet-tools" } })

local adapter = require("snippet_tools.integrations.completion_tools")
require("completion_tools").setup(vim.tbl_deep_extend("force", {
  sources = { "lsp", "path", "buffer", "snippets" },
}, adapter.options()))
```

`adapter.options()` provides `providers.snippets`, the default snippet preset and
the `snippets.expand`, `active`, `jump` callbacks. Merge it into your existing
options after any LuaSnip preset. The provider lists literal definitions,
resolves documentation on demand and expands Lua nodes directly. Pattern
definitions remain available through typed/manual triggers.

Both LSP `insertTextMode` variants preserve completion-tools' adjusted indentation.
Mode 1 retains literal tabs; mode 2 expands tabs according to the buffer settings.
Completion's primary edit and expansion share an undo transaction.

## Public API and lifecycle

- `setup(opts)`, `dispose()` manage handlers and opt-in mappings. Definitions persist.
- `add(ft, definitions, opts)`, `filetype_extend(ft, parents)`, `reload()` manage collections.
- `expand(body, opts)` inserts at the cursor; in a selected active field it replaces that field.
- `expand_trigger()` returns whether a manual trigger expanded.
- `expand_or_jump()` tries a manual trigger, then forward navigation.
- `active(direction?)`, `jump(1|-1)`, `stop()`, `update()` manage the current session.
- `choices()` returns the active choice's node alternatives and selected index.
- `change_choice(1|-1)`, `choice_next()`, `choice_prev()` switch alternatives.
- `select_choice()` uses `vim.ui.select`, preserving the session across picker buffers.
- `available(ctx?)`, `context()`, `inspect()` expose candidates and diagnostics.

Expansion options include `range = { {start_row, start_col}, {end_row, end_col} }`
(zero-based byte positions, end exclusive), `indent = false`, `expand_tabs = false`,
`variables`, `selected_text`, `resolve_variable(name)` and `join_undo = true` for
an enclosing edit transaction. `body` is a raw snippet; custom Lua strings are
literal text when supplied through `s.t()` or returned by a dynamic node.

Moving outside the snippet or leaving the buffer ends the session. Reaching root
`$0` ends that session and resumes its parent. Undo ends a session when it moves
behind its tracked undo sequence; redo restores text without recreating sessions.
Replacing a whole parent field discards its old nested fields. Finished snippets
are not retained in a history jump list. `stop()` preserves buffer text.
While a field is selected, window folding is temporarily suspended so an
asynchronous fold cannot widen the replacement range. The previous folding
setting is restored when selection ends or the session stops.

`:SnippetToolsInspect`, `:SnippetToolsStop`, `:SnippetToolsReload` and
`:checkhealth snippet_tools` are available after setup.
Highlights are `SnippetToolsPlaceholder` and `SnippetToolsActive`.
The `User` events `SnippetToolsExpand` and `SnippetToolsEnter` expose expansion
and field-entry transitions for integrations; their data includes `bufnr`.

## Compatibility boundaries

Supported string syntax includes `$1`, `${1:default}`, `${1|one,two|}`, `$0`,
repeated fields, nesting, escaping, `$VARIABLE` and `${VARIABLE:default}`.
Common `TM_*` file/selection variables and `CURRENT_*` date/time variables are
provided; custom variables can be supplied at expansion time. An unresolved
variable without a default becomes an editable field containing its name.

ECMAScript transformations (`${1/regex/format/options}`) are rejected explicitly;
use Lua function nodes for transformations. This is not a complete LSP snippet
implementation. LuaSnip's Lua DSL, VSCode package discovery, SnipMate files and
LuaSnip-specific history/restore-node APIs are not supported. Existing LuaSnip
collections need migration to this plugin's definitions.

## Development

```sh
sh tests/run.sh
COMPLETION_TOOLS_PATH=../completion-tools.nvim sh tests/run.sh
NVIM=/path/to/nvim sh tests/run.sh
sh tests/bench.sh
stylua --check lua tests examples
```

Tests exercise a separate attached UI and real PTY, including intermediate
selection/rendered states, UTF-8, input bursts, undo/redo, nesting, dynamic
regeneration and optional integration with the actual sibling completion checkout.
`SNIPPET_TUI_TRACE=/tmp/snippet-frames.json` records PTY state snapshots.
Benchmarks report local parse/render/matching costs; they are not an end-to-end
latency comparison against another engine.
