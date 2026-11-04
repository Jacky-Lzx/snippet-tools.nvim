local M = {}
local paths, loaded = {}, {}
function M.setup(directories)
  paths, loaded = {}, {}
  for _, path in ipairs(directories or {}) do
    assert(type(path) == "string", "snippet-tools: snippet paths must be strings")
    paths[#paths + 1] = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/$", "")
  end
end
function M.load(filetypes, reload)
  for _, ft in ipairs(filetypes) do
    assert(ft:match("^[%w_.-]+$") and ft ~= "." and ft ~= "..", "snippet-tools: invalid snippet filename")
    for _, directory in ipairs(paths) do
      local path = directory .. "/" .. ft .. ".lua"
      if reload or not loaded[path] then
        if vim.fn.filereadable(path) == 1 then
          local definitions = dofile(path)
          assert(type(definitions) == "table", "snippet-tools: " .. path .. " must return definitions")
          require("snippet_tools.registry").add(ft, definitions, { key = path })
        elseif loaded[path] then
          require("snippet_tools.registry").add(ft, {}, { key = path })
        end
        loaded[path] = true
      end
    end
  end
end
return M
