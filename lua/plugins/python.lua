-- Formatting with LazyVim's conform.nvim
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      python = function(bufnr)
        -- Use Ruff in Smith project, Black elsewhere
        if vim.startswith(vim.fn.getcwd(), '/home/serallap/code/smith') then
          return {} -- Disable conform, use custom autocmd
        else
          return { "black" }
        end
      end,
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      css = { "prettier" },
      scss = { "prettier" },
      html = { "prettier" },
    },
    formatters = {
      black = {
        prepend_args = { "--line-length=79" }, -- Keep for non-Smith
      },
    },
  },
}