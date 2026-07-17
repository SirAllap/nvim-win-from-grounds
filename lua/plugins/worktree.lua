-- Git worktree navigation from inside Neovim.
--
-- Every branch lives in its own worktree dir (e.g. ~/code/smith-PROJ-16755).
-- A worktree is just a folder with that branch already checked out, so there is
-- never a reason to remove one (or fight `git checkout`) just to read its code.
-- These maps let nvim follow you into a worktree instead.
--
-- Pairs with persistence.nvim: sessions are keyed by cwd, so each worktree keeps
-- its own buffer/window layout. Switching saves the layout you are leaving and
-- restores the one you are entering.
--
-- Keys (under the git group):
--   <leader>gw  switch worktree
--   <leader>gW  create worktree from a branch (new or existing)

local uv = vim.uv or vim.loop

-- Parse `git worktree list --porcelain` from the current repo into
-- { path = "/abs/path", branch = "name" } entries.
local function worktrees()
  local lines = vim.fn.systemlist({ "git", "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  local items, cur = {}, nil
  for _, line in ipairs(lines) do
    if line:sub(1, 9) == "worktree " then
      cur = { path = line:sub(10) }
    elseif line:sub(1, 7) == "branch " and cur then
      cur.branch = (line:sub(8):gsub("^refs/heads/", ""))
    elseif line == "" and cur then
      items[#items + 1] = cur
      cur = nil
    end
  end
  if cur then
    items[#items + 1] = cur
  end
  return items
end

-- Move nvim into a worktree: persist the current layout, cd over, then restore
-- the target worktree's session (or land on a file picker if it has none).
local function goto_worktree(path)
  if not path or vim.fn.isdirectory(path) == 0 then
    vim.notify("Worktree path not found: " .. tostring(path), vim.log.levels.ERROR, { title = "Worktree" })
    return
  end
  if path == uv.cwd() then
    vim.notify("Already in " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO, { title = "Worktree" })
    return
  end

  local persistence = require("persistence")
  -- Save the layout of the worktree we are leaving.
  pcall(persistence.save)
  -- Set the global cwd so file pickers, lazygit and terminals follow.
  vim.api.nvim_set_current_dir(path)
  -- Drop the old worktree's buffers; their paths point at the previous tree.
  -- (Modified buffers survive `silent!` and are left untouched.)
  vim.cmd("silent! noautocmd %bwipeout")

  -- Restore the target worktree's session if it has one, else open a picker.
  local session = persistence.current()
  if session and vim.fn.filereadable(session) == 1 then
    persistence.load()
  else
    Snacks.picker.files()
  end
  vim.notify("→ " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO, { title = "Worktree" })
end

local function switch_worktree()
  local items = worktrees()
  if #items == 0 then
    vim.notify("No worktrees found (not a git repo?)", vim.log.levels.WARN, { title = "Worktree" })
    return
  end
  local cwd = uv.cwd()
  vim.ui.select(items, {
    prompt = "Switch worktree",
    format_item = function(it)
      local name = vim.fn.fnamemodify(it.path, ":t")
      local here = (it.path == cwd) and " ●" or ""
      return string.format("%-42s %s%s", name, it.branch or "(detached)", here)
    end,
  }, function(choice)
    if choice then
      goto_worktree(choice.path)
    end
  end)
end

local function create_worktree()
  vim.ui.input({ prompt = "Branch (new or existing): " }, function(branch)
    if not branch or branch == "" then
      return
    end
    local root = (vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" }) or {})[1]
    if not root or vim.v.shell_error ~= 0 then
      vim.notify("Not inside a git repo", vim.log.levels.ERROR, { title = "Worktree" })
      return
    end
    -- Mirror the ~/code/smith-PROJ-XXXX naming: PROJ-XXXX when present, else the
    -- full branch name. Always editable in the prompt below.
    local short = branch:match("^%a+%-%d+") or branch
    local default = vim.fn.fnamemodify(root, ":h") .. "/smith-" .. short

    vim.ui.input({ prompt = "Worktree path: ", default = default, completion = "dir" }, function(path)
      if not path or path == "" then
        return
      end
      -- Reuse the branch if it already exists, otherwise cut a new one.
      vim.fn.systemlist({ "git", "rev-parse", "--verify", "--quiet", branch })
      local cmd = (vim.v.shell_error == 0)
          and { "git", "worktree", "add", path, branch }
          or { "git", "worktree", "add", "-b", branch, path }
      local out = vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify(out, vim.log.levels.ERROR, { title = "git worktree add" })
        return
      end
      goto_worktree(path)
    end)
  end)
end

return {
  "folke/snacks.nvim",
  keys = {
    { "<leader>gw", switch_worktree, desc = "Worktree: switch" },
    { "<leader>gW", create_worktree, desc = "Worktree: create from branch" },
  },
}
