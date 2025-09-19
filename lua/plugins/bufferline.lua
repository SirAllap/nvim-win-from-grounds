return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "famiu/bufdelete.nvim",
    },
    config = function()
      require("bufferline").setup({
        options = {
          mode = "buffers",
          numbers = "none",
          close_command = "Bdelete! %d",
          show_buffer_close_icons = false,
          show_close_icon = false,
          max_name_length = 18,
          truncate_names = true,
          tab_size = 20,
          diagnostics = "nvim_lsp",
          diagnostics_indicator = function(count, level)
            local icons = { error = " ", warning = " ", info = " " }
            return " " .. (icons[level:lower()] or "") .. count
          end,
          offsets = {
            { filetype = "NvimTree", text = "Files", highlight = "Directory", text_align = "left" },
          },
          separator_style = "thin",
          hover = { enabled = true, delay = 200 },
          always_show_bufferline = false,
        },
      })
      vim.keymap.set("n", "<Tab>", "<Cmd>BufferLineCycleNext<CR>")
      vim.keymap.set("n", "<S-Tab>", "<Cmd>BufferLineCyclePrev<CR>")
      vim.keymap.set("n", "<leader>bp", "<Cmd>BufferLinePick<CR>")
      vim.keymap.set("n", "<leader>bP", "<Cmd>BufferLinePickClose<CR>")
      vim.keymap.set("n", "<leader>bd", "<Cmd>Bdelete!<CR>")
      vim.keymap.set("n", "<leader>bc", "<Cmd>Bdelete!<CR>", { noremap = true, silent = true })
    end,
  },
}
