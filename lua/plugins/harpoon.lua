return {
  "ThePrimeagen/harpoon",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("harpoon").setup({
      global_settings = {
        save_on_toggle = false,
        save_on_change = true,
        enter_on_sendcmd = false,
        tmux_autoclose_windows = false,
        excluded_filetypes = { "harpoon" },
        mark_branch = false,
        tabline = false,
      },
    })

    -- Keybindings
    local harpoon_ui = require("harpoon.ui")
    local harpoon_mark = require("harpoon.mark")

    vim.keymap.set("n", "<leader>a", harpoon_mark.add_file, { desc = "Harpoon Add File" })
    vim.keymap.set("n", "<leader>h", harpoon_ui.toggle_quick_menu, { desc = "Harpoon Quick Menu" })

    vim.keymap.set("n", "<leader>1", function()
      harpoon_ui.nav_file(1)
    end, { desc = "Harpoon File 1" })
    vim.keymap.set("n", "<leader>2", function()
      harpoon_ui.nav_file(2)
    end, { desc = "Harpoon File 2" })
    vim.keymap.set("n", "<leader>3", function()
      harpoon_ui.nav_file(3)
    end, { desc = "Harpoon File 3" })
    vim.keymap.set("n", "<leader>4", function()
      harpoon_ui.nav_file(4)
    end, { desc = "Harpoon File 4" })
  end,
}
