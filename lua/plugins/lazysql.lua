--- File: ~/.config/nvim/lua/plugins/lazysql.lua (Final Working Version)
return {
  "LostbBlizzard/lazysql.nvim",
  -- Change cmd to only include the registered command
  cmd = { "LazySql" },

  opts = {
    window = {
      settings = {
        width = 0.9,
        height = 0.9,
        border = "none",
        relative = "editor",
      },
      on_open = function()
        vim.cmd("startinsert")
      end,
      on_close = function()
        vim.cmd("stopinsert")
      end,
    },
  },

  -- Update the keymap to use the registered command
  keys = {
    {
      "<leader>dd",
      "<cmd>LazySql<CR>", -- ⬅️ CHANGED FROM LazySqlToggle
      mode = "n",
      desc = "Toggle LazySql TUI",
    },
  },

  dependencies = {
    "MunifTanjim/nui.nvim",
  },
}
