local nodes = require("snippet_tools.nodes")
local M = {}

function M.render(body, options)
  options = options or {}
  local records, groups, values, evaluating = {}, {}, {}, {}
  local definitions, generated = {}, {}
  local text, length = {}, 0
  local function resolve(node)
    local v = (options.variables or {})[node.name]
    if v == nil and options.resolve_variable then
      v = options.resolve_variable(node.name)
    end
    return v
  end
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
      if node.children then
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
  local function branch(node, scope)
    local id = key(scope, node.index)
    if generated[id] then
      return generated[id][1], generated[id][2]
    end
    local list, child_scope
    if node.kind == "choice" then
      local choice = (options.choices or {})[id] or 1
      list, child_scope = node.branches[choice], id .. "@" .. choice
    else
      list, child_scope = nodes.normalize(node.fn(args(node, scope), options.context) or {}), id .. "@dynamic"
    end
    generated[id] = { list, child_scope }
    collect(list, child_scope)
    return list, child_scope
  end
  flatten = function(list, scope)
    local result = {}
    for _, node in ipairs(list) do
      if node.kind == "text" then
        result[#result + 1] = node.text
      elseif node.kind == "variable" then
        local v = resolve(node)
        result[#result + 1] = ((v == nil or v == "") and #(node.children or {}) > 0)
            and flatten(node.children, scope)
          or (v ~= nil and tostring(v) or node.name)
      elseif node.kind == "function" then
        result[#result + 1] = tostring(node.fn(args(node, scope), options.context) or "")
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
    local saved = node and node.kind == "insert" and (options.values or {})[id] or nil
    local v = saved
    if v == nil then
      if node and (node.kind == "choice" or node.kind == "dynamic") then
        local list, child_scope = branch(node, scope)
        v = flatten(list, child_scope)
      else
        v = node and flatten(node.children or {}, scope) or ""
      end
    end
    evaluating[id], values[id] = nil, v
    return v
  end
  local function append(s)
    text[#text + 1], length = s, length + #s
  end
  emit = function(list, scope, parent, order, depth)
    depth = (depth or 0) + 1
    assert(depth <= 64, "snippet-tools: generated snippet exceeds 64 nesting levels")
    collect(list, scope)
    for ordinal, original in ipairs(list) do
      if original.kind == "variable" and resolve(original) == nil and #(original.children or {}) == 0 then
        local highest = 0
        for i in pairs(definitions[scope]) do
          highest = math.max(highest, i)
        end
        original = nodes.insert(highest + 1, original.name)
        definitions[scope][original.index] = original
      end
      local node, id = original, original.index and key(scope, original.index)
      local record = { node = node, scope = scope, parent = parent, start = length, ordinal = ordinal }
      local first_part = #text + 1
      records[#records + 1] = record
      if id and groups[id] then
        record.kind, record.key = "mirror", id
        append(value(node.index, scope))
      elseif node.kind == "insert" or node.kind == "choice" or node.kind == "dynamic" then
        node = definitions[scope][node.index]
        record.node, record.kind, record.key, groups[id] = node, node.kind, id, record
        local path = {}
        for i, part in ipairs(order or {}) do
          path[i] = part
        end
        path[#path + 1] = node.index == 0 and math.huge or node.index
        record.order = path
        local saved = (options.values or {})[id]
        if node.kind == "insert" then
          if saved ~= nil then
            append(saved)
          else
            emit(node.children, scope, record, order, depth)
          end
        elseif node.kind == "choice" then
          record.choice = (options.choices or {})[id] or 1
          local list, child_scope = branch(node, scope)
          emit(list, child_scope, record, path, depth)
        else
          local list, child_scope = branch(node, scope)
          emit(list, child_scope, record, path, depth)
        end
        values[id] = table.concat(text, "", first_part, #text)
      elseif node.kind == "mirror" then
        record.kind, record.key = "mirror", id
        append(value(node.index, scope))
      elseif node.kind == "function" then
        record.kind = "function"
        append(tostring(node.fn(args(node, scope), options.context) or ""))
      elseif node.kind == "variable" then
        record.kind = "text"
        local v = resolve(node)
        if (v == nil or v == "") and #(node.children or {}) > 0 then
          emit(node.children, scope, parent, order, depth)
        else
          append(v ~= nil and tostring(v) or node.name)
        end
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
