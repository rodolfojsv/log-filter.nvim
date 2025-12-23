-- log-filter/core.lua
-- Core filtering logic

-- Module configuration (set by init.lua)
local config = {}

function InitializeConfig(user_config)
  config = user_config
end

-- Check if ripgrep is available
local function has_ripgrep()
  return vim.fn.executable('rg') == 1
end

local function load_history()
  local file = io.open(config.history_file, 'r')
  if not file then
    return {}
  end
  
  local history = {}
  for line in file:lines() do
    if line and line ~= '' then
      table.insert(history, line)
    end
  end
  file:close()
  
  return history
end

local function save_history(history)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(config.history_file, ':h')
  vim.fn.mkdir(dir, 'p')
  
  local file = io.open(config.history_file, 'w')
  if not file then
    return
  end
  
  -- Save only up to MAX_HISTORY entries
  for i = 1, math.min(#history, config.max_history) do
    file:write(history[i] .. '\n')
  end
  file:close()
end

local function add_to_history(pattern)
  local history = load_history()
  
  -- Remove pattern if it already exists
  for i = #history, 1, -1 do
    if history[i] == pattern then
      table.remove(history, i)
    end
  end
  
  -- Add pattern to the front (most recent)
  table.insert(history, 1, pattern)
  
  -- Save updated history
  save_history(history)
end

local function show_history_selector(callback)
  local history = load_history()
  
  -- Check if telescope is available
  local has_telescope, pickers = pcall(require, 'telescope.pickers')
  local has_finders, finders = pcall(require, 'telescope.finders')
  local has_conf, conf = pcall(require, 'telescope.config')
  local has_actions, actions = pcall(require, 'telescope.actions')
  local has_action_state, action_state = pcall(require, 'telescope.actions.state')
  
  if has_telescope and has_finders and has_conf and has_actions and has_action_state then
    -- Use Telescope for a better UX
    local sorters = require('telescope.sorters')
    
    pickers.new({}, {
      prompt_title = 'Filter Regex (type new or select from history)',
      finder = finders.new_table({
        results = history,
      }),
      sorter = sorters.empty(),  -- Disable filtering so all history items always show
      default_text = '',  -- Start with empty prompt
      attach_mappings = function(prompt_bufnr, map)
        -- Add a mapping to "load" selected item into prompt for editing
        map('i', config.load_entry_key, function()
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            local picker = action_state.get_current_picker(prompt_bufnr)
            picker:set_prompt(selection.value)
          end
        end)
        
        -- Standard Ctrl+N/P for navigation (no auto-update)
        -- Let Telescope handle them normally
        
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          local prompt_text = picker:_get_prompt()
          actions.close(prompt_bufnr)
          
          -- If there's text in prompt, use it; otherwise use the selected entry
          local pattern
          if prompt_text and prompt_text ~= '' then
            pattern = prompt_text
          elseif selection and selection.value then
            pattern = selection.value
          end
          
          if pattern and pattern ~= '' then
            callback(pattern)
          end
        end)
        return true
      end,
    }):find()
  else
    -- Fallback: simple input with history as default
    local default_value = #history > 0 and history[1] or ''
    vim.ui.input({
      prompt = 'Filter regex pattern (use | for OR): ',
      default = default_value,
    }, function(pattern)
      if pattern and pattern ~= '' then
        callback(pattern)
      end
    end)
  end
end

-- Fast ripgrep-based matching for large files
local function filter_with_ripgrep(pattern, lines, current_line_num)
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == '' then
    return nil  -- Can't use ripgrep on unnamed buffers
  end
  
  -- Remove outer parentheses if present
  local clean_pattern = pattern:gsub('^%((.*)%)$', '%1')
  
  -- Run ripgrep to get matching line numbers
  local cmd = string.format('rg --line-number --no-heading --color=never -e "%s" "%s"', 
    clean_pattern:gsub('"', '\\"'), bufname)
  
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end
  
  local output = handle:read('*all')
  handle:close()
  
  -- Parse ripgrep output to get line numbers
  local matching_lines = {}
  for line_info in output:gmatch('[^\r\n]+') do
    local line_num = line_info:match('^(%d+):')
    if line_num then
      matching_lines[tonumber(line_num)] = true
    end
  end
  
  if vim.tbl_count(matching_lines) == 0 then
    return nil
  end
  
  return matching_lines
end

-- Build context blocks from matching line numbers
local function build_context_blocks(lines, matching_lines, current_line_num)
  local lines_to_include = {}
  local block_starts = {}
  local match_count = 0
  
  -- For each matching line, include context (lines above until empty line)
  for i = 1, #lines do
    if matching_lines[i] then
      match_count = match_count + 1
      lines_to_include[i] = true
      
      -- Walk backwards until we hit an empty line or start of file
      local j = i - 1
      local block_start = i
      while j >= 1 do
        if lines[j]:match('^%s*$') then
          break
        end
        lines_to_include[j] = true
        block_start = j
        j = j - 1
      end
      
      table.insert(block_starts, block_start)
    end
  end
  
  -- Collect all marked lines with blank lines between blocks
  local result_lines = {}
  local line_mapping = {}
  local last_block_start = nil
  local filtered_line_num = 0
  
  for i = 1, #lines do
    if lines_to_include[i] then
      -- Check if this is the start of a new block
      local is_block_start = false
      for _, block_start in ipairs(block_starts) do
        if i == block_start then
          is_block_start = true
          break
        end
      end
      
      -- Add blank line before new block (except first block)
      if is_block_start and last_block_start ~= nil then
        filtered_line_num = filtered_line_num + 1
        table.insert(result_lines, '')
      end
      
      if is_block_start then
        last_block_start = i
      end
      
      filtered_line_num = filtered_line_num + 1
      table.insert(result_lines, lines[i])
      line_mapping[i] = filtered_line_num
    end
  end
  
  return result_lines, line_mapping, match_count
end

function FilterLog()
  -- If this is a filtered buffer, reload it first to get original content
  if vim.b.log_filter_original_file then
    vim.cmd('edit!')
  end
  
  -- Store original filename for reference
  local original_file = vim.api.nvim_buf_get_name(0)
  local original_name = vim.fn.fnamemodify(original_file, ':t')
  
  -- Save current line and position to restore after filtering
  local current_line = vim.api.nvim_get_current_line()
  local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
  
  local function do_filter(pattern)
    if not pattern or pattern == '' then
      return
    end

    -- Save pattern to history
    add_to_history(pattern)
    
    -- Get all lines
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local matching_lines
    
    -- Try ripgrep first for speed (if file is saved)
    if has_ripgrep() then
      matching_lines = filter_with_ripgrep(pattern, lines, current_line_num)
    end
    
    -- Fallback to Vim regex if ripgrep failed or not available
    if not matching_lines then
      matching_lines = {}
      local clean_pattern = pattern:gsub('^%((.*)%)$', '%1')
      local vim_pattern = '\\v' .. clean_pattern
      
      for i, line in ipairs(lines) do
        if vim.fn.match(line, vim_pattern) ~= -1 then
          matching_lines[i] = true
        end
      end
    end
    
    -- Check if we found any matches
    if vim.tbl_count(matching_lines) == 0 then
      vim.notify('No matching lines found!', vim.log.levels.WARN)
      return
    end
    
    -- Build context blocks
    local result_lines, line_mapping, match_count = build_context_blocks(lines, matching_lines, current_line_num)
    
    -- Prepend header with original file and filter info
    table.insert(result_lines, 1, '')
    table.insert(result_lines, 1, string.rep('-', 80))
    table.insert(result_lines, 1, '')
    table.insert(result_lines, 1, 'Filter: ' .. pattern)
    table.insert(result_lines, 1, 'Original file: ' .. original_name)
    
    -- Set winbar to show filter at top of window (stays fixed while scrolling)
    vim.wo.winbar = '%#Comment#Filter: ' .. pattern .. ' %#Normal#' .. string.rep('─', 60)
    
    -- Replace buffer contents with matching lines
    vim.api.nvim_buf_set_lines(0, 0, -1, false, result_lines)
    
    -- Make buffer not directly saveable to prevent overwriting original
    vim.bo.buftype = 'acwrite'
    vim.bo.modified = false
    
    -- Store original file path for save-as functionality
    vim.b.log_filter_original_file = original_file
    
    -- Smart cursor positioning
    -- Try to find exact line match first
    local found_exact = false
    for i, line in ipairs(result_lines) do
      if line == current_line then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        found_exact = true
        break
      end
    end
    
    -- If exact match not found, find closest included line
    if not found_exact then
      local closest_line = nil
      local min_distance = math.huge
      
      for orig_line_num, filt_line_num in pairs(line_mapping) do
        local distance = math.abs(orig_line_num - current_line_num)
        if distance < min_distance then
          min_distance = distance
          closest_line = filt_line_num
        end
      end
      
      if closest_line then
        vim.api.nvim_win_set_cursor(0, {closest_line, 0})
      end
    end
  end
  
  -- Call history selector which will call do_filter
  show_history_selector(function(pattern)
    if not pattern or pattern == '' then
      return
    end
    
    -- Filter immediately with the pattern
    do_filter(pattern)
  end)
end

function ShowMatchingLines()
  -- Get current buffer content (should be already filtered)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local original_file = vim.b.log_filter_original_file
  local current_file = vim.api.nvim_buf_get_name(0)
  
  if not original_file then
    vim.notify('Not a filtered buffer - use logr first', vim.log.levels.WARN)
    return
  end
  
  local base_name = vim.fn.fnamemodify(original_file, ':t')
  local analysis_name = base_name .. ' [analysis]'
  
  -- Check if an analysis buffer already exists
  local existing_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match('%[analysis%]$') and vim.fn.fnamemodify(buf_name, ':t') == analysis_name then
        existing_buf = buf
        break
      end
    end
  end
  
  local buf
  if existing_buf then
    -- Reuse existing buffer and update its contents
    buf = existing_buf
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    -- Create new scratch buffer for analysis
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'acwrite')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    
    -- Set buffer name (safe now since we checked for existing)
    vim.api.nvim_buf_set_name(buf, analysis_name)
    
    -- Mark this as an analysis buffer
    vim.api.nvim_buf_set_var(buf, 'log_filter_original_file', original_file)
    vim.api.nvim_buf_set_var(buf, 'log_filter_is_analysis', true)
  end
  
  vim.api.nvim_buf_set_option(buf, 'modified', false)
  
  -- Split and show buffer
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
end

function SaveFiltered()
  local original_file = vim.b.log_filter_original_file
  if not original_file then
    vim.notify('Not a filtered buffer', vim.log.levels.WARN)
    return
  end
  
  -- Check if this is an analysis buffer
  local is_analysis = vim.b.log_filter_is_analysis
  local extension = is_analysis and '.filtered.analysis' or '.filtered'
  local filtered_file = original_file .. extension
  
  vim.bo.buftype = ''
  vim.cmd('write! ' .. vim.fn.fnameescape(filtered_file))
  vim.bo.buftype = 'acwrite'
  vim.notify('Saved to: ' .. filtered_file, vim.log.levels.INFO)
end

function UndoFilter()
  -- Save current line content to search for after reload
  local current_line = vim.api.nvim_get_current_line()
  local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
  
  -- Clear the winbar filter display
  vim.wo.winbar = ''
  
  -- Reload the buffer
  vim.cmd('edit!')
  
  -- Try to find the line we were on
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == current_line then
      -- Found the exact line, jump to it
      vim.api.nvim_win_set_cursor(0, {i, 0})
      return
    end
  end
  
  -- If exact line not found, stay at similar position
  local total_lines = vim.api.nvim_buf_line_count(0)
  if current_line_num <= total_lines then
    vim.api.nvim_win_set_cursor(0, {current_line_num, 0})
  end
end
