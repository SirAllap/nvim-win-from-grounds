-- Override LazyVim's default persistence.nvim spec to auto-load the last
-- session when nvim starts with no file arguments. Combined with tmux-resurrect
-- this restores buffers/splits/cursor after a reboot.
return {
  "folke/persistence.nvim",
  -- Force eager load so the VimEnter autocmd is registered before VimEnter
  -- actually fires (LazyVim's default `event = "BufReadPre"` is too late when
  -- nvim is launched with no file args).
  lazy = false,
  init = function()
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("persistence_autoload", { clear = true }),
      nested = true,
      callback = function()
        if vim.fn.argc(-1) == 0 and not vim.g.started_with_stdin then
          require("persistence").load()
        end
      end,
    })
  end,
}
