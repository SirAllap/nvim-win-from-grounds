return {
  -- Oxocarbon: IBM Carbon-based theme by nyoom-engineering
  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = false,
    priority = 1000,
  },

  -- Make oxocarbon the default colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "oxocarbon",
    },
  },
}
