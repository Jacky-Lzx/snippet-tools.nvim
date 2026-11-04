local nodes = require("snippet_tools.nodes")
local M = {}

function M.render(body, options)
  options = options or {}
  local records, groups, values, evaluating = {}, {}, {}, {}
  local definitions, scopes = {}, {}
  local text, length = {}, 0
  local function key(scope, index)
    return scope .. "/" .. index
  end
  local function collect(list, scope)
    definitions[scope] = definitions[scope] or {}
    for _, node in ipairs(list) do
      if node.index and node.kind ~= "mirror" then
        local old = definitions[scope][node.index]
        if not old or (#(old.children or {}) == 0 and #(node.children or {}) > 0) then
          definitions[scope][node.index] = node
        end
      end
      if node.kind == "insert" then
        collect(node.children, scope)
      end
    end
  end
  local emit, value, flatten
  local function args(node, scope)
    local result = {}
    for i, dep in ipairs(node.deps or {}) do
      result[i] = value(dep, scope)
    end
    return result
  end
  flatten = function(list, scope)
    local result = {}
    for _, node in ipairs(list) do
      if node.kind == "text" then
        result[#result + 1] = node.text
      elseif node.kind == "variable" then
        local v = (options.variables or {})[node.name]
        if v == nil and options.resolve_variable then
          v = options.resolve_variable(node.name)
        end
        result[#result + 1] = v ~= nil and tostring(v)
          or (#(node.children or {}) > 0 and flatten(node.children, scope) or node.name)
      elseif node.kind == "function" then
        result[#result + 1] = tostring(node.fn(args(node, scope), options.context) or "")
      elseif node.kind == "dynamic" then
        result[#result + 1] = "" -- Generated children are rendered in their own scope below.
      else
        result[#result + 1] = value(node.index, scope)
      end
    end
    return table.concat(result)
  end
  value = function(index, scope)
    local id = key(scope, index)
    if values[id] ~= nil then
      return values[id]
    end
    assert(not evaluating[id], "snippet-tools: cyclic placeholder dependency: " .. id)
    evaluating[id] = true
    local node = (definitions[scope] or {})[index]
    local saved = (options.values or {})[id]
    local v = saved
    if v == nil then
      v = node
          and flatten(
            node.kind == "choice" and node.branches[(options.choices or {})[id] or 1] or node.children or {},
            scope
          )
        or ""
    end
    evaluating[id], values[id] = nil, v
    return v
  end
  local function append(s)
    text[#text + 1], length = s, length + #s
  end
  emit = function(list, scope, parent, order)
    collect(list, scope)
    scopes[scope] = order or {}
    for ordinal, original in ipairs(list) do
      local node, id = original, original.index and key(scope, original.index)
      local record = { node = node, scope = scope, parent = parent, start = length, ordinal = ordinal }
      records[#records + 1] = record
      if id and groups[id] then
        record.kind, record.key = "mirror", id
        append(value(node.index, scope))
      elseif node.kind == "insert" or node.kind == "choice" or node.kind == "dynamic" then
        node = definitions[scope][node.index]
        record.node, record.kind, record.key, groups[id] = node, node.kind, id, record
        local path =
          vim.list_extend(vim.deepcopy(order or {}), { node.index == 0 and math.huge or node.index })
        record.order = path
        local saved = (options.values or {})[id]
        if node.kind == "insert" then
          if saved ~= nil then
            append(saved)
          else
            emit(node.children, scope, record, order)
          end
        elseif node.kind == "choice" then
          record.choice = (options.choices or {})[id] or 1
          emit(node.branches[record.choice], id .. "@" .. record.choice, record, path)
        else
          emit(
            nodes.normalize(node.fn(args(node, scope), options.context) or {}),
            id .. "@dynamic",
            record,
            path
          )
        end
        values[id] = table.concat(text):sub(record.start + 1)
      elseif node.kind == "mirror" then
        record.kind, record.key = "mirror", id
        append(value(node.index, scope))
      elseif node.kind == "function" then
        record.kind = "function"
        append(tostring(node.fn(args(node, scope), options.context) or ""))
      elseif node.kind == "variable" then
        record.kind = "text"
        append(flatten({ node }, scope))
      else
        assert(node.kind == "text", "snippet-tools: unknown node kind " .. tostring(node.kind))
        record.kind = "text"
        append(node.text)
      end
      record.finish = length
    end
  end
  collect(body, options.scope or "root")
  emit(body, options.scope or "root", nil, options.order)
  return { text = table.concat(text), records = records, groups = groups, values = values }
end

return M
