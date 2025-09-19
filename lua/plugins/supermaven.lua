return {
  {
    "supermaven-inc/supermaven-nvim",
    event = "InsertEnter",
    config = function()
      require("supermaven-nvim").setup({
        keymaps = {
          accept_suggestion = "<C-l>", -- Accept suggestion (like Copilot's default)
          clear_suggestion = "<C-]>", -- Dismiss suggestion
        },
        disable_inline_completion = false, -- Show suggestions inline
        disable_keymaps = false, -- Enable Supermaven keymaps
        show_suggestions_on_insert = true, -- Auto-show as you type
      })

      -- Optional highlight customization (similar to your Copilot setup)
      vim.api.nvim_set_hl(0, "SupermavenSuggestion", { fg = "#ff80bf", italic = true, bold = true }) -- Bubble pink
    end,
  },
}
