return {
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "VeryLazy",
    opts = {
      enable = true, -- enabled by default
      max_lines = 10,  -- increased from 3 to show more context
      trim_scope = "outer",
      mode = "cursor",
    },
  },
}
