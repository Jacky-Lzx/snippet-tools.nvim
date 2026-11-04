local s = require("snippet_tools")
return {
  {
    trigger = "columns",
    description = "Beamer columns with linked widths totalling 0.98\\linewidth",
    preview = "\\begin{columns}[T,totalwidth=\\linewidth] ... \\end{columns}",
    body = {
      s.t("\\begin{columns}[T,totalwidth=\\linewidth]\n  \\begin{column}{0."),
      s.i(1, "49"),
      s.t("\\linewidth}\n    "),
      s.i(2),
      s.t("\n  \\end{column}\n  \\begin{column}{0."),
      s.f(function(args)
        local value = tonumber("0." .. args[1])
        if not value or value > 0.98 then
          return "49"
        end
        local digits = string.format("%.6f", 0.98 - value):sub(3):gsub("0+$", "")
        return digits ~= "" and digits or "0"
      end, { 1 }),
      s.t("\\linewidth}\n    "),
      s.i(3),
      s.t("\n  \\end{column}\n\\end{columns}"),
      s.i(0),
    },
  },
  {
    trigger = "frame",
    description = "Beamer frame with optional title",
    body = {
      s.t("\\begin{frame}"),
      s.c(1, { "", { s.t("{"), s.i(1, "Title"), s.t("}") } }),
      s.t("\n  "),
      s.i(2),
      s.t("\n\\end{frame}"),
      s.i(0),
    },
  },
}
