local M = {}
local stores, extensions, serial = {}, {}, 0

local function before(a, b)
  return a.priority == b.priority and a.id < b.id or a.priority > b.priority
end

function M.add(filetype, definitions, options)
  options = options or {}
  assert(type(filetype) == "string" and filetype ~= "", "snippet-tools: invalid filetype")
  local entries = {}
  -- Validate the whole collection before replacing an existing namespace.
  for _, spec in ipairs(definitions) do
    local trigger = spec.trigger or spec.prefix
    assert(type(trigger) == "string" and trigger ~= "", "snippet-tools: trigger must not be empty")
    assert(spec.pattern == nil or type(spec.pattern) == "boolean", "snippet-tools: pattern must be boolean")
    assert(spec.condition == nil or type(spec.condition) == "function", "snippet-tools: invalid condition")
    assert(
      spec.show_condition == nil or type(spec.show_condition) == "function",
      "snippet-tools: invalid show_condition"
    )
    if spec.pattern then
      assert(pcall(string.find, "", trigger .. "$"), "snippet-tools: invalid Lua pattern")
    end
    local body = type(spec.body) == "string" and require("snippet_tools.parser").parse(spec.body)
      or require("snippet_tools.nodes").normalize(spec.body)
    serial = serial + 1
    entries[#entries + 1] = {
      id = serial,
      trigger = trigger,
      body = vim.deepcopy(body),
      description = spec.description,
      preview = spec.preview or (type(spec.body) == "string" and spec.body),
      pattern = spec.pattern or false,
      auto = spec.auto or false,
      hidden = spec.hidden or false,
      word = spec.word ~= false,
      priority = spec.priority or 1000,
      condition = spec.condition,
      show_condition = spec.show_condition,
    }
    assert(type(entries[#entries].priority) == "number", "snippet-tools: invalid priority")
  end
  stores[filetype] = stores[filetype] or {}
  stores[filetype][options.key or "default"] = entries
end

function M.extend(filetype, parents)
  assert(type(filetype) == "string" and type(parents) == "table", "snippet-tools: invalid filetype extension")
  for _, parent in ipairs(parents) do
    assert(type(parent) == "string", "snippet-tools: extension must be a filetype")
  end
  extensions[filetype] = vim.deepcopy(parents)
end

local function entries(filetype)
  local result, visited = {}, {}
  local function visit(ft)
    if visited[ft] then
      return
    end
    visited[ft] = true
    for _, items in pairs(stores[ft] or {}) do
      vim.list_extend(result, items)
    end
    for _, parent in ipairs(extensions[ft] or {}) do
      visit(parent)
    end
  end
  visit(filetype)
  visit("all")
  table.sort(result, before)
  return result
end

-- Collections are indexed once per registry revision, not once per character.
local indexed = {}
local add, extend = M.add, M.extend
function M.add(...)
  add(...)
  indexed = {}
end
function M.extend(...)
  extend(...)
  indexed = {}
end
local function get_index(filetype)
  if indexed[filetype] then
    return indexed[filetype]
  end
  local index = {
    all = entries(filetype),
    suffix = { [true] = {}, [false] = {} },
    patterns = { [true] = {}, [false] = {} },
    has_auto = false,
  }
  for _, entry in ipairs(index.all) do
    if entry.pattern then
      table.insert(index.patterns[entry.auto], entry)
    else
      local last = entry.trigger:sub(-1)
      index.suffix[entry.auto][last] = index.suffix[entry.auto][last] or {}
      table.insert(index.suffix[entry.auto][last], entry)
    end
    index.has_auto = index.has_auto or entry.auto
  end
  indexed[filetype] = index
  return index
end

function M.match(entry, ctx)
  local start, captures
  if entry.pattern then
    local matched = { ctx.before:find(entry.trigger .. "$") }
    start = matched[1]
    captures = {}
    for i = 3, #matched do
      captures[#captures + 1] = matched[i]
    end
  elseif ctx.before:sub(-#entry.trigger) == entry.trigger then
    start, captures = #ctx.before - #entry.trigger + 1, {}
  end
  if not start then
    return
  end
  if entry.word and start > 1 and vim.fn.match(ctx.before:sub(1, start - 1), [[\k$]]) >= 0 then
    return
  end
  local match = { start_col = start - 1, captures = captures, trigger = ctx.before:sub(start) }
  if not entry.condition or entry.condition(ctx, match) then
    return match
  end
end

function M.find(ctx, auto)
  local index = get_index(ctx.filetype)
  local literal, patterns = index.suffix[auto][ctx.before:sub(-1)] or {}, index.patterns[auto]
  local i, j = 1, 1
  while literal[i] or patterns[j] do
    local entry
    if literal[i] and (not patterns[j] or before(literal[i], patterns[j])) then
      entry, i = literal[i], i + 1
    else
      entry, j = patterns[j], j + 1
    end
    local match = M.match(entry, ctx)
    if match then
      return entry, match
    end
  end
end

function M.available(ctx)
  local result = {}
  for _, entry in ipairs(get_index(ctx.filetype).all) do
    if not entry.hidden and not entry.pattern and (not entry.show_condition or entry.show_condition(ctx)) then
      result[#result + 1] = entry
    end
  end
  return result
end

function M.has_auto(filetype)
  return get_index(filetype).has_auto
end

function M.filetypes(filetype)
  local result, visited = {}, {}
  local function visit(ft)
    if ft == "" or visited[ft] then
      return
    end
    visited[ft] = true
    result[#result + 1] = ft
    for _, parent in ipairs(extensions[ft] or {}) do
      visit(parent)
    end
  end
  visit(filetype)
  visit("all")
  return result
end

function M.clear()
  stores, extensions, indexed = {}, {}, {}
end

return M
