-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.showbreak = "↪ "
vim.g.autoformat = false

-- Visual indicator for line length
vim.opt.colorcolumn = "121"

-- Aggressive highlight for lines >120
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "python", "javascript", "typescript", "lua" },
  callback = function()
    vim.opt_local.colorcolumn = "121"
    vim.cmd [[highlight OverLength guibg=#FF5555 ctermbg=Red]]
    vim.cmd [[match OverLength /\%121v.\+/]]
  end,
})

vim.opt.clipboard = "unnamedplus"
