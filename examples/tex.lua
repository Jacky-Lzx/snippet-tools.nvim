local s = require("snippet_tools")
return {
  {
    trigger = "columns",
    description = "Beamer columns with linked widths totalling 0.98\\linewidth",
    preview = "\\begin{columns}[T,totalwidth=\\linewidth] ... \\end{columns}",
    body = s.fmta(
      [[
      \begin{columns}[T,totalwidth=\linewidth]
        \begin{column}{0.<width>\linewidth}
          <left>
        \end{column}
        \begin{column}{0.<remaining>\linewidth}
          <right>
        \end{column}
      \end{columns}<exit>
    ]],
      {
        width = s.i(1, "49"),
        left = s.i(2),
        remaining = s.f(function(args)
          local value = tonumber("0." .. args[1])
          if not value or value > 0.98 then
            return "49"
          end
          local digits = string.format("%.6f", 0.98 - value):sub(3):gsub("0+$", "")
          return digits ~= "" and digits or "0"
        end, { 1 }),
        right = s.i(3),
        exit = s.i(0),
      }
    ),
  },
  {
    trigger = "frame",
    description = "Beamer frame with optional title",
    body = s.fmta(
      [[
      \begin{frame}<title>
        <body>
      \end{frame}<exit>
    ]],
      {
        title = s.c(1, { "", s.fmta("{<>}", s.i(1, "Title")) }),
        body = s.i(2),
        exit = s.i(0),
      }
    ),
  },
}
