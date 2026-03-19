return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function() return _G.taskwarrior_status() end,
      cond = function() return _G.taskwarrior_status() ~= "" end,
      color = { fg = "#e2e8f0" },
    })
  end,
}
