local M = {}
local path = require("snippet_tools.path")
local sources = {}

local function directories(value, label)
  assert(type(value) == "table" and vim.islist(value), "snippet-tools: " .. label .. " must be a list")
  for _, directory in ipairs(value) do
    assert(
      type(directory) == "string" and directory ~= "",
      "snippet-tools: snippet paths must be nonempty strings"
    )
  end
  return value
end

function M.prepare(global_paths, project)
  local next_sources, seen = {}, {}
  local function add(directory, root)
    local absolute = path.normalize(directory)
    local key = (root or "") .. "\0" .. absolute
    if not seen[key] then
      seen[key] = true
      next_sources[#next_sources + 1] = { path = absolute, root = root, files = {} }
    end
  end
  for _, directory in ipairs(directories(global_paths or {}, "paths")) do
    add(directory)
  end
  if project and project ~= false then
    assert(type(project) == "table", "snippet-tools: project must be a table or false")
    assert(type(project.root) == "string" and project.root ~= "", "snippet-tools: project.root is required")
    local root = path.normalize(project.root)
    for _, directory in ipairs(directories(project.paths or { ".nvim/snippets" }, "project.paths")) do
      local expanded = vim.fn.expand(directory)
      add(expanded:match("^/") and expanded or root .. "/" .. expanded, root)
    end
  end
  return next_sources
end

function M.apply(next_sources)
  for _, source in ipairs(sources) do
    for ft, state in pairs(source.files) do
      require("snippet_tools.registry").remove(ft, state.key)
    end
  end
  sources = next_sources
  path.invalidate()
end

function M.setup(global_paths, project)
  M.apply(M.prepare(global_paths, project))
end

function M.dispose()
  M.apply({})
end

local function active(source, buf)
  return not source.root or path.contains(source.root, path.buffer(buf))
end

local function load(source, ft)
  local filename = source.path .. "/" .. ft .. ".lua"
  local previous = source.files[ft]
  local state =
    { path = filename, key = source.root and source.root .. "\0" .. filename or filename, status = "loading" }
  source.files[ft] = state
  local registry = require("snippet_tools.registry")
  local ok, definitions, status = pcall(function()
    if vim.fn.filereadable(filename) ~= 1 then
      return nil, "missing"
    end
    local chunk
    if source.root then
      local contents = vim.secure.read(filename)
      if not contents then
        state.trust = "untrusted"
        return nil, "untrusted"
      end
      state.trust = "trusted"
      chunk = assert(loadstring(contents, "@" .. filename))
    else
      chunk = assert(loadfile(filename))
    end
    local result = chunk()
    assert(type(result) == "table" and vim.islist(result), "snippet file must return a list of definitions")
    return result, "loaded"
  end)
  if ok and status == "loaded" then
    ok, state.error = pcall(registry.add, ft, definitions, {
      key = state.key,
      root = source.root,
      source = filename,
    })
    state.count = ok and #definitions or previous and previous.count or 0
  elseif ok then
    registry.remove(ft, state.key)
    state.count = 0
  else
    state.error = definitions
    state.count = previous and previous.count or 0
  end
  state.status = ok and status or "error"
  if not ok then
    vim.notify("snippet-tools: " .. filename .. ": " .. tostring(state.error), vim.log.levels.ERROR)
  end
  source.files[ft] = state
  return ok
end

function M.load(filetypes, reload, buf)
  local success = true
  for _, ft in ipairs(filetypes) do
    assert(ft:match("^[%w_.-]+$") and ft ~= "." and ft ~= "..", "snippet-tools: invalid snippet filename")
    for _, source in ipairs(sources) do
      local state = source.files[ft]
      if active(source, buf) and (not state or state.status ~= "loading") and (reload or not state) then
        success = load(source, ft) and success
      end
    end
  end
  return success
end

function M.inspect(filetypes, buf)
  local result = {}
  for _, source in ipairs(sources) do
    for _, ft in ipairs(filetypes) do
      local state = source.files[ft]
      result[#result + 1] = {
        path = source.path .. "/" .. ft .. ".lua",
        root = source.root,
        active = active(source, buf),
        trust = source.root and (state and state.trust or "unchecked") or "global",
        status = state and state.status or "pending",
        count = state and state.count or 0,
        error = state and state.error,
      }
    end
  end
  return result
end

return M
