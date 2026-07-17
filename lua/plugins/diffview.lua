-- Review the full changeset of a branch / worktree without checking it out.
--
-- `:DiffviewOpen <base>...HEAD` reads the trees directly, so you can read every
-- changed file of a branch (in a file panel + side-by-side diff) without ever
-- swapping branches or removing a worktree just to look.
--
-- Keys (under the git group):
--   <leader>gv  review branch vs base (prompts for base, defaults origin/master)
--   <leader>gV  close the diffview tab
--   <leader>gH  history of the current file
return {
  "sindrets/diffview.nvim",
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
  },
  opts = {
    enhanced_diff_hl = true,
    view = {
      merge_tool = { layout = "diff3_mixed" },
    },
  },
  keys = {
    {
      "<leader>gv",
      function()
        vim.ui.input({ prompt = "Diff against (base): ", default = "origin/master" }, function(base)
          if base and base ~= "" then
            vim.cmd("DiffviewOpen " .. base .. "...HEAD")
          end
        end)
      end,
      desc = "Diffview: review branch vs base",
    },
    { "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
    { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: current file history" },
  },
}
