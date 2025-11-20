return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "macchiato",
      transparent_background = false,
      term_colors = true,
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
        functions = { "bold" },
        keywords = { "bold" },
        types = { "italic", "bold" },
        variables = {},
      },
      integrations = {
        telescope = true,
        treesitter = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
  },
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "storm",
    },
  },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      variant = "auto", -- auto, main, moon, or dawn
      dark_variant = "main",
      styles = {
        bold = true,
        italic = true,
        transparency = false,
      },
    },
  },
  {
    "rebelot/kanagawa.nvim",
    opts = {
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
      functionStyle = {},
      keywordStyle = { italic = true },
      statementStyle = { bold = true },
      typeStyle = {},
      transparent = false,
      theme = "wave", -- Load "wave" theme when 'background' option is not set
      background = {
        dark = "wave", -- try "dragon" !
        light = "lotus",
      },
    },
  },
  {
    "Mofiqul/dracula.nvim",
    opts = {
      colors = {},
      show_end_of_buffer = true,
      transparent_bg = false,
      lualine_bg_color = "#44475a",
      italic_comment = true,
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      pickers = {
        colorscheme = {
          enable_preview = true,
        },
      },
    },
    keys = {
      {
        "<leader>uT",
        function()
          require("telescope.builtin").colorscheme({
            enable_preview = true,
          })
        end,
        desc = "Theme Switcher",
      },
    },
  },
  {
    "maxmx03/fluoromachine.nvim",
    lazy = false, -- load immediately
    priority = 1000, -- make sure it loads before other plugins
    opts = {
      glow = false, -- enable the neon glow effect
      theme = "fluoromachine", -- optional, you can pick variants
      transparent = true,
    },
    config = function(_, opts)
      require("fluoromachine").setup(opts)
      vim.cmd.colorscheme("fluoromachine")
    end,
  },

}