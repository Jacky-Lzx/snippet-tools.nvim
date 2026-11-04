local M = {}
function M.check()
  vim.health.start("snippet-tools")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim 0.11+; pure Lua engine, no build step")
  else
    vim.health.error("Neovim 0.11+ is required")
  end
  if vim.fn.exists(":SnippetToolsInspect") == 2 then
    vim.health.ok("setup() has installed snippet lifecycle handlers")
  else
    vim.health.info(
      "Call require('snippet_tools').setup() to enable automatic expansion and lifecycle handlers"
    )
  end
end
return M
