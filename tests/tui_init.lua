vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.termguicolors = true
vim.o.timeoutlen = 200
vim.o.ttimeoutlen = 30
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.filetype = "lua"
local s = require("snippet_tools")
local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end
local function setup()
  s.setup({
    keymap = {
      ["<Tab>"] = "expand_or_jump",
      ["<S-Tab>"] = "jump_backward",
      ["<F6>"] = "choice_next",
      ["<F7>"] = "choice_prev",
    },
  })
end
setup()
function _G.snippet_tui_reset(kind)
  if package.loaded.completion_tools then
    require("completion_tools").dispose()
  end
  s.dispose()
  require("snippet_tools.registry").clear()
  vim.cmd("enew!")
  vim.bo.filetype, vim.bo.expandtab, vim.bo.shiftwidth = "lua", true, 2
  notifications = {}
  setup()
  if kind == "mirror" then
    fixture = "hello ${1:world} / $1!$0"
  elseif kind == "choice" then
    fixture = "${1|red,blue|}=$1$0"
  elseif kind == "dynamic" then
    fixture = {
      s.i(1, "49"),
      s.t("/"),
      s.f(function(a)
        return tostring(98 - (tonumber(a[1]) or 0))
      end, { 1 }),
      s.i(0),
    }
  elseif kind == "nested" then
    fixture = "[${1:outer}]=${1}:${2:next}$0"
  elseif kind == "auto" then
    s.add("lua", { { trigger = "mk", body = "[$1]$0", auto = true } })
  elseif kind == "completion" then
    vim.opt.runtimepath:append(vim.env.COMPLETION_TOOLS_PATH)
    s.setup({ keymap = false })
    s.add("lua", { { trigger = "greet", body = "hello ${1:world} / $1$0" } })
    local opts = require("snippet_tools.integrations.completion_tools").options()
    opts.sources = { "snippets" }
    require("completion_tools").setup(opts)
  end
end
vim.keymap.set({ "i", "s" }, "<F5>", function()
  s.expand(fixture)
end)
vim.keymap.set({ "i", "s" }, "<F8>", function()
  s.expand("(${1:inner})$0")
end)
local timer = vim.uv.new_timer()
timer:start(
  0,
  15,
  vim.schedule_wrap(function()
    local row = vim.fn.screenpos(vim.api.nvim_get_current_win(), 1, 1).row
    local cells = {}
    if row > 0 then
      for col = 1, math.min(vim.o.columns, 100) do
        cells[#cells + 1] = vim.fn.screenstring(row, col)
      end
    end
    local state = {
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      mode = vim.api.nvim_get_mode().mode,
      cursor = vim.api.nvim_win_get_cursor(0),
      session = s.inspect(),
      screen = table.concat(cells),
      errors = notifications,
      menu = package.loaded.completion_tools and require("completion_tools").is_menu_visible() or false,
    }
    vim.fn.writefile({ vim.json.encode(state) }, vim.env.SNIPPET_TUI_STATE)
  end)
)
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    timer:stop()
    timer:close()
  end,
})
