-- Highlights
local function set_hl()
  vim.api.nvim_set_hl(0, "TaskDone", { fg = "#6b7280", strikethrough = true })
  vim.api.nvim_set_hl(0, "TaskOverdue", { fg = "#ef4444", bold = true })
  vim.api.nvim_set_hl(0, "TaskDueToday", { fg = "#eab308", bold = true })
  vim.api.nvim_set_hl(0, "TaskProject", { fg = "#7c3aed", bold = true })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

-- Due date helpers (defined early — used by sl_refresh and startup notification)
local function today_ts()
  local t = os.date("*t")
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

-- Parse a taskwarrior UTC timestamp ("20260330T220000Z") into a local Unix timestamp.
-- Taskwarrior always exports dates in UTC; reading just the date portion gives the wrong
-- day for UTC+ users (local midnight = previous day in UTC).
local function parse_tw_date(tw_str)
  if not tw_str then return nil end
  local y, mo, d, h, mi, s = tw_str:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
  if not y then
    y, mo, d = tw_str:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0, min = 0, sec = 0 })
  end
  local fake_ts = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                             hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local utc_t = os.date("!*t", fake_ts)
  utc_t.isdst = nil -- let os.time auto-detect DST; "!*t" returns isdst=false which skews the offset
  local diff = os.difftime(fake_ts, os.time(utc_t))
  return fake_ts + diff
end

-- Return the local date string "YYYY-MM-DD" for a taskwarrior UTC timestamp.
local function tw_date_str(tw_str)
  local ts = parse_tw_date(tw_str)
  if not ts then return nil end
  local t = os.date("*t", ts)
  return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

-- Statusline widget (async, cached)
local sl_cache = { text = "", ts = 0 }
local SL_TTL = 30

local function sl_refresh()
  sl_cache.ts = os.time()
  vim.fn.jobstart({ "bash", "-c", "TERM=dumb task rc.color=off rc.verbose=nothing export 2>/dev/null" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local raw = table.concat(data, "\n")
      local s = raw:find("%[\n")
      local ok, tasks = pcall(vim.fn.json_decode, s and raw:sub(s) or raw)
      if not ok or type(tasks) ~= "table" then sl_cache.text = ""; sl_cache.ts = os.time(); return end
      local pending, overdue, due_today = 0, 0, 0
      local today = today_ts()
      local tomorrow = today + 86400
      for _, t in ipairs(tasks) do
        if t.status == "pending" then
          pending = pending + 1
          if t.due then
            local due_ts = parse_tw_date(t.due)
            if due_ts then
              local dd = os.date("*t", due_ts)
              due_ts = os.time({ year = dd.year, month = dd.month, day = dd.day, hour = 0, min = 0, sec = 0 })
              if due_ts < today then overdue = overdue + 1
              elseif due_ts < tomorrow then due_today = due_today + 1 end
            end
          end
        end
      end
      if pending == 0 then sl_cache.text = ""; sl_cache.ts = os.time(); return end
      local parts = { pending .. " tasks" }
      if overdue > 0 then table.insert(parts, overdue .. " overdue") end
      if due_today > 0 then table.insert(parts, due_today .. " due today") end
      sl_cache.text = table.concat(parts, " · ")
      sl_cache.ts = os.time()
    end,
  })
end
vim.defer_fn(sl_refresh, 1000)

_G.taskwarrior_status = function()
  if os.time() - sl_cache.ts > SL_TTL then sl_refresh() end
  return sl_cache.text
end

-- Startup notification for overdue tasks
vim.defer_fn(function()
  local raw = vim.fn.system("TERM=dumb task rc.color=off rc.verbose=nothing export 2>/dev/null")
  local s = raw:find("%[\n")
  local ok, tasks = pcall(vim.fn.json_decode, s and raw:sub(s) or raw)
  if not ok or type(tasks) ~= "table" then return end
  local today = today_ts()
  local tomorrow = today + 86400
  local overdue, due_today = {}, {}
  for _, t in ipairs(tasks) do
    if t.status == "pending" and t.due then
      local due_ts = parse_tw_date(t.due)
      if due_ts then
        local dd = os.date("*t", due_ts)
        due_ts = os.time({ year = dd.year, month = dd.month, day = dd.day, hour = 0, min = 0, sec = 0 })
        if due_ts < today then table.insert(overdue, t.description)
        elseif due_ts < tomorrow then table.insert(due_today, t.description) end
      end
    end
  end
  if #overdue == 0 and #due_today == 0 then return end
  local lines = {}
  if #overdue > 0 then
    table.insert(lines, "OVERDUE (" .. #overdue .. "):")
    for _, desc in ipairs(overdue) do table.insert(lines, "  - " .. desc) end
  end
  if #due_today > 0 then
    if #lines > 0 then table.insert(lines, "") end
    table.insert(lines, "DUE TODAY (" .. #due_today .. "):")
    for _, desc in ipairs(due_today) do table.insert(lines, "  - " .. desc) end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN, { title = "Taskwarrior" })
end, 2000)

-- State
local copied_tags = {}
local sort_mode = "default"
local filter_tag = nil
local filter_project = nil
local sort_modes = { "default", "priority", "due", "created", "urgency" }

local function due_status(task)
  if not task.due then return nil end
  local due_ts = parse_tw_date(task.due)
  if not due_ts then return nil end
  -- Snap to local midnight for day-level comparison
  local due_day = os.date("*t", due_ts)
  due_ts = os.time({ year = due_day.year, month = due_day.month, day = due_day.day, hour = 0, min = 0, sec = 0 })
  if task.status == "completed" then
    if task["end"] then
      local end_ts = parse_tw_date(task["end"])
      if end_ts then
        local end_day = os.date("*t", end_ts)
        end_ts = os.time({ year = end_day.year, month = end_day.month, day = end_day.day, hour = 0, min = 0, sec = 0 })
        if due_ts < end_ts then return "overdue" end
      end
    end
    return nil
  end
  local today = today_ts()
  if due_ts < today then return "overdue"
  elseif due_ts < today + 86400 then return "today"
  end
  return nil
end

-- Task fetching with sort + filter
local function get_tasks()
  local raw = vim.fn.system("TERM=dumb task rc.color=off rc.verbose=nothing export 2>/dev/null")
  local start = raw:find("%[\n")
  local ok, tasks = pcall(vim.fn.json_decode, start and raw:sub(start) or raw)
  if not ok or type(tasks) ~= "table" then return {}, 0, 0 end

  local pending, done = {}, {}
  local overdue_n, today_n = 0, 0

  for _, t in ipairs(tasks) do
    if t.status == "pending" then
      -- filter
      if filter_tag then
        local has = false
        for _, tag in ipairs(t.tags or {}) do if tag == filter_tag then has = true end end
        if not has then goto continue end
      end
      if filter_project and t.project ~= filter_project then goto continue end
      local ds = due_status(t)
      if ds == "overdue" then overdue_n = overdue_n + 1
      elseif ds == "today" then today_n = today_n + 1 end
      table.insert(pending, t)
    elseif t.status == "completed" then
      if not filter_tag and not filter_project then table.insert(done, t) end
    end
    ::continue::
  end

  -- Sort pending
  if sort_mode == "priority" then
    local pw = { H = 3, M = 2, L = 1 }
    table.sort(pending, function(a, b) return (pw[a.priority] or 0) > (pw[b.priority] or 0) end)
  elseif sort_mode == "due" then
    table.sort(pending, function(a, b) return (a.due or "9") < (b.due or "9") end)
  elseif sort_mode == "created" then
    table.sort(pending, function(a, b) return (a.entry or "") > (b.entry or "") end)
  elseif sort_mode == "urgency" then
    table.sort(pending, function(a, b) return (a.urgency or 0) > (b.urgency or 0) end)
  end

  local result = {}
  for i, t in ipairs(pending) do t._idx = i; table.insert(result, t) end
  for i, t in ipairs(done) do t._idx = i; table.insert(result, t) end
  return result, overdue_n, today_n
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
  input = input:gsub("@([%w][%w.]*)", function(proj)
    table.insert(args, "project:" .. proj)
    return ""
  end)
  input = input:gsub("(due:%d%d%d%d%-%d%d%-%d%d)", function(d)
    table.insert(args, d)
    return ""
  end)
  input = input:gsub("%s+", " "):match("^%s*(.-)%s*$")
  return input, args
end

local function add_task(callback)
  vim.ui.input({ prompt = "Task (!h/!m/!l  #0=today #1=tomorrow  +tag  @project):" }, function(input)
    if input and input ~= "" then
      local desc, args = parse_input(input)
      vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
      vim.notify("Task added", vim.log.levels.INFO)
      sl_refresh()
      if callback then callback() end
    end
  end)
end

local prio_icon  = { H = "(!!) ", M = "(!)  ", L = "(.)  " }
local prio_cycle = { H = "", M = "H", L = "M", [""] = "L" }
local TAG_WIDTH  = 20
local DUE_WIDTH  = 13

local function pad(s, width) return s .. string.rep(" ", math.max(0, width - #s)) end

local function make_entry(task)
  local is_done = task.status == "completed"
  local id = task._idx or task.id

  local tag_str = (task.tags and #task.tags > 0)
    and table.concat(vim.tbl_map(function(t) return "[" .. t .. "]" end, task.tags), " ")
    or "-"
  local tag_col = pad(tag_str, TAG_WIDTH)

  local due_str = "-"
  local due_local = tw_date_str(task.due)
  if due_local then due_str = "{" .. due_local .. "}" end
  local due_col = pad(due_str, DUE_WIDTH)

  local prio_str = is_done and "(✓)  " or (prio_icon[task.priority or ""] or "-    ")
  local id_prefix = string.format("=> [%s] ", id)
  local project_str = task.project and ("@" .. task.project .. " ") or ""
  local desc = id_prefix .. project_str .. task.description

  local date_str = tw_date_str(task.entry) or ""

  local p0, p1 = 0, #tag_str
  local p2, p3 = #tag_col + 3, #tag_col + 3 + #due_str
  local p4, p5 = #tag_col + 3 + #due_col + 3, #tag_col + 3 + #due_col + 3 + #vim.trim(prio_str)
  local desc_start = #tag_col + 3 + #due_col + 3 + #prio_str
  local p6 = desc_start + #id_prefix
  local p7 = p6 + #project_str

  local ds = due_status(task)

  return {
    value = task,
    ordinal = table.concat(vim.tbl_filter(function(s) return s ~= "" end, {
      task.description,
      tag_str ~= "-" and tag_str or "",
      ({ H = "!!", M = "!", L = "." })[task.priority or ""] or "",
      due_str ~= "-" and due_str or "",
      date_str,
      task.project or "",
    }), " "),
    display = function()
      local total = vim.api.nvim_win_get_width(0) - 2
      local mid = tag_col .. " | " .. due_col .. " | " .. prio_str .. desc
      local rpad = date_str ~= "" and math.max(1, total - #mid - #date_str) or 0
      local line = mid .. string.rep(" ", rpad) .. date_str

      local hls = {}
      if is_done then
        table.insert(hls, { { 0, #line }, "TaskDone" })
      else
        if tag_str ~= "-" then table.insert(hls, { { p0, p1 }, "Type" }) end
        -- due date warning colors
        if ds == "overdue" then
          table.insert(hls, { { p2, p3 }, "TaskOverdue" })
        elseif ds == "today" then
          table.insert(hls, { { p2, p3 }, "TaskDueToday" })
        elseif due_str ~= "-" then
          table.insert(hls, { { p2, p3 }, "DiagnosticInfo" })
        end
        if task.priority then table.insert(hls, { { p4, p5 }, "DiagnosticWarn" }) end
        if project_str ~= "" then table.insert(hls, { { p6, p7 }, "TaskProject" }) end
        if date_str ~= "" then table.insert(hls, { { #mid + rpad, #line }, "Comment" }) end
      end
      return line, hls
    end,
  }
end

local function task_picker()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local action_utils = require("telescope.actions.utils")

  local preview_winid = nil
  local task_previewer = previewers.new_buffer_previewer({
    title = "Task Details",
    define_preview = function(self, entry)
      preview_winid = self.state.winid
      local task = entry.value
      local lines = { task.description, "" }
      if task.tags and #task.tags > 0 then
        table.insert(lines, "Tags:     " .. table.concat(vim.tbl_map(function(t) return "[" .. t .. "]" end, task.tags), " "))
      end
      if task.priority then
        local p = ({ H = "High (!!)", M = "Medium (!)", L = "Low (.)" })[task.priority] or task.priority
        table.insert(lines, "Priority: " .. p)
      end
      local due_local = tw_date_str(task.due)
      if due_local then
        local label = due_local
        local ds = due_status(task)
        if ds == "overdue" then label = label .. " [OVERDUE]"
        elseif ds == "today" then label = label .. " [TODAY]" end
        table.insert(lines, "Due:      " .. label)
      end
      if task.project then
        table.insert(lines, "Project:  " .. task.project)
      end
      local created_local = tw_date_str(task.entry)
      if created_local then table.insert(lines, "Created:  " .. created_local) end
      table.insert(lines, "Status:   " .. task.status)
      local completed_local = tw_date_str(task["end"])
      if completed_local then table.insert(lines, "Completed: " .. completed_local) end
      if task.annotations and #task.annotations > 0 then
        local urls, notes = {}, {}
        for _, ann in ipairs(task.annotations) do
          local url = (ann.description or ""):match("https?://[^%s]+")
          if url then table.insert(urls, url)
          else table.insert(notes, ann.description or "") end
        end
        if #urls > 0 then
          table.insert(lines, "")
          table.insert(lines, "URLs:")
          for _, u in ipairs(urls) do table.insert(lines, "  " .. u) end
        end
        if #notes > 0 then
          table.insert(lines, "")
          table.insert(lines, "Notes:")
          for _, n in ipairs(notes) do table.insert(lines, "  - " .. n) end
        end
      end
      local safe_lines = {}
      for _, line in ipairs(lines) do
        for _, subline in ipairs(vim.split(line, "\n", { plain = true })) do
          table.insert(safe_lines, subline)
        end
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, safe_lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(self.state.winid) then
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
        end
      end)
    end,
  })

  local all_tasks, overdue_n, today_n = get_tasks()

  local function results_title()
    local pending_n = #vim.tbl_filter(function(t) return t.status == "pending" end, all_tasks)
    local done_n = #vim.tbl_filter(function(t) return t.status == "completed" end, all_tasks)
    local parts = { pending_n .. " pending" }
    if done_n > 0 then table.insert(parts, done_n .. " done") end
    if overdue_n > 0 then table.insert(parts, overdue_n .. " overdue") end
    if today_n > 0 then table.insert(parts, today_n .. " due today") end
    if filter_tag then table.insert(parts, "filter: [" .. filter_tag .. "]") end
    if filter_project then table.insert(parts, "filter: @" .. filter_project) end
    if sort_mode ~= "default" then table.insert(parts, "sort: " .. sort_mode) end
    return table.concat(parts, " · ")
  end

  local function make_finder_with(tasks)
    return finders.new_table({ results = tasks, entry_maker = make_entry })
  end

  local function make_finder()
    return make_finder_with(all_tasks)
  end

  local function full_refresh(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    local row = picker:get_selection_row()
    all_tasks, overdue_n, today_n = get_tasks()
    picker:refresh(make_finder(), { reset_prompt = false })
    picker.results_title = results_title()
    picker.results_border:change_title(results_title())
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(prompt_bufnr) then
        picker:set_selection(row)
      end
    end, 50)
  end

  pickers.new({}, {
    sorting_strategy = "ascending",
    initial_mode = "normal",
    layout_strategy = "vertical",
    layout_config = {
      preview_cutoff = 1,
      preview_height = 0.3,
    },
    prompt_title = "Tasks  [<C-a>add · <C-e>edit · <C-n>note · <C-o>url · <C-p>prio · <C-s>sort · <C-f>filter · <Tab>sel · <C-b>bulk · <C-d>del]",
    results_title = results_title(),
    finder = make_finder(),
    previewer = task_previewer,
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)

      -- Switch to search/create bar
      map("n", "<C-w>", function() vim.cmd("startinsert") end)

      -- Preview scroll mode: l enters, h exits. j/k scroll preview instead of moving selection.
      local preview_mode = false
      local function set_preview_hl(active)
        if not preview_winid or not vim.api.nvim_win_is_valid(preview_winid) then return end
        if active then
          vim.wo[preview_winid].cursorline = true
          vim.wo[preview_winid].winhighlight = "FloatBorder:DiagnosticOk,CursorLine:Visual"
        else
          vim.wo[preview_winid].cursorline = false
          vim.wo[preview_winid].winhighlight = ""
        end
      end
      map("n", "l", function()
        preview_mode = true
        set_preview_hl(true)
      end)
      map("n", "h", function()
        if preview_mode then
          preview_mode = false
          set_preview_hl(false)
        end
      end)
      map("n", "j", function()
        if preview_mode and preview_winid and vim.api.nvim_win_is_valid(preview_winid) then
          vim.api.nvim_win_call(preview_winid, function() vim.cmd("normal! 3j") end)
        else
          actions.move_selection_next(prompt_bufnr)
        end
      end)
      map("n", "k", function()
        if preview_mode and preview_winid and vim.api.nvim_win_is_valid(preview_winid) then
          vim.api.nvim_win_call(preview_winid, function() vim.cmd("normal! 3k") end)
        else
          actions.move_selection_previous(prompt_bufnr)
        end
      end)

      -- Toggle done / undo done — or add task if no results
      local function toggle_or_add()
        -- Ignore clicks originating from the previewer window
        local mouse_win = vim.fn.win_getid(vim.v.mouse_win)
        if preview_winid and mouse_win == preview_winid then return end

        local entry = action_state.get_selected_entry()
        if not entry then
          local prompt = action_state.get_current_line()
          if prompt and prompt ~= "" then
            local desc, args = parse_input(prompt)
            vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
            vim.notify("Task added: " .. desc, vim.log.levels.INFO)
            action_state.get_current_picker(prompt_bufnr):reset_prompt()
            sl_refresh()
            full_refresh(prompt_bufnr)
          end
          return
        end
        local task = entry.value
        if task.status == "pending" then
          vim.fn.system("task rc.confirmation=no " .. task.id .. " done")
          vim.notify("Done: " .. task.description, vim.log.levels.INFO)
          sl_refresh()
          full_refresh(prompt_bufnr)
        else
          vim.fn.system("task rc.confirmation=no " .. task.uuid .. " modify status:pending")
          vim.notify("Restored: " .. task.description, vim.log.levels.INFO)
          sl_refresh()
          vim.defer_fn(function() full_refresh(prompt_bufnr) end, 150)
        end
      end
      actions.select_default:replace(toggle_or_add)
      map({ "i", "n" }, "<CR>", toggle_or_add)

      -- Add from prompt text
      map({ "i", "n" }, "<C-a>", function()
        local prompt = action_state.get_current_line()
        if prompt and prompt ~= "" then
          local desc, args = parse_input(prompt)
          vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
          vim.notify("Task added: " .. desc, vim.log.levels.INFO)
          action_state.get_current_picker(prompt_bufnr):reset_prompt()
          sl_refresh()
          full_refresh(prompt_bufnr)
        else
          vim.ui.input({ prompt = "Task (!h/!m/!l  #0=today #1=tomorrow  +tag  @project):" }, function(input)
            if not input or input == "" then return end
            local desc, args = parse_input(input)
            vim.fn.system("task add " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
            vim.notify("Task added: " .. desc, vim.log.levels.INFO)
            sl_refresh()
            full_refresh(prompt_bufnr)
          end)
        end
      end)

      -- Edit task in place
      map({ "i", "n" }, "<C-e>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local task = entry.value
        local current = task.description
        if task.tags then current = current .. " +" .. table.concat(task.tags, " +") end
        if task.priority then current = current .. " !" .. task.priority:lower() end
        if task.project then current = current .. " @" .. task.project end
        if task.due then
          local due_ts = parse_tw_date(task.due)
          if due_ts then
            local due_day = os.date("*t", due_ts)
            due_ts = os.time({ year = due_day.year, month = due_day.month, day = due_day.day, hour = 0, min = 0, sec = 0 })
            local days = math.floor((due_ts - today_ts()) / 86400)
            if days >= 0 then
              current = current .. " #" .. days
            else
              current = current .. " due:" .. tw_date_str(task.due)
            end
          end
        end
        vim.ui.input({ prompt = "Edit task (!h/!m/!l  #0=today #1=tomorrow  +tag  @project):", default = current }, function(input)
          if not input or input == "" then return end
          local desc, args = parse_input(input)
          local new_tags = {}
          for _, a in ipairs(args) do
            if a:match("^%+") then new_tags[a:sub(2)] = true end
          end
          if task.tags then
            for _, old in ipairs(task.tags) do
              if not new_tags[old] then table.insert(args, "-" .. old) end
            end
          end
          local has_due = false
          for _, a in ipairs(args) do if a:match("^due:") then has_due = true end end
          if task.due and not has_due then table.insert(args, "due:") end
          local has_prio = false
          for _, a in ipairs(args) do if a:match("^priority:") then has_prio = true end end
          if task.priority and not has_prio then table.insert(args, "priority:") end
          local has_proj = false
          for _, a in ipairs(args) do if a:match("^project:") then has_proj = true end end
          if task.project and not has_proj then table.insert(args, "project:") end
          local ref = task.id ~= 0 and task.id or task.uuid
          vim.fn.system("task rc.confirmation=no " .. ref .. " modify " .. vim.fn.shellescape(desc) .. " " .. table.concat(args, " "))
          vim.notify("Task updated", vim.log.levels.INFO)
          sl_refresh()
          full_refresh(prompt_bufnr)
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
        full_refresh(prompt_bufnr)
      end)

      -- Sort toggle
      map({ "i", "n" }, "<C-s>", function()
        local idx = 1
        for i, m in ipairs(sort_modes) do
          if m == sort_mode then idx = i; break end
        end
        sort_mode = sort_modes[(idx % #sort_modes) + 1]
        vim.notify("Sort: " .. sort_mode, vim.log.levels.INFO)
        full_refresh(prompt_bufnr)
      end)

      -- Filter by tag or project
      map({ "i", "n" }, "<C-f>", function()
        if filter_tag or filter_project then
          filter_tag = nil
          filter_project = nil
          vim.notify("Filter cleared", vim.log.levels.INFO)
          full_refresh(prompt_bufnr)
          return
        end
        local items, seen = {}, {}
        for _, t in ipairs(all_tasks) do
          for _, tag in ipairs(t.tags or {}) do
            local key = "tag:" .. tag
            if not seen[key] then seen[key] = true; table.insert(items, { kind = "tag", value = tag, display = "[" .. tag .. "]" }) end
          end
          if t.project then
            local key = "project:" .. t.project
            if not seen[key] then seen[key] = true; table.insert(items, { kind = "project", value = t.project, display = "@" .. t.project }) end
          end
        end
        if #items == 0 then vim.notify("No tags or projects found", vim.log.levels.WARN); return end
        table.sort(items, function(a, b)
          if a.kind ~= b.kind then return a.kind < b.kind end
          return a.value < b.value
        end)
        actions.close(prompt_bufnr)
        vim.schedule(function()
          pickers.new({}, {
            prompt_title = "Filter by tag / project  [<Esc> cancel]",
            sorting_strategy = "ascending",
            finder = finders.new_table({
              results = items,
              entry_maker = function(item)
                return { value = item, display = item.display, ordinal = item.value }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(fbufnr, fmap)
              fmap({ "i", "n" }, "<Esc>", function() actions.close(fbufnr); task_picker() end)
              fmap({ "i", "n" }, "<C-c>", function() actions.close(fbufnr); task_picker() end)
              actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                if sel then
                  if sel.value.kind == "tag" then filter_tag = sel.value.value
                  else filter_project = sel.value.value end
                end
                actions.close(fbufnr)
                task_picker()
              end)
              return true
            end,
          }):find()
        end)
      end)

      -- Bulk actions on multi-selected tasks
      map({ "i", "n" }, "<C-b>", function()
        local selected = {}
        action_utils.map_selections(prompt_bufnr, function(entry)
          table.insert(selected, entry.value)
        end)
        if #selected == 0 then
          vim.notify("No tasks selected (use <Tab> to select)", vim.log.levels.WARN)
          return
        end
        actions.close(prompt_bufnr)
        vim.schedule(function()
          local bulk_actions = { "Mark done", "Set priority High", "Set priority Medium", "Set priority Low", "Clear priority", "Add tag", "Delete" }
          pickers.new({}, {
            prompt_title = "Bulk action on " .. #selected .. " tasks",
            sorting_strategy = "ascending",
            finder = finders.new_table({
              results = bulk_actions,
              entry_maker = function(a) return { value = a, display = a, ordinal = a } end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(bbufnr, bmap)
              bmap({ "i", "n" }, "<Esc>", function() actions.close(bbufnr); task_picker() end)
              bmap({ "i", "n" }, "<C-c>", function() actions.close(bbufnr); task_picker() end)
              actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                if not sel then actions.close(bbufnr); task_picker(); return end
                local act = sel.value
                actions.close(bbufnr)
                local function apply(modify_str)
                  for _, t in ipairs(selected) do
                    local ref = t.status == "pending" and t.id or t.uuid
                    vim.fn.system("task rc.confirmation=no " .. ref .. " " .. modify_str)
                  end
                  vim.notify(act .. " applied to " .. #selected .. " tasks", vim.log.levels.INFO)
                  sl_refresh()
                  task_picker()
                end
                if act == "Mark done" then apply("done")
                elseif act == "Set priority High" then apply("modify priority:H")
                elseif act == "Set priority Medium" then apply("modify priority:M")
                elseif act == "Set priority Low" then apply("modify priority:L")
                elseif act == "Clear priority" then apply("modify priority:")
                elseif act == "Delete" then apply("delete")
                elseif act == "Add tag" then
                  vim.ui.input({ prompt = "Tag to add: " }, function(tag)
                    if tag and tag ~= "" then apply("modify +" .. tag) end
                  end)
                end
              end)
              return true
            end,
          }):find()
        end)
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
        full_refresh(prompt_bufnr)
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

      -- Add note/annotation to task (floating scratch buffer)
      map({ "i", "n" }, "<C-n>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local task = entry.value
        local ref = task.status == "pending" and task.id or task.uuid

        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].filetype = "markdown"

        local width = math.min(80, vim.o.columns - 4)
        local height = 12
        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          row = math.floor((vim.o.lines - height) / 2),
          col = math.floor((vim.o.columns - width) / 2),
          width = width,
          height = height,
          style = "minimal",
          border = "rounded",
          title = " Note: " .. task.description:sub(1, 50) .. " ",
          title_pos = "center",
          footer = " <C-s> save · <Esc>/<q> cancel ",
          footer_pos = "center",
        })
        vim.wo[win].wrap = true
        vim.wo[win].linebreak = true
        vim.cmd("startinsert")

        local function save()
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
          local note = table.concat(lines, "\n")
          vim.api.nvim_win_close(win, true)
          if note ~= "" then
            vim.fn.system("task rc.confirmation=no " .. ref .. " annotate " .. vim.fn.shellescape(note))
            vim.notify("Note added", vim.log.levels.INFO)
            full_refresh(prompt_bufnr)
          end
        end

        local function cancel()
          vim.api.nvim_win_close(win, true)
        end

        vim.keymap.set({ "i", "n" }, "<C-s>", save, { buffer = buf, nowait = true })
        vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
        vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
      end)

      -- Open URL from annotations (or add one if none exist)
      map({ "i", "n" }, "<C-o>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local task = entry.value
        local urls = {}
        for _, ann in ipairs(task.annotations or {}) do
          local url = (ann.description or ""):match("https?://[^%s]+")
          if url then table.insert(urls, url) end
        end
        if #urls == 0 then
          vim.ui.input({ prompt = "Add URL to task: " }, function(url)
            if not url or url == "" then return end
            local ref = task.status == "pending" and task.id or task.uuid
            vim.fn.system("task rc.confirmation=no " .. ref .. " annotate " .. vim.fn.shellescape(url))
            vim.notify("URL added", vim.log.levels.INFO)
            full_refresh(prompt_bufnr)
          end)
        elseif #urls == 1 then
          vim.ui.open(urls[1])
        else
          actions.close(prompt_bufnr)
          vim.schedule(function()
            pickers.new({}, {
              prompt_title = "Open URL  [<Esc> cancel]",
              sorting_strategy = "ascending",
              finder = finders.new_table({
                results = urls,
                entry_maker = function(u) return { value = u, display = u, ordinal = u } end,
              }),
              sorter = conf.generic_sorter({}),
              attach_mappings = function(ubufnr, umap)
                umap({ "i", "n" }, "<Esc>", function() actions.close(ubufnr); task_picker() end)
                umap({ "i", "n" }, "<C-c>", function() actions.close(ubufnr); task_picker() end)
                actions.select_default:replace(function()
                  local sel = action_state.get_selected_entry()
                  if sel then vim.ui.open(sel.value) end
                  actions.close(ubufnr)
                  task_picker()
                end)
                return true
              end,
            }):find()
          end)
        end
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
        sl_refresh()
        full_refresh(prompt_bufnr)
      end)

      return true
    end,
  }):find()
end

-- TODO comment scanner
local function scan_todos()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- scan with ripgrep for TODO/FIXME/HACK/NOTE comments
  local raw = vim.fn.systemlist("rg --no-heading --line-number --column '(TODO|FIXME|HACK):\\s*(.+)' --pcre2 -o -r '$1: $2' 2>/dev/null")
  if #raw == 0 then
    vim.notify("No TODO/FIXME/HACK comments found", vim.log.levels.INFO)
    return
  end

  -- parse: each line is "file:line:col:TYPE: description"
  local items = {}
  for _, line in ipairs(raw) do
    local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.+)$")
    if file and text then
      table.insert(items, {
        file = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = vim.trim(text),
        display_text = file .. ":" .. lnum .. "  " .. vim.trim(text),
      })
    end
  end

  if #items == 0 then
    vim.notify("No TODO/FIXME/HACK comments found", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "TODO Comments  [<CR> create task · <C-o> jump to file · <Tab> multi-select · <C-b> bulk create]",
    sorting_strategy = "ascending",
    initial_mode = "normal",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = item.display_text,
          ordinal = item.text .. " " .. item.file,
          filename = item.file,
          lnum = item.lnum,
          col = item.col,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(bufnr, smap)
      -- Create task from single item
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local item = entry.value
        vim.fn.system("task add " .. vim.fn.shellescape(item.text) .. " +code")
        vim.notify("Task created: " .. item.text, vim.log.levels.INFO)
        sl_refresh()
      end)
      -- Jump to file
      smap({ "i", "n" }, "<C-o>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(bufnr)
        vim.cmd("edit " .. vim.fn.fnameescape(entry.value.file))
        vim.api.nvim_win_set_cursor(0, { entry.value.lnum, entry.value.col - 1 })
      end)
      -- Bulk create tasks from multi-selected
      smap({ "i", "n" }, "<C-b>", function()
        local action_utils = require("telescope.actions.utils")
        local selected = {}
        action_utils.map_selections(bufnr, function(entry)
          table.insert(selected, entry.value)
        end)
        if #selected == 0 then
          vim.notify("No items selected (use <Tab>)", vim.log.levels.WARN)
          return
        end
        for _, item in ipairs(selected) do
          vim.fn.system("task add " .. vim.fn.shellescape(item.text) .. " +code")
        end
        vim.notify(#selected .. " tasks created from TODO comments", vim.log.levels.INFO)
        sl_refresh()
        actions.close(bufnr)
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
    { "<leader>ts", scan_todos, desc = "Scan TODO Comments" },
  },
}
