local M = {}
function M.snapshot(options)
  options = options or {}
  local name = vim.api.nvim_buf_get_name(0)
  local pos = vim.api.nvim_win_get_cursor(0)
  local date = os.date("*t")
  -- Neovim raises E348 when an empty line has no current word.
  local has_word, word = pcall(vim.fn.expand, "<cword>")
  return vim.tbl_extend("force", {
    TM_SELECTED_TEXT = options.selected_text or "",
    TM_CURRENT_LINE = vim.api.nvim_get_current_line(),
    TM_CURRENT_WORD = has_word and word or "",
    TM_LINE_INDEX = tostring(pos[1] - 1),
    TM_LINE_NUMBER = tostring(pos[1]),
    TM_FILENAME = vim.fn.fnamemodify(name, ":t"),
    TM_FILENAME_BASE = vim.fn.fnamemodify(name, ":t:r"),
    TM_DIRECTORY = name == "" and "" or vim.fn.fnamemodify(name, ":h"),
    TM_FILEPATH = name,
    CURRENT_YEAR = tostring(date.year),
    CURRENT_YEAR_SHORT = os.date("%y"),
    CURRENT_MONTH = os.date("%m"),
    CURRENT_DATE = os.date("%d"),
    CURRENT_HOUR = os.date("%H"),
    CURRENT_MINUTE = os.date("%M"),
    CURRENT_SECOND = os.date("%S"),
    CURRENT_DAY_NAME = os.date("%A"),
    CURRENT_DAY_NAME_SHORT = os.date("%a"),
    CURRENT_MONTH_NAME = os.date("%B"),
    CURRENT_MONTH_NAME_SHORT = os.date("%b"),
  }, options.variables or {})
end
return M
