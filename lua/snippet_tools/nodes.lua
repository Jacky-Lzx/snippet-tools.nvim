local M = {}

local function index(value)
  assert(type(value) == "number" and value >= 0 and value % 1 == 0, "snippet-tools: invalid node index")
  return value
end

function M.text(value)
  assert(type(value) == "string", "snippet-tools: text must be a string")
  return { kind = "text", text = value }
end

function M.insert(pos, default)
  return { kind = "insert", index = index(pos), children = default == nil and {} or M.normalize(default) }
end

function M.choice(pos, choices)
  assert(type(choices) == "table" and #choices > 0, "snippet-tools: choice requires alternatives")
  local branches = {}
  for i, branch in ipairs(choices) do
    branches[i] = M.normalize(branch)
  end
  return { kind = "choice", index = index(pos), branches = branches }
end

function M.mirror(pos)
  return { kind = "mirror", index = index(pos) }
end

local function computed(kind, pos, fn, deps)
  assert(type(fn) == "function", "snippet-tools: computed nodes require a function")
  for _, dep in ipairs(deps or {}) do
    index(dep)
  end
  return { kind = kind, index = pos and index(pos), fn = fn, deps = deps or {} }
end

function M.func(fn, deps)
  return computed("function", nil, fn, deps)
end

function M.dynamic(pos, fn, deps)
  return computed("dynamic", pos, fn, deps)
end

function M.normalize(value)
  if type(value) == "string" then
    return { M.text(value) }
  end
  assert(type(value) == "table", "snippet-tools: expected a string or nodes")
  if value.kind then
    return { value }
  end
  local result = {}
  for _, node in ipairs(value) do
    assert(type(node) == "table" and type(node.kind) == "string", "snippet-tools: invalid node")
    result[#result + 1] = node
  end
  return result
end

return M
