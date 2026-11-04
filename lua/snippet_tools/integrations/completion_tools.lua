-- This adapter uses completion-tools' public provider/custom-engine contracts.
-- Neither plugin needs to depend on the other at module-load time.
local M = {}
function M.new()
  return {
    score_offset = 30,
    complete = function(ctx, callback)
      if ctx.mode == "cmdline" then
        callback({ items = {} })
        return
      end
      ctx.cache = ctx.cache or {}
      local items = {}
      for _, entry in ipairs(require("snippet_tools").available(ctx)) do
        local match = { trigger = entry.trigger, start_col = ctx.start_col, captures = {} }
        if not entry.condition or entry.condition(ctx, match) then
          items[#items + 1] = {
            label = entry.trigger,
            kind = 15,
            insertText = "",
            _snippet_tools = entry,
            sortText = string.format("%010d", 1000000000 - math.min(entry.priority, 1000000000))
              .. entry.trigger,
          }
        end
      end
      -- Conditions depend on the current cursor/buffer, so results aren't reusable.
      callback({ items = items })
    end,
    resolve = function(entry, callback)
      local definition = entry.item._snippet_tools
      callback(vim.tbl_extend("force", {}, entry.item, {
        detail = definition.preview or definition.trigger,
        documentation = definition.description,
      }))
    end,
    execute = function(entry, ctx)
      local definition = entry.item._snippet_tools
      require("snippet_tools").expand_definition(definition, {
        trigger = definition.trigger,
        start_col = ctx.start_col,
        captures = {},
      }, { context = ctx, keep_trigger = true, join_undo = true })
    end,
  }
end

function M.options()
  return {
    providers = { snippets = M.new() },
    snippets = {
      preset = "default",
      expand = function(text, options)
        return require("snippet_tools").expand(text, {
          indent = not (options and options.insert_text_mode),
          expand_tabs = not options or options.insert_text_mode ~= 1,
          join_undo = true,
        })
      end,
      active = function(direction)
        return require("snippet_tools").active(direction)
      end,
      jump = function(direction)
        return require("snippet_tools").jump(direction)
      end,
    },
  }
end
return M
