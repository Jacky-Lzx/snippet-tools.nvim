local api = vim.api
local configured = vim.env.SNIPPET_BENCH_TRACK == "configured"
local engine = assert(vim.env.SNIPPET_BENCH_ENGINE)
local fixtures = dofile(vim.env.SNIPPET_BENCH_ROOT .. "/bench/fixtures.lua")
local B = { errors = {}, fixtures = {}, sequence = 0 }
_G.SnippetBench = B
local clock = vim.uv.hrtime
local prior_notify = vim.notify
vim.notify = function(message, level, opts)
  if level == vim.log.levels.ERROR then
    B.errors[#B.errors + 1] = tostring(message)
  end
  if configured then
    return prior_notify(message, level, opts)
  end
end
local function native()
  return require("snippet_tools")
end
local function ls()
  return require("luasnip")
end
local function stop()
  if package.loaded.snippet_tools then
    native().stop()
  end
  if package.loaded.luasnip then
    for _ = 1, 64 do
      if not ls().session.current_nodes[api.nvim_get_current_buf()] then
        break
      end
      ls().unlink_current()
    end
  end
end
local function mode()
  return api.nvim_get_mode().mode
end
local function selected()
  if mode() ~= "s" then
    return ""
  end
  return table.concat(
    vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), {
      type = "v",
      exclusive = vim.o.selection == "exclusive",
    }),
    "\n"
  )
end
local F5, F6, F7 = "\27[15~", "\27[17~", "\27[18~"
local function stage(keys, lines, m, label)
  return { keys = keys, lines = lines, mode = m, menu = label }
end
local cases
if configured then
  cases = {
    {
      name = "plain_input",
      pre = { stage("i", { "" }, "i") },
      action = "z",
      lines = { "z" },
      mode = "i",
      sources = false,
    },
    {
      name = "bold_accept",
      pre = { stage("ibold", { "bold" }, "i", "bold") },
      action = "\t",
      lines = { "**BOLD**" },
      mode = "s",
      selection = "BOLD",
    },
    {
      name = "link_jump",
      pre = { stage("ilink", { "link" }, "i", "link"), stage("\t", { "[NAME](LINK)" }, "s") },
      action = "\27l",
      lines = { "[NAME](LINK)" },
      mode = "s",
      selection = "LINK",
    },
    {
      name = "figure_update_jump",
      pre = {
        stage("ifigure", { "figure" }, "i", "figure"),
        stage("\t", { "![](./Figures_markdown/)" }, "i"),
      },
      action = "my_figure.png\27l",
      lines = { "![my figure](./Figures_markdown/my_figure.png)" },
      mode = "s",
      selection = "my figure",
    },
    {
      name = "table_2x2",
      pre = { stage("itable2x2", { "table2x2" }, "i") },
      action = " ",
      lines = fixtures.table_text(2, 2),
      mode = "s",
      selection = "1",
    },
    {
      name = "table_10x10",
      pre = { stage("itable10x10", { "table10x10" }, "i") },
      action = " ",
      lines = fixtures.table_text(10, 10),
      mode = "s",
      selection = "1",
    },
    {
      name = "choice_toggle",
      pre = { stage("itodo", { "todo" }, "i", "todo"), stage("\t", { "- [ ]" }, "s") },
      action = "\27j",
      lines = { "- [x]" },
      mode = engine == "luasnip" and "i" or "s",
      selection = engine ~= "luasnip" and "[x]" or nil,
      semantics = "Same checked checkbox; LuaSnip retains Insert mode, snippet-tools selects the choice text",
    },
    {
      name = "undo_field_edit",
      pre = {
        stage("ibold", { "bold" }, "i", "bold"),
        stage("\t", { "**BOLD**" }, "s"),
        stage("x", { "**x**" }, "i"),
      },
      action = "\28\14u", -- Ctrl-\\ Ctrl-N, then u; no terminal Alt-u ambiguity.
      lines = { "**BOLD**" },
      mode = "n",
      normalize_undo_key = "x",
    },
  }
else
  cases = {
    { name = "plain_input", pre = { stage("i", { "" }, "i") }, action = "z", lines = { "z" }, mode = "i" },
    {
      name = "simple_expand",
      kind = "simple",
      pre = { stage("i", { "" }, "i") },
      action = F5,
      lines = { "<field>" },
      mode = "s",
      selection = "field",
    },
    {
      name = "table_2x2",
      kind = "table",
      count = 2,
      pre = { stage("i", { "" }, "i") },
      action = F5,
      lines = fixtures.table_text(2, 2),
      mode = "s",
      selection = "1",
    },
    {
      name = "table_10x10",
      kind = "table",
      count = 10,
      pre = { stage("i", { "" }, "i") },
      action = F5,
      lines = fixtures.table_text(10, 10),
      mode = "s",
      selection = "1",
    },
    {
      name = "jump_final",
      kind = "simple",
      pre = { stage("i" .. F5, { "<field>" }, "s") },
      action = F7,
      lines = { "<field>" },
      mode = "i",
    },
    {
      name = "choice_toggle",
      kind = "choice",
      pre = { stage("i" .. F5, { "red" }, "s") },
      action = F6,
      lines = { "blue" },
      mode = "s",
      selection = "blue",
    },
    {
      name = "mirrors_10",
      kind = "mirror",
      count = 10,
      pre = { stage("i" .. F5, { "field" .. string.rep("/field", 10) }, "s") },
      action = "x",
      lines = { "x" .. string.rep("/x", 10) },
      mode = "i",
    },
    {
      name = "mirrors_100",
      kind = "mirror",
      count = 100,
      pre = { stage("i" .. F5, { "field" .. string.rep("/field", 100) }, "s") },
      action = "x",
      lines = { "x" .. string.rep("/x", 100) },
      mode = "i",
    },
    {
      name = "session_cycle",
      kind = "simple",
      pre = { stage("i", { "" }, "i") },
      action = F5 .. F7,
      lines = { "<field>" },
      mode = "i",
      memory = true,
    },
  }
  for _, case in ipairs(cases) do
    if case.kind then
      B.fixtures[case.name] =
        fixtures[engine == "snippet-tools" and "native" or "luasnip"](case.kind, case.count)
    end
  end
end
B.cases = cases
if configured and engine == "luasnip" then
  for _, case in ipairs(cases) do
    if case.name == "choice_toggle" then
      case.pre[2].lines = { "- [ ] " }
      case.lines = { "- [x] " }
    end
  end
end
local by_name = {}
for _, case in ipairs(cases) do
  by_name[case.name] = case
end
function B.matches(expected)
  if
    mode() ~= expected.mode or not vim.deep_equal(api.nvim_buf_get_lines(0, 0, -1, false), expected.lines)
  then
    return false
  end
  if expected.selection and selected() ~= expected.selection then
    return false
  end
  if package.loaded.snippet_tools and native().inspect().pending then
    return false
  end
  if expected.menu then
    local cmp = package.loaded.completion_tools
    local item = cmp and cmp.get_selected_item()
    if not cmp or not cmp._can("accept") or not item or item.label ~= expected.menu then
      return false
    end
  end
  return true
end
function B.prepare(name)
  stop()
  if package.loaded.completion_tools then
    require("completion_tools").hide()
  end
  assert(mode() == "n", "prepare requires Normal mode")
  local case = assert(by_name[name])
  B.case, B.started, B.checking = case, nil, false
  api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  api.nvim_win_set_cursor(0, { 1, 0 })
  vim.bo.autoindent = false
  vim.bo.indentexpr = ""
  vim.bo.expandtab = true
  vim.bo.shiftwidth = 2
  if configured then
    vim.b.completion_tools_sources = case.sources == false and {} or { "snippets" }
  else
    vim.wo.foldenable = false
  end
  B.errors = {}
  B.deadline = nil
  return case
end
function B.arm(id, channel)
  B.id, B.channel, B.started, B.checking = id, channel, nil, false
  assert(#B.errors == 0, table.concat(B.errors, "\n"))
end
function B.start()
  B.started = clock()
end
local function check()
  if not B.checking then
    return
  end
  local now = clock()
  if B.matches(B.case) or now > B.deadline or #B.errors > 0 then
    B.checking = false
    local valid = B.matches(B.case) and #B.errors == 0
    local result = { id = B.id, valid = valid, state_ms = (now - B.started) / 1e6 }
    if not valid then
      result.diagnostic = {
        mode = mode(),
        lines = api.nvim_buf_get_lines(0, 0, -1, false),
        selection = selected(),
        errors = B.errors,
      }
    end
    vim.rpcnotify(B.channel, "snippet_bench_done", result)
    -- Request a frame after validation. Python timestamps the UI flush, not a timer/file poll.
    vim.cmd("redraw!")
  else
    vim.defer_fn(check, 0)
  end
end
function B.finish()
  assert(B.started, "missing benchmark start key")
  B.deadline = clock() + 2e9
  B.checking = true
  vim.schedule(check)
end
function B.snapshot()
  collectgarbage("collect")
  collectgarbage("collect")
  local marks = 0
  for _, id in pairs(api.nvim_get_namespaces()) do
    local ok, items = pcall(api.nvim_buf_get_extmarks, 0, id, 0, -1, {})
    if ok then
      marks = marks + #items
    end
  end
  return {
    lua_heap_kib = collectgarbage("count"),
    extmarks = marks,
    autocmds = #api.nvim_get_autocmds({}),
    buffers = #api.nvim_list_bufs(),
  }
end
vim.keymap.set({ "i", "s" }, "<F5>", function()
  if engine == "snippet-tools" then
    native().expand(B.fixtures[B.case.name])
  else
    ls().snip_expand(B.fixtures[B.case.name])
  end
end)
vim.keymap.set({ "i", "s" }, "<F6>", function()
  if engine == "snippet-tools" then
    native().change_choice(1)
  else
    ls().change_choice(1)
  end
end)
vim.keymap.set({ "i", "s" }, "<F7>", function()
  if engine == "snippet-tools" then
    native().jump(1)
  else
    ls().jump(1)
  end
end)
vim.keymap.set({ "i", "s", "n" }, "<F10>", B.start)
vim.keymap.set({ "i", "s", "n" }, "<F12>", B.finish)
if configured then
  local buf = api.nvim_get_current_buf()
  B.engine_policy = {
    configured_route = require("integrations.snippets").engine(),
    both_engines_loaded = package.loaded.snippet_tools ~= nil and package.loaded.luasnip ~= nil,
    filetype = vim.bo[buf].filetype,
  }
else
  B.engine_policy = { both_engines_loaded = false, normalized_decorations = true, normalized_history = true }
end
