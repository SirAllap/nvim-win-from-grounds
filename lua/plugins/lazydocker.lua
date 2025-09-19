return {
  "crnvl96/lazydocker.nvim",
  event = "VeryLazy",
  cmd = { "LazyDockerToggle", "LazyDocker" }, -- custom commands
  opts = function()
    return {
      window = {
        settings = {
          width = 0.9,
          height = 0.9,
          border = "none",
          relative = "editor",
        },
        on_open = function()
          -- auto insert mode for terminal usability
          vim.cmd("startinsert")
        end,
        on_close = function()
          -- optional: return to normal mode when closing
          vim.cmd("stopinsert")
        end,
      },
    }
  end,
  config = function(_, opts)
    require("lazydocker").setup(opts)

    -- Define custom command for convenience
    vim.api.nvim_create_user_command("LazyDocker", function()
      require("lazydocker").open()
    end, {})

    vim.api.nvim_create_user_command("LazyDockerToggle", function()
      require("lazydocker").toggle()
    end, {})
  end,
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
}
