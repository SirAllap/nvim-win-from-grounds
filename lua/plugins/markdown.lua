return {
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npx --yes yarn install",
    config = function()
      vim.g.mkdp_browser = '/home/serallap/bin/zen-browser'  -- Use the custom script for Zen browser
    end,
  },
}
