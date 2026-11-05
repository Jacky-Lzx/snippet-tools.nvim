vim.opt.rtp:prepend(vim.fn.getcwd())
local bootstrap = require("snippet_tools.bootstrap")
bootstrap.setup({ keymap = false, paths = {}, extends = { markdown = { "tex" } } })
assert(not package.loaded.snippet_tools)
local ready = 0
vim.api.nvim_create_autocmd("User", {
  pattern = "SnippetToolsReady",
  callback = function()
    ready = ready + 1
  end,
})
vim.api.nvim_exec_autocmds("InsertEnter", {})
assert(package.loaded.snippet_tools and ready == 1)
bootstrap.ensure()
assert(ready == 1 and vim.fn.exists("#SnippetToolsBootstrap") == 0)
print("Snippet-owned first-input setup and one-time initialization passed")
