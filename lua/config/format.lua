-- Custom Python formatter for Smith project (Ruff via make)
local M = {}

function M.format_python_file()
  local cwd = vim.fn.getcwd()
  local file_path = vim.fn.expand('%:p')
  
  -- Only format if in Smith project
  if not vim.startswith(cwd, '/home/serallap/code/smith') then
    return false -- Let conform.nvim handle it
  end
  
  -- Get relative path from project root
  local rel_path = string.gsub(file_path, '^/home/serallap/code/smith/', '')
  
  -- Run make ruff.format in project root with relative path
  local cmd = string.format('cd /home/serallap/code/smith && make ruff.format ARGS="%s"', rel_path)
  local result = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify('Ruff format failed: ' .. result, vim.log.levels.ERROR)
    return false
  end
  
  -- Reload buffer to reflect changes
  vim.cmd('edit!')
  vim.notify('Python file formatted with Ruff', vim.log.levels.INFO)
  return true
end

return M