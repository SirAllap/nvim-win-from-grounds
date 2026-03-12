local function set_hl()
  vim.api.nvim_set_hl(0, "TaskDone", { fg = "#6b7280", strikethrough = true })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

local function get_tasks()
  local raw = vim.fn.system("TERM=dumb task rc.color=off rc.verbose=nothing export 2>/dev/null")
  local start = raw:find("%[\n")
  local ok, tasks = pcall(vim.fn.json_decode, start and raw:sub(start) or raw)
  if not ok or type(tasks) ~= "table" then return {} end
  local pending, done = {}, {}
  for _, t in ipairs(tasks) do
    if t.status == "pending" then table.insert(pending, t)
    elseif t.status == "completed" then table.insert(done, t)
    end
  end
  local result = {}
  for i, t in ipairs(pending) do t._idx = i; table.insert(result, t) end
  for i, t in ipairs(done)    do t._idx = i; table.insert(result, t) end
  return result
end

local function parse_input(input)
  local args = {}
  local prio_map = { h = "H", m = "M", l = "L" }
  input = input:gsub("!([hml])", function(p)
    table.insert(args, "priority:" .. prio_map[p])
    return ""
  end)
  input = input:gsub("#(%d+)", function(n)
    n = tonumber(n)
    table.insert(args, n == 0 and "due:today" or n == 1 and "due:tomorrow" or ("due:" .. n .. "d"))
    return ""
  end)
  input = input:gsub("%+(%w+)", function(tag)
    table.insert(args, "+" .. tag)
    return ""
  end)
  input = input:gsub("%s+", " "):match("^%s*(.-)%s*$")
  return input, args
end

local function add_task(callback)
  vim.ui.input({ prompt = "Task (!h/!m/!l  #0=today #1=tomorrow  +tag): " }, function(input)
    if input and input ~= "" then
      local desc, args = parse_input(input)
      vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
      vim.notify("Task added", vim.log.levels.INFO)
      if callback then callback() end
    end
  end)
end

local copied_tags = {}  -- tag clipboard

local prio_icon  = { H = "(!!) ", M = "(!)  ", L = "(.)  " }
local prio_cycle = { H = "", M = "H", L = "M", [""] = "L" }
local TAG_WIDTH  = 20
local DUE_WIDTH  = 13  -- "{YYYY-MM-DD} "

local function pad(s, width) return s .. string.rep(" ", math.max(0, width - #s)) end

local function make_entry(task)
  local is_done = task.status == "completed"
  local id      = task._idx or task.id

  -- [tag1] [tag2]
  local tag_str = (task.tags and #task.tags > 0)
    and table.concat(vim.tbl_map(function(t) return "[" .. t .. "]" end, task.tags), " ")
    or "-"
  local tag_col = pad(tag_str, TAG_WIDTH)

  -- {due date} or -
  local due_str = "-"
  if task.due then
    local y, m, d = task.due:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if y then due_str = string.format("{%s-%s-%s}", y, m, d) end
  end
  local due_col = pad(due_str, DUE_WIDTH)

  -- (priority)
  local prio_str = is_done and "(✓)  " or (prio_icon[task.priority or ""] or "-    ")

  -- task description
  local desc = string.format("=> [%s] %s", id, task.description)

  -- created date (right-aligned)
  local date_str = ""
  if task.entry then
    local y, m, d = task.entry:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if y then date_str = y .. "-" .. m .. "-" .. d end
  end

  -- highlight positions
  local p0, p1 = 0, #tag_str
  local p2, p3 = #tag_col + 3, #tag_col + 3 + #due_str      -- +3 for " | "
  local p4, p5 = #tag_col + 3 + #due_col + 3, #tag_col + 3 + #due_col + 3 + #vim.trim(prio_str)

  return {
    value   = task,
    ordinal = table.concat(vim.tbl_filter(function(s) return s ~= "" end, {
      task.description,
      tag_str ~= "-" and tag_str or "",
      ({ H = "!!", M = "!", L = "." })[task.priority or ""] or "",
      due_str ~= "-" and due_str or "",
      date_str,
    }), " "),
    display = function()
      local total = vim.api.nvim_win_get_width(0) - 2
      local mid   = tag_col .. " | " .. due_col .. " | " .. prio_str .. desc
      local rpad  = date_str ~= "" and math.max(1, total - #mid - #date_str) or 0
      local line  = mid .. string.rep(" ", rpad) .. date_str

      local hls = {}
      if is_done then
        table.insert(hls, { { 0, #line }, "TaskDone" })
      else
        if tag_str  ~= "" then table.insert(hls, { { p0, p1 }, "Type" })            end
        if due_str  ~= "" then table.insert(hls, { { p2, p3 }, "DiagnosticInfo" }) end
        if prio_str ~= "" then table.insert(hls, { { p4, p5 }, "DiagnosticWarn" }) end
        if date_str ~= "" then table.insert(hls, { { #mid + rpad, #line }, "Comment" }) end
      end
      return line, hls
    end,
  }
end

local function task_picker()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local function make_finder()
    return finders.new_table({ results = get_tasks(), entry_maker = make_entry })
  end

  local function refresh(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    local row = picker:get_selection_row()
    picker:refresh(make_finder(), { reset_prompt = false })
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(prompt_bufnr) then
        picker:set_selection(row)
      end
    end, 50)
  end

  pickers.new({}, {
    sorting_strategy = "ascending",
    prompt_title = "Tasks  [<C-a>add · <C-e>edit · <C-p>prio · <CR>toggle · <C-t>copy tags · <C-g>paste tags · <C-l>edit tags · <C-y>copy · <C-d>delete]",
    results_title = "!h !m !l = priority  ·  #0 today  #1 tomorrow  #N days  ·  +tag",
    finder = make_finder(),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)

      -- Toggle done / undo done — or add task if no results
      map({ "i", "n" }, "<CR>", function()
        local entry = action_state.get_selected_entry()
        if not entry then
          local prompt = action_state.get_current_line()
          if prompt and prompt ~= "" then
            local desc, args = parse_input(prompt)
            vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
            vim.notify("Task added: " .. desc, vim.log.levels.INFO)
            action_state.get_current_picker(prompt_bufnr):reset_prompt()
            refresh(prompt_bufnr)
          end
          return
        end
        local task = entry.value
        if task.status == "pending" then
          vim.fn.system("task rc.confirmation=no " .. task.id .. " done")
          vim.notify("Done: " .. task.description, vim.log.levels.INFO)
          refresh(prompt_bufnr)
        else
          vim.fn.system("task rc.confirmation=no " .. task.uuid .. " modify status:pending")
          vim.notify("Restored: " .. task.description, vim.log.levels.INFO)
          vim.defer_fn(function() refresh(prompt_bufnr) end, 150)
        end
      end)

      -- Add from prompt text
      map({ "i", "n" }, "<C-a>", function()
        local prompt = action_state.get_current_line()
        if prompt and prompt ~= "" then
          local desc, args = parse_input(prompt)
          vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
          vim.notify("Task added: " .. desc, vim.log.levels.INFO)
          action_state.get_current_picker(prompt_bufnr):reset_prompt()
          refresh(prompt_bufnr)
        else
          actions.close(prompt_bufnr)
          add_task(task_picker)
        end
      end)

      -- Edit task in place
      map({ "i", "n" }, "<C-e>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local task = entry.value
        -- pre-fill with current values using our syntax
        local current = task.description
        if task.tags then current = current .. " +" .. table.concat(task.tags, " +") end
        if task.priority then current = current .. " !" .. task.priority:lower() end
        if task.due then
          local y, m, d = task.due:match("^(%d%d%d%d)(%d%d)(%d%d)")
          if y then
            local due_ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
            local now = os.time()
            local today = os.time({ year = os.date("*t", now).year, month = os.date("*t", now).month, day = os.date("*t", now).day, hour = 0, min = 0, sec = 0 })
            local days = math.max(0, math.floor((due_ts - today) / 86400))
            current = current .. " #" .. days
          end
        end

        vim.ui.input({ prompt = "Edit task: ", default = current }, function(input)
          if not input or input == "" then return end
          local desc, args = parse_input(input)

          -- detect which old tags to remove
          local new_tags = {}
          for _, a in ipairs(args) do
            if a:match("^%+") then new_tags[a:sub(2)] = true end
          end
          if task.tags then
            for _, old in ipairs(task.tags) do
              if not new_tags[old] then table.insert(args, "-" .. old) end
            end
          end

          -- clear due date if it was removed
          local has_due = false
          for _, a in ipairs(args) do if a:match("^due:") then has_due = true end end
          if task.due and not has_due then table.insert(args, "due:") end

          -- clear priority if it was removed
          local has_prio = false
          for _, a in ipairs(args) do if a:match("^priority:") then has_prio = true end end
          if task.priority and not has_prio then table.insert(args, "priority:") end

          local ref = task.id ~= 0 and task.id or task.uuid
          vim.fn.system("task rc.confirmation=no " .. ref .. " modify " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
          vim.notify("Task updated", vim.log.levels.INFO)
          refresh(prompt_bufnr)
        end)
      end)

      -- Cycle priority
      map({ "i", "n" }, "<C-p>", function()
        local entry = action_state.get_selected_entry()
        if not entry or entry.value.status == "completed" then return end
        local current = entry.value.priority or ""
        local next_p = prio_cycle[current] or ""
        local cmd = next_p ~= ""
          and ("task rc.confirmation=no " .. entry.value.id .. " modify priority:" .. next_p)
          or  ("task rc.confirmation=no " .. entry.value.id .. " modify priority:")
        vim.fn.system(cmd)
        vim.notify("Priority: " .. (next_p ~= "" and next_p or "none"), vim.log.levels.INFO)
        refresh(prompt_bufnr)
      end)

      -- Copy all tags from task
      map({ "i", "n" }, "<C-t>", function()
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value.tags or #entry.value.tags == 0 then
          vim.notify("No tags on this task", vim.log.levels.WARN)
          return
        end
        copied_tags = vim.deepcopy(entry.value.tags)
        vim.notify("Tags copied: " .. table.concat(copied_tags, ", "), vim.log.levels.INFO)
      end)

      -- Apply copied tags (merge, no duplicates, preserve existing)
      map({ "i", "n" }, "<C-g>", function()
        if #copied_tags == 0 then
          vim.notify("No tags copied yet", vim.log.levels.WARN)
          return
        end
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local existing = {}
        for _, t in ipairs(entry.value.tags or {}) do existing[t] = true end
        local to_add = {}
        for _, t in ipairs(copied_tags) do
          if not existing[t] then table.insert(to_add, "+" .. t) end
        end
        if #to_add == 0 then
          vim.notify("All tags already present", vim.log.levels.INFO)
          return
        end
        local ref = entry.value.status == "pending" and entry.value.id or entry.value.uuid
        vim.fn.system("task rc.confirmation=no " .. ref .. " modify " .. table.concat(to_add, " "))
        vim.notify("Applied: " .. table.concat(to_add, " "), vim.log.levels.INFO)
        refresh(prompt_bufnr)
      end)

      -- Interactive tag editor
      map({ "i", "n" }, "<C-l>", function()
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value.tags or #entry.value.tags == 0 then
          vim.notify("No tags on this task", vim.log.levels.WARN)
          return
        end
        local task = entry.value
        local ref = task.status == "pending" and task.id or task.uuid
        actions.close(prompt_bufnr)
        vim.schedule(function()
          -- Nested picker: select tag
          pickers.new({}, {
            prompt_title = "Select tag",
            sorting_strategy = "ascending",
            finder = finders.new_table({
              results = task.tags,
              entry_maker = function(t)
                return { value = t, display = "[" .. t .. "]", ordinal = t }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(tag_bufnr, tag_map)
              tag_map({ "i", "n" }, "<Esc>", function() actions.close(tag_bufnr); task_picker() end)
              tag_map({ "i", "n" }, "<C-c>", function() actions.close(tag_bufnr); task_picker() end)
              actions.select_default:replace(function()
                local tag_entry = action_state.get_selected_entry()
                if not tag_entry then actions.close(tag_bufnr); task_picker(); return end
                local tag = tag_entry.value
                actions.close(tag_bufnr)
                vim.schedule(function()
                  -- Nested picker: select action
                  pickers.new({}, {
                    prompt_title = "[" .. tag .. "] →",
                    sorting_strategy = "ascending",
                    finder = finders.new_table({
                      results = { "Delete", "Rename" },
                      entry_maker = function(a)
                        return { value = a, display = a, ordinal = a }
                      end,
                    }),
                    sorter = conf.generic_sorter({}),
                    attach_mappings = function(act_bufnr, act_map)
                      act_map({ "i", "n" }, "<Esc>", function() actions.close(act_bufnr); task_picker() end)
                      act_map({ "i", "n" }, "<C-c>", function() actions.close(act_bufnr); task_picker() end)
                      actions.select_default:replace(function()
                        local act_entry = action_state.get_selected_entry()
                        if not act_entry then actions.close(act_bufnr); task_picker(); return end
                        local act = act_entry.value
                        actions.close(act_bufnr)
                        if act == "Delete" then
                          vim.fn.system("task rc.confirmation=no " .. ref .. " modify -" .. tag)
                          vim.notify("Removed: " .. tag, vim.log.levels.INFO)
                          task_picker()
                        else
                          vim.ui.input({ prompt = "Rename [" .. tag .. "] to: ", default = tag }, function(new)
                            if new and new ~= "" and new ~= tag then
                              vim.fn.system("task rc.confirmation=no " .. ref .. " modify -" .. tag .. " +" .. new)
                              vim.notify("Renamed: " .. tag .. " → " .. new, vim.log.levels.INFO)
                            end
                            task_picker()
                          end)
                        end
                      end)
                      return true
                    end,
                  }):find()
                end)
              end)
              return true
            end,
          }):find()
        end)
      end)

      -- Copy task description
      map({ "i", "n" }, "<C-y>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        vim.fn.setreg("+", entry.value.description)
        vim.notify("Copied: " .. entry.value.description, vim.log.levels.INFO)
      end)

      -- Delete
      map({ "i", "n" }, "<C-d>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local ref = entry.value.status == "pending" and entry.value.id or entry.value.uuid
        vim.fn.system("task rc.confirmation=no " .. ref .. " delete")
        vim.notify("Deleted: " .. entry.value.description, vim.log.levels.WARN)
        refresh(prompt_bufnr)
      end)

      return true
    end,
  }):find()
end

return {
  "folke/snacks.nvim",
  keys = {
    { "<leader>tl", task_picker, desc = "Task List" },
    { "<leader>ta", function() add_task() end, desc = "Add Task" },
  },
}
