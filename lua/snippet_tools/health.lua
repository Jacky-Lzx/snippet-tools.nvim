local M = {}

function M.check()
  vim.health.start("snippet-tools.nvim")
  if vim.fn.has("nvim-0.11") == 0 then
    vim.health.error("Neovim 0.11+ is required", { "Upgrade Neovim" })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  if vim.fn.exists(":SnippetToolsInfo") == 0 then
    vim.health.info("Not configured; snippet lifecycle checks skipped.")
    return
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == "error"
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok("Snippet lifecycle handlers are installed.")
  end
  vim.health.info("Details: :SnippetToolsInfo")
end

return M
