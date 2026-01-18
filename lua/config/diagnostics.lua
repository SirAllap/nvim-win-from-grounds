vim.diagnostic.config({
  virtual_text = false, -- ❌ inline text
  signs = false,        -- ❌ gutter icons
  underline = false,    -- ❌ squiggly lines
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    header = "",
    prefix = "",
  },
})

