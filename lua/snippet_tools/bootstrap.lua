local M = {}
local options, group, initialized
function M.ensure()
  local engine = require("snippet_tools")
  if not initialized then
    local opts = vim.deepcopy(options or {})
    local extends = opts.extends or {}
    opts.extends = nil
    for filetype, parents in pairs(extends) do
      engine.filetype_extend(filetype, parents)
    end
    engine.setup(opts)
    initialized = true
    vim.api.nvim_exec_autocmds("User", { pattern = "SnippetToolsReady", modeline = false })
  end
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
  return engine
end
function M.setup(opts)
  options, initialized = vim.deepcopy(opts or {}), false
  if group then
    vim.api.nvim_del_augroup_by_id(group)
  end
  group = vim.api.nvim_create_augroup("SnippetToolsBootstrap", { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", { group = group, callback = M.ensure })
  vim.api.nvim_create_autocmd(
    "CmdUndefined",
    { group = group, pattern = "SnippetTools*", callback = M.ensure }
  )
end
return M
