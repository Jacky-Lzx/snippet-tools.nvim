vim.opt.rtp:prepend(assert(vim.env.SNIPPET_BENCH_ROOT))
if vim.env.SNIPPET_BENCH_ENGINE == "luasnip" then
  vim.opt.rtp:append(assert(vim.env.SNIPPET_BENCH_LUASNIP))
end
vim.loader.enable()
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.termguicolors = true
vim.o.timeoutlen = 300
vim.o.ttimeoutlen = 10
vim.o.showmode = false
vim.o.showcmd = false
vim.o.ruler = false
vim.o.laststatus = 0
vim.o.hidden = true
vim.bo.filetype = "bench"
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
local engine = vim.env.SNIPPET_BENCH_ENGINE
if engine == "snippet-tools" then
  require("snippet_tools").setup({ keymap = false })
else
  require("luasnip").setup({
    enable_autosnippets = true,
    keep_roots = false,
    link_roots = false,
    link_children = true,
    exit_roots = true,
    update_events = { "TextChanged", "TextChangedI" },
    delete_check_events = { "TextChanged", "TextChangedI" },
  })
end
dofile(vim.env.SNIPPET_BENCH_ROOT .. "/bench/input.lua")
