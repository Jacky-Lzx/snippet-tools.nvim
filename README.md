# snippet-tools.nvim

A standalone, pure Lua snippet engine for Neovim 0.11+. No LuaSnip dependency,
native build, or background process is required.

- LSP-style tabstops, defaults, mirrors, nested placeholders, choices and variables.
- Lua function nodes and dynamic nodes with editable local placeholders.
- Readable `fmt` / `fmta` templates with positional and named node slots.
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

## Readable templates

`s.fmt(template, fields, opts?)` uses `{}` slots; `s.fmta(...)` uses `<>`, which
keeps LaTeX braces literal. Both return ordinary node lists and also work inside
choices, insert defaults and dynamic callbacks.

```lua
local s = require("snippet_tools")

-- Positional slots: {}, {2}, {1} refer to entries in the fields table.
local fn = s.fmt([[
  function {}({})
    {}
  end
]], { s.i(1, "name"), s.i(2), s.i(0) })

-- Named slots make the template and its fields easier to match.
local environment = s.fmta([[
  \begin{<env>}
    <body>
  \end{<env>}
]], { env = s.i(1, "table"), body = s.i(0) })

s.add("tex", { { trigger = "begin", body = environment } })
```

Fields can be nodes, literal strings or node lists. A single node can be passed
directly instead of a fields table. Slot numbers index this table, starting at
one; they do not change node indices. Named slots leave the automatic slot
counter unchanged; an explicit number resets it, so `{} {3} {}` selects entries
1, 3 and 4. Reusing an indexed field uses the engine's normal mirror behavior,
without adding another navigation stop. No LuaSnip `repeat_duplicates` option is
needed. Nodes and field tables remain reusable and are not modified by formatting.

Double either delimiter to insert it literally: `{{` / `}}` with `fmt`, or
`<<` / `>>` with `fmta`. Delimiters inside inserted fields are not parsed.
Template text and string fields are literal text, including `$1`, backslashes
and braces; LSP snippet syntax belongs in `expand(string)` or node definitions.

Options apply to the template before inserting fields:

| Option | Default | Behavior |
| --- | --- | --- |
| `delimiters` | `"{}"` / `"<>"` | Two distinct ASCII delimiter characters |
| `trim_empty` | `true` | Remove surrounding whitespace-only lines |
| `dedent` | `true` | Remove common leading whitespace from nonblank lines |
| `indent_string` | `""` | Convert repeated indentation units at line starts into tabs, after dedenting |
| `strict` | `true` | Reject fields that the template does not use |

Missing fields and malformed delimiters always raise an error. Set
`strict = false` to permit unused fields, or disable `dedent` / `trim_empty` to
preserve the template's layout exactly. Tabs then follow the engine's normal
buffer indentation settings. The module is loaded on first use; it is also
available as `require("snippet_tools.fmt").fmt` / `.fmta`.

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

### Project sources

```lua
require("snippet_tools.bootstrap").setup({
  paths = { "~/.config/nvim/snippet-tools" },
  project = {
    root = "/path/to/project", -- supplied by the host's trusted project context
    paths = { ".nvim/snippets" }, -- relative to root; this is also the default
  },
})
```

Project files use the same `all.lua` and `<filetype>.lua` format as global
collections. Only files applicable to the requested buffer and its filetype
inheritance are loaded. `project = false` disables the project source. Paths
are canonicalized, including symlinks and newly named files; switching cwd does
not change the source root. Project definitions are unavailable in unnamed,
special, or outside-project buffers, even when another project buffer loaded them.

Project Lua is read with `vim.secure.read()`. New or changed files use Neovim's
file-content trust flow: view the file, inspect it, run `:trust`, then return to
the project buffer and run `:SnippetToolsReload`. Untrusted files are skipped
and are not repeatedly prompted while typing. Revocation or changed untrusted
contents remove the old collection on reload. Global paths remain trusted user
configuration and do not prompt.

Explicit priority wins; equal-priority project definitions precede global ones.
Conditions still apply, so a rejected project match falls back to global
definitions. The completion adapter deduplicates eligible triggers in that order.
Named manual collections remain independent of directory-loaded collections.

`:SnippetToolsReload` reloads the current buffer's applicable global/project files,
parents and `all.lua`, discovers newly created files, and removes deleted files.
Compilation or validation errors retain the previous good collection and report
the failing path. Reload never replaces an active editing session or its fields.
Setup removes sources registered by the previous loader, while preserving manually
added collections. Sources and their negative lookup results are cached; matching
does not scan directories or stat files on each keypress.

`:SnippetToolsInspect` adds `sources` (path, root, active scope, trust, load status,
definition count and error) and `definitions` (origin, priority and current matching
winner) to the existing session information. Lua `add()` accepts optional `root`
and `source` metadata; `remove(ft, key)` removes a named collection.

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

Moving outside the snippet or leaving the buffer ends the session.
The range check includes columns on the same line and unwinds every nested
session the cursor has left. In Insert mode the end boundary remains available
for typing; in Normal mode the first character after the snippet is outside it.
Navigation also checks the cursor before acting, even before cursor events run.
Reaching root `$0` ends that session and resumes its parent. Undo ends a session
when it moves behind its tracked undo sequence; redo restores text without
recreating sessions.
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

## Node display

`setup({ ext_opts = ... })` configures decorations by node type and state.
Types are `insert`, `exit`, `choice`, `dynamic`, `mirror` and `["function"]`.
`active` is the current node of the innermost session; all other live nodes are
`passive`, including the current field of a suspended parent session.

```lua
require("snippet_tools").setup({
  ext_opts = {
    insert = {
      passive = {
        virt_text = { { "●", "Comment" } },
        virt_text_pos = "inline",
        sign_text = "●",
        sign_hl_group = "Comment",
      },
      active = {
        virt_text = { { "●", "Identifier" } },
        sign_hl_group = "Identifier",
      },
    },
    choice = {
      passive = { virt_text = { { "◆", "Comment" } }, sign_text = "◆", sign_hl_group = "Comment" },
      active = { virt_text = { { "◆", "Type" } }, sign_hl_group = "Type" },
    },
    exit = {
      passive = { virt_text = { { "■", "Comment" } }, sign_text = "■" },
      active = { virt_text = { { "■", "Identifier" } } },
    },
  },
})
```

Active options inherit configured passive options, with active overrides applied
last. Nested tables such as `virt_text` replace the whole value. Use
`virt_text = {}` to remove inherited virtual text, or `false` to remove an
inherited display option (for example `hl_group = false` or `sign_text = false`).
`hl_eol` and `virt_text_hide` retain their normal boolean meanings.
`exit` styles index-zero fields (`$0`), including implicit final stops and local
zero fields inside choice/dynamic branches. It inherits the configured `insert`
styles before applying its own overrides. Mirrors retain the `mirror` style.

Supported extmark options are `hl_group`, `hl_eol`, `hl_mode`, `virt_text`,
`virt_text_pos`, `virt_text_win_col`, `virt_text_hide`, `priority`, `sign_text`,
`sign_hl_group`, `number_hl_group`, `line_hl_group` and `cursorline_hl_group`.
Signs appear when the window's `signcolumn` permits them. Virtual text defaults
to Neovim's end-of-line placement; `inline` also identifies empty fields at their
exact position. Decorations do not modify buffer text and disappear when their
node or session is removed. Root `$0` uses the exit style until the session ends.

Without `ext_opts`, existing highlights remain unchanged and no icons or signs
are added. Default priorities are 130 for active nodes and 120 for passive nodes.
End-of-line virtual text uses separate marks with stable priorities of 120–125
so its order follows the fields' buffer positions when the active node changes; range
highlights and signs keep their configured priorities.
Each buffer line shows at most five end-of-line node markers. Additional nodes
are represented by `...`, which uses the active hidden node's marker color when
one of those nodes is current; otherwise it uses the first hidden marker's color.
Exactly five markers need no ellipsis. Inline markers and signs are not truncated.
Range/gravity/lifecycle options remain owned by the engine and cannot be set
through `ext_opts`. This API uses string node types and two states; it does not
accept LuaSnip's numeric types, per-node overrides or visited/history states.

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
`tests/bench.sh` reports local parse/render/matching costs. For the LuaSnip
comparison, see [bench/README.md](bench/README.md): fresh module loads, collection
scaling, real PTY input in isolation and in the user configuration, and lifecycle
memory checkpoints. Raw samples and correctness failures are recorded.

### Plugin-owned first-input initialization

Call `require("snippet_tools.bootstrap").setup(opts)` to register first-input
initialization without loading the snippet engine. The plugin handles InsertEnter
and its own SnippetTools commands. `bootstrap.ensure()` explicitly initializes
once and returns the engine; the `User SnippetToolsReady` event lets completion
integrations refresh their keymaps. Optional `extends` maps filetypes to parent
filetypes before setup. Direct `snippet_tools.setup(opts)` remains eager.
