local nodes = require("snippet_tools.nodes")
local M = {}
local option_types = {
  delimiters = "string",
  strict = "boolean",
  trim_empty = "boolean",
  dedent = "boolean",
  indent_string = "string",
}

local function check(ok, message)
  assert(ok, "snippet-tools: fmt " .. message)
end

local function multiline(template, opts)
  local lines = vim.split(template, "\n", { plain = true })
  if opts.trim_empty ~= false then
    while #lines > 0 and lines[1]:match("^%s*$") do
      table.remove(lines, 1)
    end
    while #lines > 0 and lines[#lines]:match("^%s*$") do
      table.remove(lines)
    end
  end
  if opts.dedent ~= false then
    local indent = math.huge
    for _, line in ipairs(lines) do
      if line:find("%S") then
        indent = math.min(indent, #line:match("^[ \t]*"))
      end
    end
    if indent < math.huge then
      for i, line in ipairs(lines) do
        lines[i] = line:sub(math.min(indent, #line) + 1)
      end
    end
  end
  local unit = opts.indent_string or ""
  if #unit > 0 then
    for i, line in ipairs(lines) do
      local count, offset = 0, 1
      while line:sub(offset, offset + #unit - 1) == unit do
        count, offset = count + 1, offset + #unit
      end
      lines[i] = string.rep("\t", count) .. line:sub(offset)
    end
  end
  return table.concat(lines, "\n")
end

local function format(template, args, opts, delimiters)
  check(type(template) == "string", "template must be a string")
  check(opts == nil or type(opts) == "table", "options must be a table")
  opts = opts or {}
  for key, value in pairs(opts) do
    check(option_types[key] ~= nil, "unknown option " .. tostring(key))
    check(type(value) == option_types[key], "invalid option " .. tostring(key))
  end
  delimiters = opts.delimiters or delimiters
  check(
    #delimiters == 2
      and delimiters:byte(1) < 128
      and delimiters:byte(2) < 128
      and delimiters:sub(1, 1) ~= delimiters:sub(2, 2),
    "delimiters must be two distinct ASCII characters"
  )
  check(not (opts.indent_string or ""):find("[\r\n]"), "indent_string must not contain a newline")
  check(args == nil or type(args) == "table", "arguments must be a node or table")
  args = args or {}
  if
    type(args.kind) == "string"
    and (
      type(args.index) == "number"
      or type(args.text) == "string"
      or type(args.fn) == "function"
      or (args.kind == "variable" and type(args.name) == "string")
    )
  then
    args = { args }
  end
  template = multiline(template, opts)
  local left, right = delimiters:sub(1, 1), delimiters:sub(2, 2)
  local pattern = "[" .. vim.pesc(left) .. vim.pesc(right) .. "]"
  local result, text, used = {}, {}, {}
  local offset, index = 1, 0
  local function flush()
    if #text > 0 then
      result[#result + 1] = nodes.text(table.concat(text))
      text = {}
    end
  end
  while offset <= #template do
    local at = template:find(pattern, offset)
    if not at then
      text[#text + 1] = template:sub(offset)
      break
    end
    if at > offset then
      text[#text + 1] = template:sub(offset, at - 1)
    end
    local char = template:sub(at, at)
    if template:sub(at + 1, at + 1) == char then
      text[#text + 1] = char
      offset = at + 2
    else
      check(char == left, "unescaped closing delimiter at byte " .. at)
      local finish = template:find(pattern, at + 1)
      check(finish ~= nil, "missing closing delimiter at byte " .. at)
      check(template:sub(finish, finish) == right, "nested placeholder at byte " .. finish)
      local key = template:sub(at + 1, finish - 1)
      if key == "" then
        index, key = index + 1, index + 1
      elseif tonumber(key) then
        key = tonumber(key)
        check(key >= 1 and key % 1 == 0 and key < math.huge, "argument indices must be positive integers")
        index = key
      end
      check(args[key] ~= nil, "missing argument " .. tostring(key))
      flush()
      vim.list_extend(result, nodes.normalize(args[key]))
      used[key] = true
      offset = finish + 1
    end
  end
  flush()
  if opts.strict ~= false then
    for key in pairs(args) do
      check(used[key], "unused argument " .. tostring(key))
    end
  end
  return result
end

function M.fmt(template, args, opts)
  return format(template, args, opts, "{}")
end

function M.fmta(template, args, opts)
  return format(template, args, opts, "<>")
end

return M
