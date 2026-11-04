-- Use the real configuration and its installed sibling plugins. Both engines
-- remain loaded in this track; only buffer-local routing is switched.
vim.cmd("enew!")
vim.bo.filetype = "markdown"
require("integrations.snippets").switch(assert(vim.env.SNIPPET_BENCH_ENGINE))
-- The route changes after FileType. Ensure that route's lazy collection is
-- present before timing; no candidate lookup is measured on an empty source.
require("luasnip.loaders").load_lazy_loaded(vim.api.nvim_get_current_buf())
dofile(vim.env.SNIPPET_BENCH_ROOT .. "/bench/input.lua")
