local M = {}
local kinds =
  { insert = true, exit = true, choice = true, dynamic = true, mirror = true, ["function"] = true }
local fields = {
  hl_group = { string = true, number = true, table = true },
  hl_eol = { boolean = true },
  hl_mode = { string = true },
  virt_text = { table = true },
  virt_text_pos = { string = true },
  virt_text_win_col = { number = true },
  virt_text_hide = { boolean = true },
  priority = { number = true },
  sign_text = { string = true },
  sign_hl_group = { string = true, number = true },
  number_hl_group = { string = true, number = true },
  line_hl_group = { string = true, number = true },
  cursorline_hl_group = { string = true, number = true },
}
local styles = {}

local function merge(...)
  local result = vim.tbl_extend("force", {}, ...)
  for key, value in pairs(result) do
    if value == false and key ~= "hl_eol" and key ~= "virt_text_hide" then
      result[key] = nil
    end
  end
  return result
end

local function node_style(passive, active, opts)
  opts = opts or {}
  return {
    passive = merge(passive, opts.passive or {}),
    active = merge(active, opts.passive or {}, opts.active or {}),
  }
end

function M.resolve(options)
  assert(options == nil or type(options) == "table", "snippet-tools: ext_opts must be a table")
  options = vim.deepcopy(options or {})
  for kind, states in pairs(options) do
    assert(kinds[kind], "snippet-tools: invalid ext_opts node type " .. tostring(kind))
    assert(type(states) == "table", "snippet-tools: ext_opts node states must be a table")
    for state, opts in pairs(states) do
      assert(
        state == "active" or state == "passive",
        "snippet-tools: invalid ext_opts state " .. tostring(state)
      )
      assert(type(opts) == "table", "snippet-tools: ext_opts state must be a table")
      for key, value in pairs(opts) do
        assert(fields[key], "snippet-tools: unsupported ext_opts display option " .. tostring(key))
        assert(value == false or fields[key][type(value)], "snippet-tools: invalid ext_opts " .. key)
        if type(value) == "number" and (key == "priority" or key == "virt_text_win_col") then
          assert(
            value >= 0 and value % 1 == 0,
            "snippet-tools: ext_opts " .. key .. " must be a nonnegative integer"
          )
        elseif key == "virt_text" and value ~= false then
          for _, chunk in ipairs(value) do
            assert(
              type(chunk) == "table" and type(chunk[1]) == "string",
              "snippet-tools: invalid virt_text chunk"
            )
          end
        end
      end
    end
  end
  local next_styles = {}
  for kind in pairs(kinds) do
    if kind ~= "exit" then
      local editable = kind == "insert" or kind == "choice" or kind == "dynamic"
      next_styles[kind] = node_style(
        { priority = 120, hl_group = editable and "SnippetToolsPlaceholder" or nil },
        { priority = 130, hl_group = "SnippetToolsActive" },
        options[kind]
      )
    end
  end
  next_styles.exit = node_style(next_styles.insert.passive, next_styles.insert.active, options.exit)
  return next_styles
end

function M.options(kind, active)
  local style = styles[kind]
  return style and style[active and "active" or "passive"] or { priority = 120 }
end

function M.configure(options)
  styles = M.resolve(options)
end

M.configure()
return M
