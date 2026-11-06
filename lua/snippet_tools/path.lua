local M = {}
local buffers = {}

-- Resolve the existing ancestor as well, so newly named files and symlinked
-- project paths use the same scope before their first write.
function M.normalize(path)
  local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/+$", "")
  absolute = absolute ~= "" and vim.fs.normalize(absolute) or "/"
  local ancestor, suffix = absolute, {}
  while true do
    local real = vim.uv.fs_realpath(ancestor)
    if real then
      return vim.fs.normalize(real .. (#suffix > 0 and "/" .. table.concat(suffix, "/") or ""))
    end
    local parent = vim.fs.dirname(ancestor)
    if not parent or parent == ancestor then
      return absolute
    end
    table.insert(suffix, 1, vim.fs.basename(ancestor))
    ancestor = parent
  end
end

function M.buffer(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" then
    return nil
  end
  if not buffers[buf] or buffers[buf].name ~= name then
    buffers[buf] = { name = name, path = M.normalize(name) }
  end
  return buffers[buf].path
end

function M.contains(root, path)
  return path ~= nil and (root == "/" or path:sub(1, #root + 1) == root .. "/")
end

function M.invalidate(buf)
  if buf then
    buffers[buf] = nil
  else
    buffers = {}
  end
end

return M
