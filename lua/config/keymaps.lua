-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local keymap = vim.keymap
local opts = { noremap = true, silent = true }

-- Lazydocker
keymap.set("n", "<Leader>k", function()
  require("lazydocker").toggle()
end, { desc = "Open LazyDocker" })

-- Select all
keymap.set("n", "<C-a>", "gg<S-v>G")

-- Split window
keymap.set("n", "ss", ":split<Return>", opts)
keymap.set("n", "sv", ":vsplit<Return>", opts)

-- Move window
keymap.set("n", "sh", "<C-w>h")
keymap.set("n", "sk", "<C-w>k")
keymap.set("n", "sj", "<C-w>j")
keymap.set("n", "sl", "<C-w>l")

-- Resize window
keymap.set("n", "<C-w><left>", "<C-w><")
keymap.set("n", "<C-w><right>", "<C-w>>")
keymap.set("n", "<C-w><up>", "<C-w>+")
keymap.set("n", "<C-w><down>", "<C-w>-")

-- Close window
keymap.set("n", "sw", ":close<CR>", opts)

-- Rename symbol
keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename Symbol" })

-- Exit insert mode
keymap.set("i", "jj", "<Esc>", opts)

-- Show diagnostic under cursor
vim.keymap.set("n", "<leader>cd", function()
  vim.diagnostic.open_float(nil, { focus = false })
end, { desc = "Show diagnostic" })

-- Toggle diagnostics (per buffer)
vim.keymap.set("n", "<leader>td", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local disabled = vim.diagnostic.is_disabled(bufnr)
  if disabled then
    vim.diagnostic.enable(bufnr)
  else
    vim.diagnostic.disable(bufnr)
  end
end, { desc = "Toggle diagnostics" })

-- Manual Python format with Ruff (Smith project only)
vim.keymap.set("n", "<leader>fp", function()
  require("config.format").format_python_file()
end, { desc = "Format Python file with Ruff" })
