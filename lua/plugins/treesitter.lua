return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- Parsers required by snacks.nvim to render inline LaTeX/typst math in docs.
    -- opts_extend on LazyVim's side appends these to the default ensure_installed list.
    opts = {
      ensure_installed = { "latex", "typst" },
    },
    init = function()
      -- Fix: files reopened at startup (restored from a persistence session, or
      -- brought back by tmux-resurrect) can open with NO filetype set. LazyVim's
      -- sessionoptions doesn't save buffer-local options, so filetype must be
      -- re-detected on restore — but detection doesn't fire on those buffers, so
      -- they get no filetype => no treesitter language => no syntax highlighting
      -- (and no LSP, no ftplugin).
      --
      -- Once startup settles, for every loaded buffer with an empty filetype, run
      -- `:filetype detect`. That sets the filetype and fires FileType, which starts
      -- treesitter highlight, attaches LSP, etc. As a belt-and-suspenders step we
      -- also force treesitter highlight if a parser exists but isn't active yet.
      local function rehighlight()
        vim.schedule(function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
              local ft = vim.bo[buf].filetype
              if ft == "" then
                -- restored buffer never got filetype detection — run it now
                pcall(function()
                  vim.api.nvim_buf_call(buf, function()
                    vim.cmd("filetype detect")
                  end)
                end)
                ft = vim.bo[buf].filetype
              end
              -- ensure treesitter highlight even if the FileType handler didn't start it
              local lang = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
              if lang and vim.treesitter.highlighter.active[buf] == nil then
                pcall(vim.treesitter.start, buf, lang)
              end
            end
          end
        end)
      end

      local group = vim.api.nvim_create_augroup("ts_startup_rehighlight", { clear = true })
      -- VeryLazy fires once after VimEnter/UIEnter — covers files opened via argv
      -- (tmux-resurrect) AND a session auto-restored by persistence at VimEnter.
      vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", group = group, callback = rehighlight })
      -- Also covers loading a session manually mid-run (persistence fires this after source).
      vim.api.nvim_create_autocmd("User", { pattern = "PersistenceLoadPost", group = group, callback = rehighlight })
    end,
  },
}
