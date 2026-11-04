local M = {}
local registry = require("snippet_tools.registry")
local session = require("snippet_tools.session")
local config = { auto = true, keymap = {} }
local group, maps, auto_pending = nil, {}, false
local auto_guard = {}
local selections = {}
local actions = {
  expand_trigger = true,
  expand_or_jump = true,
  jump_forward = true,
  jump_backward = true,
  choice_next = true,
  choice_prev = true,
  select_choice = true,
  stop = true,
}
local function load(filetype, reload)
  require("snippet_tools.loader").load(registry.filetypes(filetype), reload)
end

local function termcode(key)
  return vim.api.nvim_replace_termcodes(key, true, false, true)
end
local function feed(key)
  vim.api.nvim_feedkeys(termcode(key), "in", false)
end
local function enabled(ctx)
  return config.enabled ~= false and (type(config.enabled) ~= "function" or config.enabled(ctx))
end
function M.get_selection(buf)
  return selections[buf or vim.api.nvim_get_current_buf()] or ""
end
function M.clear_selection(buf)
  selections[buf or vim.api.nvim_get_current_buf()] = nil
end
function M.cut_selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return false
  end
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), {
    type = mode,
    exclusive = vim.o.selection == "exclusive",
  })
  local text = table.concat(lines, "\n")
  selections[vim.api.nvim_get_current_buf()] = text
  feed('"_c')
  return text
end

function M.context()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  return {
    bufnr = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    row = pos[1] - 1,
    col = pos[2],
    before = line:sub(1, pos[2]),
    line = line,
    tick = vim.api.nvim_buf_get_changedtick(0),
    cache = {},
    selected_text = M.get_selection(),
  }
end

function M.expand(body, options)
  options = vim.tbl_extend("force", {}, options or {})
  options.context = options.context or M.context()
  if options.selected_text == nil then
    options.selected_text = M.get_selection()
  end
  options.context.selected_text = options.selected_text
  options.variables = require("snippet_tools.variables").snapshot(options)
  if type(body) == "string" then
    body = require("snippet_tools.parser").parse(body)
  end
  local expanded = session.expand(require("snippet_tools.nodes").normalize(body), options)
  if expanded then
    M.clear_selection()
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "SnippetToolsExpand", modeline = false, data = { bufnr = vim.api.nvim_get_current_buf() } }
    )
  end
  return expanded
end

function M.expand_definition(entry, match, options)
  options = vim.tbl_extend("force", {}, options or {})
  local ctx = options.context or M.context()
  options.context = ctx
  options.context.match = match
  if match and not options.keep_trigger then
    options.range = { { ctx.row, match.start_col }, { ctx.row, ctx.col } }
  end
  return M.expand(entry.body, options)
end

function M.expand_trigger()
  local ctx = M.context()
  if not enabled(ctx) then
    return false
  end
  load(ctx.filetype)
  local entry, match = registry.find(ctx, false)
  if not entry then
    return false
  end
  return M.expand_definition(entry, match, { context = ctx })
end

function M.expand_or_jump()
  if M.expand_trigger() then
    return true
  end
  return M.jump(1)
end
M.add = registry.add
M.filetype_extend = function(filetype, parents)
  registry.extend(filetype, parents)
  if group then
    load(vim.bo.filetype)
  end
end
M.available = function(ctx)
  ctx = ctx or M.context()
  ctx.selected_text = ctx.selected_text or M.get_selection(ctx.bufnr)
  load(ctx.filetype)
  return registry.available(ctx)
end
M.active = session.active
M.jump = session.jump
M.stop = function()
  session.stop(nil, true)
  return true
end
M.reload = function()
  load(vim.bo.filetype, true)
end
M.update = session.update
M.change_choice = session.change_choice
M.select_choice = session.select_choice
M.choices = session.choices
M.inspect = session.inspect

function M._auto()
  auto_pending = false
  local buf = vim.api.nvim_get_current_buf()
  if not group or not config.auto or vim.api.nvim_get_mode().mode ~= "i" or not vim.bo.modifiable then
    return
  end
  local ctx = M.context()
  if not enabled(ctx) then
    return
  end
  load(ctx.filetype)
  if auto_guard[buf] == ctx.tick then
    return
  end
  local entry, match = registry.find(ctx, true)
  if entry then
    local ok, err = pcall(M.expand_definition, entry, match, { context = ctx })
    auto_guard[buf] = vim.api.nvim_buf_get_changedtick(buf)
    if not ok then
      vim.notify("snippet-tools: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

local function mapping(mode, key)
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if termcode(map.lhs) == termcode(key) then
      return map
    end
  end
end
function M.dispose()
  session.dispose()
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
  for _, name in ipairs({ "SnippetToolsInspect", "SnippetToolsStop", "SnippetToolsReload" }) do
    pcall(vim.api.nvim_del_user_command, name)
  end
  for _, map in ipairs(maps) do
    local current = mapping(map.mode, map.key)
    if current and current.callback == map.callback then
      vim.keymap.del(map.mode, map.key)
      if map.previous then
        vim.fn.mapset(
          map.mode,
          false,
          vim.tbl_extend("keep", map.previous, { abbr = 0, buffer = 0, mode = map.mode, scriptversion = 1 })
        )
      end
    end
  end
  maps, auto_guard, selections = {}, {}, {}
  auto_pending = false
end

function M.setup(options)
  options = options or {}
  assert(vim.fn.has("nvim-0.11") == 1, "snippet-tools requires Neovim 0.11+")
  assert(options.auto == nil or type(options.auto) == "boolean", "snippet-tools: auto must be boolean")
  assert(
    options.enabled == nil or type(options.enabled) == "boolean" or type(options.enabled) == "function",
    "snippet-tools: enabled must be a boolean or function"
  )
  assert(
    options.keymap == nil or options.keymap == false or type(options.keymap) == "table",
    "snippet-tools: invalid keymap"
  )
  assert(options.paths == nil or type(options.paths) == "table", "snippet-tools: paths must be a list")
  for _, path in ipairs(options.paths or {}) do
    assert(type(path) == "string", "snippet-tools: snippet paths must be strings")
  end
  for key, action in pairs(options.keymap or {}) do
    assert(
      type(key) == "string" and actions[action],
      "snippet-tools: invalid keymap action " .. tostring(action)
    )
  end
  M.dispose()
  config = { auto = options.auto ~= false, keymap = options.keymap or {}, enabled = options.enabled }
  group = vim.api.nvim_create_augroup("SnippetTools", { clear = true })
  require("snippet_tools.loader").setup(options.paths)
  load(vim.bo.filetype)
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(args)
      load(vim.bo[args.buf].filetype)
    end,
  })
  vim.api.nvim_create_user_command("SnippetToolsInspect", function()
    vim.print(M.inspect())
  end, {})
  vim.api.nvim_create_user_command("SnippetToolsStop", M.stop, {})
  vim.api.nvim_create_user_command("SnippetToolsReload", M.reload, {})
  local function highlights()
    vim.api.nvim_set_hl(0, "SnippetToolsPlaceholder", { default = true, link = "Visual" })
    vim.api.nvim_set_hl(0, "SnippetToolsActive", { default = true, link = "IncSearch" })
  end
  highlights()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertLeave", "ModeChanged" }, {
    group = group,
    callback = function()
      session.check_cursor()
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function(args)
      session.leave_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      auto_guard[args.buf] = nil
      selections[args.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    callback = function()
      if config.auto and not auto_pending and registry.has_auto(vim.bo.filetype) then
        auto_pending = true
        feed("<Cmd>lua require('snippet_tools')._auto()<CR>")
      end
    end,
  })
  for key, action in pairs(config.keymap) do
    assert(type(M[action]) == "function", "snippet-tools: invalid keymap action " .. tostring(action))
    for _, mode in ipairs({ "i", "s" }) do
      local map = { mode = mode, key = key, previous = mapping(mode, key) }
      map.callback = function()
        local result = M[action](action == "jump_backward" and -1 or nil)
        if result then
          return
        end
        if map.previous and map.previous.callback then
          local value = map.previous.callback()
          if map.previous.expr == 1 and value then
            feed(value)
          end
        elseif map.previous and map.previous.rhs and map.previous.rhs ~= "" then
          local value = map.previous.expr == 1 and vim.api.nvim_eval(map.previous.rhs) or map.previous.rhs
          vim.api.nvim_feedkeys(termcode(value), map.previous.noremap == 0 and "im" or "in", false)
        else
          feed(key)
        end
      end
      vim.keymap.set(mode, key, map.callback, { silent = true, desc = "snippet-tools " .. action })
      maps[#maps + 1] = map
    end
  end
  return M
end
M.jump_forward = function()
  return M.jump(1)
end
M.jump_backward = function()
  return M.jump(-1)
end
M.choice_next = function()
  return M.change_choice(1)
end
M.choice_prev = function()
  return M.change_choice(-1)
end

for name, fn in pairs(require("snippet_tools.nodes")) do
  if name ~= "normalize" then
    M[name] = fn
  end
end
M.t, M.i, M.c, M.f, M.d, M.rep = M.text, M.insert, M.choice, M.func, M.dynamic, M.mirror
return M
