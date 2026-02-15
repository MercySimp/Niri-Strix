return {
  {
    "bjarneo/aether.nvim",
    name = "aether",
    priority = 1000,
    opts = {
      disable_italics = false,
      colors = {
        -- Monotone shades (base00-base07)
        base00 = "#000000", -- Default background
        base01 = "#000000", -- Lighter background (status bars)
        base02 = "#524549", -- Selection background
        base03 = "#b18d85", -- Comments, invisibles
        base04 = "#edbcb3", -- Dark foreground
        base05 = "#f8f8f2", -- Default foreground
        base06 = "#fdf9f8", -- Light foreground
        base07 = "#edbcb3", -- Light background

        -- Accent colors (base08-base0F)
        base08 = "#d70000", -- Variables, errors, red
        base09 = "#ff8d34", -- Integers, constants, orange
        base0A = "#ffb86c", -- Classes, types, yellow
        base0B = "#9f6769", -- Strings, green
        base0C = "#5bd9f3", -- Support, regex, cyan
        base0D = "#6575ab", -- Functions, keywords, blue
        base0E = "#9a8c8a", -- Keywords, storage, magenta
        base0F = "#d7adad", -- Deprecated, brown/yellow
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
