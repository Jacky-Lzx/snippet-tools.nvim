-- Neovim 0.11 accepts allow only for a buffer; newer releases also accept paths.
-- Load the generated fixture without changing the current buffer or window.
return function(file)
  local existing = vim.fn.bufnr(file)
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  local ok, message = vim.secure.trust({ bufnr = buf, action = "allow" })
  if existing == -1 then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  assert(ok, message)
end
