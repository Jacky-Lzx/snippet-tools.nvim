local s = require("snippet_tools")
local registry = require("snippet_tools.registry")
local loader = require("snippet_tools.loader")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/project/snippets", "p")
vim.fn.mkdir(root .. "/global", "p")
vim.fn.mkdir(vim.fn.stdpath("state"), "p")
root = assert(vim.uv.fs_realpath(root))
local project, global = root .. "/project", root .. "/global"
local definitions = project .. "/snippets/lua.lua"
local prompts, notices, cases = 0, {}, 0
local confirm, notify = vim.fn.confirm, vim.notify
vim.fn.confirm = function()
  prompts = prompts + 1
  return 1
end
vim.notify = function(message)
  notices[#notices + 1] = message
end
local function write(file, text, trust)
  vim.fn.writefile(vim.split(text, "\n"), file)
  if trust then
    assert(vim.secure.trust({ path = file, action = "allow" }))
  end
end
local function buffer(file, ft)
  vim.cmd("enew!")
  if file then
    vim.api.nvim_buf_set_name(0, file)
  end
  vim.bo.filetype = ft or "lua"
end
local function context(before)
  local ctx = s.context()
  ctx.before = before or ""
  return ctx
end
local function find(trigger, auto)
  s.available()
  return registry.find(context(trigger), auto == true)
end
local function project_source()
  for _, source in ipairs(s.inspect().sources) do
    if source.path == definitions then
      return source
    end
  end
  error("Project source missing from inspection")
end
local function case(name, fn)
  fn()
  cases = cases + 1
  print("PASS " .. name)
end
write(
  global .. "/lua.lua",
  [[return {
  {trigger='same',body='global'},
  {trigger='fallback',body='global'},
  {trigger='higher',body='global',priority=3000},
}]]
)
write(
  definitions,
  [[_G.project_executions=(_G.project_executions or 0)+1
return {
  {trigger='same',body='project'},
  {trigger='fallback',body='project',condition=function() return false end},
  {trigger='higher',body='project'},
  {trigger='auto',body='project',auto=true},
}]]
)
write(project .. "/snippets/rust.lua", "error('Unrelated filetype executed')")
buffer(project .. "/new.lua")
s.setup({ paths = { global }, project = { root = project, paths = { "snippets" } }, keymap = false })

case("untrusted project Lua stays unexecuted and is not prompted on every input", function()
  assert(prompts == 1 and not _G.project_executions)
  assert(find("same").root == nil)
  for _ = 1, 10 do
    s.available()
  end
  assert(prompts == 1)
  assert(project_source().status == "untrusted")
end)

case("trusted project entries win ties while priority and conditions retain global fallback", function()
  assert(vim.secure.trust({ path = definitions, action = "allow" }))
  assert(s.reload())
  assert(find("same").root == project and _G.project_executions == 1)
  assert(find("higher").root == nil and find("fallback").root == nil)
  assert(registry.has_auto("lua", context()))
  local result
  require("snippet_tools.integrations.completion_tools").new().complete(context(), function(value)
    result = value
  end)
  local seen = {}
  for _, item in ipairs(result.items) do
    assert(not seen[item.label], "Duplicate completion trigger")
    seen[item.label] = true
    if item.label == "same" then
      assert(item._snippet_tools.root == project)
    elseif item.label == "fallback" then
      assert(item._snippet_tools.root == nil)
    end
  end
  assert(seen.same and seen.fallback)
  local selected = false
  for _, entry in ipairs(registry.explain(context("same"))) do
    selected = selected or entry.selected and entry.source == definitions
  end
  assert(selected)
end)

case("buffers outside the project, sibling prefixes and unnamed buffers remain isolated", function()
  local previous = find("same")
  for _, name in ipairs({ root .. "/other.lua", root .. "/project-other/new.lua" }) do
    buffer(name)
    assert(find("same").root == nil and not find("auto", true))
    assert(not s.expand_definition(previous, nil, { keep_trigger = true }))
    assert(vim.api.nvim_get_current_line() == "")
    assert(not registry.has_auto("lua", context()))
  end
  buffer()
  assert(find("same").root == nil)
  buffer(project .. "/newly-named.lua")
  assert(find("same").root == project)
  vim.api.nvim_buf_set_name(0, root .. "/renamed-outside.lua")
  assert(find("same").root == nil)
end)

case("canonical roots scope symlinked and not-yet-written buffer paths", function()
  assert(vim.uv.fs_symlink(project, root .. "/alias"))
  buffer(root .. "/alias/unwritten.lua")
  assert(find("same").root == project)
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  assert(find("same").root == project)
end)

case("project matching and collection lookup perform no repeated filesystem reads", function()
  s.available()
  local realpath, readable, secure = vim.uv.fs_realpath, vim.fn.filereadable, vim.secure.read
  vim.uv.fs_realpath = function()
    error("Repeated path resolution")
  end
  vim.fn.filereadable = function()
    error("Repeated collection stat")
  end
  vim.secure.read = function()
    error("Repeated secure read")
  end
  for _ = 1, 100 do
    assert(find("same").root == project)
  end
  vim.uv.fs_realpath, vim.fn.filereadable, vim.secure.read = realpath, readable, secure
end)

case("reload validates a complete collection before replacing the previous good definitions", function()
  write(definitions, "return {{trigger='new',body='new'}, {trigger='bad',body='${'}}", true)
  assert(not s.reload())
  assert(find("same").root == project and not find("new"))
  assert(project_source().status == "error" and #notices == 1)
  write(definitions, "return {", true)
  assert(not s.reload() and find("same").root == project)
  write(definitions, "return {{trigger='new',body='new'}}", true)
  assert(s.reload() and find("same").root == nil and find("new").root == project)
end)

case("changed or denied Lua is not executed and revocation removes old matches", function()
  write(definitions, "_G.untrusted_executed=true; return {}")
  assert(s.reload() and not find("new") and not _G.untrusted_executed)
  assert(prompts == 2)
  assert(vim.secure.trust({ path = definitions, action = "deny" }))
  assert(s.reload() and prompts == 2 and not _G.untrusted_executed)
  assert(vim.secure.trust({ path = definitions, action = "remove" }))
end)

case("reload discovers new inherited and all collections and removes deleted definitions", function()
  write(project .. "/snippets/tex.lua", "return {{trigger='inherited',body='tex'}}", true)
  write(project .. "/snippets/all.lua", "return {{trigger='everywhere',body='all'}}", true)
  s.filetype_extend("markdown", { "tex" })
  buffer(project .. "/notes.md", "markdown")
  assert(s.reload())
  assert(find("inherited").root == project and find("everywhere").root == project)
  assert(vim.fn.delete(project .. "/snippets/tex.lua") == 0)
  assert(s.reload() and not find("inherited"))
  buffer(root .. "/outside.md", "markdown")
  assert(not find("everywhere"))
end)

case(
  "reconfiguration removes loader-owned collections and retains manually registered definitions",
  function()
    s.add("all", { { trigger = "manual", body = "manual" } }, { key = "manual" })
    s.setup({ paths = { global }, keymap = false })
    buffer(project .. "/reset.lua")
    assert(find("manual") and not find("everywhere"))
    assert(find("same").root == nil)
    assert(not pcall(loader.setup, {}, { paths = { "snippets" } }))
  end
)

case("view then trust and reload works without reentrant project execution", function()
  buffer(root .. "/before-view.lua")
  write(
    definitions,
    "_G.view_executed=true; require('snippet_tools').available(); return {{trigger='viewed',body='ok'}}"
  )
  s.setup({ paths = { global }, project = { root = project, paths = { "snippets" } }, keymap = false })
  local count = 0
  vim.fn.confirm = function()
    count = count + 1
    return 2
  end
  buffer(project .. "/view.lua")
  assert(count == 1 and not _G.view_executed)
  assert(vim.api.nvim_buf_get_name(0) == definitions)
  assert(vim.secure.trust({ bufnr = 0, action = "allow" }))
  vim.api.nvim_set_current_buf(vim.fn.bufnr(project .. "/view.lua"))
  assert(s.reload() and find("viewed").root == project and _G.view_executed)
  vim.fn.confirm = function()
    return 1
  end
end)

vim.fn.confirm, vim.notify = confirm, notify
s.dispose()
vim.fn.delete(root, "rf")
print("Project sources: " .. cases .. " cases passed")
