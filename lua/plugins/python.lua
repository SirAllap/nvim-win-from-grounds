-- Formatting with LazyVim's conform.nvim
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      python = { "black" },
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
        prepend_args = { "--line-length=79" },
      },
    },
  },
}