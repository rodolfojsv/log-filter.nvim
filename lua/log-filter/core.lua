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
  
  -- Sort history in descending order
  table.sort(history, function(a, b) return a > b end)
  
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
  
  -- For each matching line, include full context block (from previous empty line to next empty line)
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
      
      -- Walk forwards until we hit an empty line or end of file
      j = i + 1
      while j <= #lines do
        if lines[j]:match('^%s*$') then
          break
        end
        lines_to_include[j] = true
        j = j + 1
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
  -- Don't reload if this is already a filtered buffer - allow stacking filters
  -- (e.g., time filter followed by regex filter)
  
  -- Store original filename for reference
  local original_file = vim.b.log_filter_original_file or vim.api.nvim_buf_get_name(0)
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
    
    -- Parse existing headers BEFORE reload to preserve accumulated patterns
    local existing_filter_patterns = {}
    local existing_exclude_patterns = {}
    local existing_time_section = {}
    
    if vim.bo.buftype == 'acwrite' then
      local current_lines = vim.api.nvim_buf_get_lines(0, 0, 100, false)
      for _, line in ipairs(current_lines) do
        if line:match('^Filter:%s*(.+)') then
          local filter_pattern = line:match('^Filter:%s*(.+)')
          table.insert(existing_filter_patterns, filter_pattern)
        elseif line:match('^Exclude:%s*(.+)') then
          local exclude_pattern = line:match('^Exclude:%s*(.+)')
          table.insert(existing_exclude_patterns, exclude_pattern)
        elseif line:match('^From:%s*(.+)') or line:match('^To:%s*(.+)') then
          table.insert(existing_time_section, line)
        elseif line:match('^%-+$') then
          break  -- End of headers
        end
      end
    end
    
    -- If we have an original file stored and this is a filtered buffer, reload it first
    -- UNLESS it's time-filtered, in which case we want to keep the time-filtered content
    local was_filtered = vim.bo.buftype == 'acwrite'
    local is_time_filtered = vim.b.log_filter_is_time_filtered
    if was_filtered and original_file and vim.fn.filereadable(original_file) == 1 and not is_time_filtered then
      -- Reload original file
      vim.cmd('edit! ' .. vim.fn.fnameescape(original_file))
      -- Restore original file tracking
      vim.b.log_filter_original_file = original_file
    end
    
    -- Get all lines (now from reloaded base content)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    
    -- Find where headers end (scan for header patterns)
    local header_end = 0
    local in_file_list = false
    
    for i = 1, math.min(100, #lines) do
      local line = lines[i]
      
      -- Track if we're in the file list section
      if line:match('^Original files:') then
        in_file_list = true
        header_end = i
      elseif in_file_list and (line:match('^From:') or line:match('^Filter:') or line:match('^Exclude:') or line:match('^Combined Regex:') or line:match('^%-+$')) then
        -- Exiting file list section
        in_file_list = false
        header_end = i
      elseif in_file_list or line:match('^Original file:') or line:match('^From:') or 
             line:match('^To:') or line:match('^Filter:') or line:match('^Exclude:') or
             line:match('^Combined Regex:') or line == '' or line:match('^%-+$') then
        header_end = i
      else
        -- Hit actual content
        break
      end
    end
    
    local matching_lines
    
    -- Extract existing headers to get patterns
    local header_lines = {}
    for i = 1, header_end do
      table.insert(header_lines, lines[i])
    end
    
    -- Parse existing headers into sections (use pre-reload patterns if available)
    local original_files_section = {}
    local time_section = existing_time_section  -- Use preserved time section
    local filter_patterns = existing_filter_patterns  -- Use preserved patterns
    local exclude_patterns = existing_exclude_patterns  -- Use preserved patterns
    
    local in_files_list = false
    for _, line in ipairs(header_lines) do
      if line:match('^Original file:') or line:match('^Original files:') then
        table.insert(original_files_section, line)
        in_files_list = line:match('^Original files:') ~= nil
      elseif in_files_list and not line:match('^From:') and not line:match('^To:') and not line:match('^Filter:') and not line:match('^Exclude:') and line ~= '' and not line:match('^%-+$') then
        -- This is part of the file list
        table.insert(original_files_section, line)
      elseif #existing_time_section == 0 and (line:match('^From:') or line:match('^To:')) then
        -- Only parse time section from file if we didn't preserve one from before reload
        in_files_list = false
        table.insert(time_section, line)
      end
      -- Note: Filter/Exclude patterns already extracted before reload
    end
    
    -- Add new pattern to the filter list
    table.insert(filter_patterns, pattern)
    
    -- Build filter pattern (just positive filters)
    local combined_filter = table.concat(filter_patterns, '|')
    
    -- Try ripgrep first for speed (if file is saved)
    local matching_lines
    if has_ripgrep() then
      matching_lines = filter_with_ripgrep(combined_filter, lines, current_line_num)
    end
    
    -- Fallback to Vim regex if ripgrep failed or not available
    if not matching_lines then
      matching_lines = {}
      local clean_pattern = combined_filter:gsub('^%((.*)%)$', '%1')
      local vim_pattern = '\v' .. clean_pattern
      
      for i, line in ipairs(lines) do
        if vim.fn.match(line, vim_pattern) ~= -1 then
          matching_lines[i] = true
        end
      end
    end
    
    -- Remove any matches in the header section
    for i = 1, header_end do
      matching_lines[i] = nil
    end
    
    -- Check if we found any matches
    if vim.tbl_count(matching_lines) == 0 then
      vim.notify('No matching lines found!', vim.log.levels.WARN)
      return
    end
    
    -- Build context blocks from content lines only (after headers)
    -- Create a subset of lines starting after headers
    local content_lines = {}
    local content_matching = {}
    
    for i = header_end + 1, #lines do
      table.insert(content_lines, lines[i])
      -- Map matching lines to new indices
      if matching_lines[i] then
        content_matching[i - header_end] = true
      end
    end
    
    -- Build context blocks from content
    local result_lines, line_mapping, match_count = build_context_blocks(content_lines, content_matching, current_line_num)
    
    -- If we have exclude patterns, filter out entire blocks that contain excluded text
    if #exclude_patterns > 0 then
      local combined_exclude = table.concat(exclude_patterns, '|')
      local clean_exclude = combined_exclude:gsub('^%((.*)%)$', '%1')
      local vim_exclude_pattern = '\v' .. clean_exclude
      
      -- Find blocks to exclude by scanning for empty line separators
      local filtered_result = {}
      local current_block = {}
      local block_has_exclude = false
      
      for _, line in ipairs(result_lines) do
        if line == '' then
          -- End of block - add it if not excluded
          if #current_block > 0 and not block_has_exclude then
            for _, block_line in ipairs(current_block) do
              table.insert(filtered_result, block_line)
            end
            table.insert(filtered_result, '')  -- Add separator
          end
          current_block = {}
          block_has_exclude = false
        else
          table.insert(current_block, line)
          -- Check if this line matches exclude pattern
          if vim.fn.match(line, vim_exclude_pattern) ~= -1 then
            block_has_exclude = true
          end
        end
      end
      
      -- Don't forget last block
      if #current_block > 0 and not block_has_exclude then
        for _, block_line in ipairs(current_block) do
          table.insert(filtered_result, block_line)
        end
      end
      
      result_lines = filtered_result
      
      -- Recalculate match count
      local block_count = 0
      for _, line in ipairs(result_lines) do
        if line == '' then
          block_count = block_count + 1
        end
      end
      match_count = block_count
      
      -- Check if we excluded everything
      if #result_lines == 0 then
        vim.notify('All matching entries were excluded!', vim.log.levels.WARN)
        return
      end
    end
    
    -- Build final pattern for display
    local final_pattern
    if #exclude_patterns > 0 then
      local exclude_part = table.concat(exclude_patterns, '|')
      final_pattern = '^(?!.*(' .. exclude_part .. ')).*(' .. combined_filter .. ')'
    else
      final_pattern = combined_filter
    end
    
    -- Build final header in correct order
    local final_header_lines = {}
    
    -- 1. Original files section (always first)
    if #original_files_section > 0 then
      for _, line in ipairs(original_files_section) do
        table.insert(final_header_lines, line)
      end
    else
      table.insert(final_header_lines, 'Original file: ' .. original_name)
    end
    
    -- 2. Time section (if any)
    if #time_section > 0 then
      table.insert(final_header_lines, '')
      for _, line in ipairs(time_section) do
        table.insert(final_header_lines, line)
      end
    end
    
    -- 3. Filter section (each pattern on its own line)
    if #filter_patterns > 0 then
      table.insert(final_header_lines, '')
      for _, filter_pattern in ipairs(filter_patterns) do
        table.insert(final_header_lines, 'Filter: ' .. filter_pattern)
      end
    end
    
    -- 4. Exclude section (each pattern on its own line)
    if #exclude_patterns > 0 then
      table.insert(final_header_lines, '')
      for _, exclude_pattern in ipairs(exclude_patterns) do
        table.insert(final_header_lines, 'Exclude: ' .. exclude_pattern)
      end
    end
    
    -- 5. Combined regex for debugging
    table.insert(final_header_lines, '')
    table.insert(final_header_lines, 'Combined Regex: ' .. final_pattern)
    
    -- 6. One separator at the end
    table.insert(final_header_lines, '')
    table.insert(final_header_lines, string.rep('-', 80))
    table.insert(final_header_lines, '')
    
    -- Combine headers with filtered content
    local final_lines = {}
    for _, line in ipairs(final_header_lines) do
      table.insert(final_lines, line)
    end
    for _, line in ipairs(result_lines) do
      table.insert(final_lines, line)
    end
    
    -- Set winbar to show filter at top of window (stays fixed while scrolling)
    vim.wo.winbar = '%#Comment#' .. final_pattern .. ' %#Normal#' .. string.rep('─', 40)
    
    -- Replace buffer contents with matching lines
    vim.api.nvim_buf_set_lines(0, 0, -1, false, final_lines)
    
    -- Make buffer not directly saveable to prevent overwriting original
    vim.bo.buftype = 'acwrite'
    vim.bo.modified = false
    
    -- Store original file path for save-as functionality
    vim.b.log_filter_original_file = original_file
    
    -- Preserve time-filtered flag if it was set
    if is_time_filtered then
      vim.b.log_filter_is_time_filtered = true
    end
    
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

function FilterLogNegated()
  -- Store original filename for reference
  local original_file = vim.b.log_filter_original_file or vim.api.nvim_buf_get_name(0)
  local original_name = vim.fn.fnamemodify(original_file, ':t')
  
  -- Save current line and position to restore after filtering
  local current_line = vim.api.nvim_get_current_line()
  local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
  
  local function do_exclude(pattern)
    if not pattern or pattern == '' then
      return
    end

    -- Save pattern to history
    add_to_history(pattern)
    
    -- Parse existing headers BEFORE reload to preserve accumulated patterns
    local existing_filter_patterns = {}
    local existing_exclude_patterns = {}
    local existing_time_section = {}
    
    if vim.bo.buftype == 'acwrite' then
      local current_lines = vim.api.nvim_buf_get_lines(0, 0, 100, false)
      for _, line in ipairs(current_lines) do
        if line:match('^Filter:%s*(.+)') then
          local filter_pattern = line:match('^Filter:%s*(.+)')
          table.insert(existing_filter_patterns, filter_pattern)
        elseif line:match('^Exclude:%s*(.+)') then
          local exclude_pattern = line:match('^Exclude:%s*(.+)')
          table.insert(existing_exclude_patterns, exclude_pattern)
        elseif line:match('^From:%s*(.+)') or line:match('^To:%s*(.+)') then
          table.insert(existing_time_section, line)
        elseif line:match('^%-+$') then
          break  -- End of headers
        end
      end
    end
    
    -- If we have an original file stored and this is a filtered buffer, reload it first
    -- UNLESS it's time-filtered, in which case we want to keep the time-filtered content
    local was_filtered = vim.bo.buftype == 'acwrite'
    local is_time_filtered = vim.b.log_filter_is_time_filtered
    if was_filtered and original_file and vim.fn.filereadable(original_file) == 1 and not is_time_filtered then
      -- Reload original file
      vim.cmd('edit! ' .. vim.fn.fnameescape(original_file))
      -- Restore original file tracking
      vim.b.log_filter_original_file = original_file
    end
    
    -- Get all lines (now from reloaded base content)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    
    -- Find where headers end
    local header_end = 0
    local in_file_list = false
    
    for i = 1, math.min(100, #lines) do
      local line = lines[i]
      
      if line:match('^Original files:') then
        in_file_list = true
        header_end = i
      elseif in_file_list and (line:match('^From:') or line:match('^Filter:') or line:match('^Exclude:') or line:match('^Combined Regex:') or line:match('^%-+$')) then
        in_file_list = false
        header_end = i
      elseif in_file_list or line:match('^Original file:') or line:match('^From:') or 
             line:match('^To:') or line:match('^Filter:') or line:match('^Exclude:') or
             line:match('^Combined Regex:') or line == '' or line:match('^%-+$') then
        header_end = i
      else
        break
      end
    end
    
    -- Extract existing headers
    local header_lines = {}
    for i = 1, header_end do
      table.insert(header_lines, lines[i])
    end
    
    -- Parse existing headers (use pre-reload patterns if available)
    local original_files_section = {}
    local time_section = existing_time_section  -- Use preserved time section
    local filter_patterns = existing_filter_patterns  -- Use preserved patterns
    local exclude_patterns = existing_exclude_patterns  -- Use preserved patterns
    
    local in_files_list = false
    for _, line in ipairs(header_lines) do
      if line:match('^Original file:') or line:match('^Original files:') then
        table.insert(original_files_section, line)
        in_files_list = line:match('^Original files:') ~= nil
      elseif in_files_list and not line:match('^From:') and not line:match('^To:') and not line:match('^Filter:') and not line:match('^Exclude:') and line ~= '' and not line:match('^%-+$') then
        table.insert(original_files_section, line)
      elseif #existing_time_section == 0 and (line:match('^From:') or line:match('^To:')) then
        -- Only parse time section from file if we didn't preserve one from before reload
        in_files_list = false
        table.insert(time_section, line)
      end
      -- Note: Filter/Exclude patterns already extracted before reload
    end
    
    -- Add new pattern to exclude list
    table.insert(exclude_patterns, pattern)
    
    -- Start with all content or filtered content
    local matching_lines = {}
    
    if #filter_patterns > 0 then
      -- Apply positive filters
      local combined_filter = table.concat(filter_patterns, '|')
      
      if has_ripgrep() then
        matching_lines = filter_with_ripgrep(combined_filter, lines, current_line_num)
      end
      
      if not matching_lines then
        matching_lines = {}
        local clean_pattern = combined_filter:gsub('^%((.*)%)$', '%1')
        local vim_pattern = '\v' .. clean_pattern
        
        for i, line in ipairs(lines) do
          if vim.fn.match(line, vim_pattern) ~= -1 then
            matching_lines[i] = true
          end
        end
      end
    else
      -- No positive filters, start with all content lines
      for i = header_end + 1, #lines do
        matching_lines[i] = true
      end
    end
    
    -- Check if we have any results
    if vim.tbl_count(matching_lines) == 0 then
      vim.notify('All lines were excluded!', vim.log.levels.WARN)
      return
    end
    
    -- Build context blocks
    local content_lines = {}
    local content_matching = {}
    
    for i = header_end + 1, #lines do
      table.insert(content_lines, lines[i])
      if matching_lines[i] then
        content_matching[i - header_end] = true
      end
    end
    
    local result_lines, line_mapping, match_count = build_context_blocks(content_lines, content_matching, current_line_num)
    
    -- Filter out entire blocks that contain excluded text
    local combined_exclude = table.concat(exclude_patterns, '|')
    local clean_exclude = combined_exclude:gsub('^%((.*)%)$', '%1')
    local vim_exclude_pattern = '\\v' .. clean_exclude
    
    -- Find blocks to exclude by scanning for empty line separators
    local filtered_result = {}
    local current_block = {}
    local block_has_exclude = false
    
    for _, line in ipairs(result_lines) do
      if line == '' then
        -- End of block - add it if not excluded
        if #current_block > 0 and not block_has_exclude then
          for _, block_line in ipairs(current_block) do
            table.insert(filtered_result, block_line)
          end
          table.insert(filtered_result, '')  -- Add separator
        end
        current_block = {}
        block_has_exclude = false
      else
        table.insert(current_block, line)
        -- Check if this line matches exclude pattern
        if vim.fn.match(line, vim_exclude_pattern) ~= -1 then
          block_has_exclude = true
        end
      end
    end
    
    -- Don't forget last block
    if #current_block > 0 and not block_has_exclude then
      for _, block_line in ipairs(current_block) do
        table.insert(filtered_result, block_line)
      end
    end
    
    result_lines = filtered_result
    
    -- Recalculate match count
    local block_count = 0
    for _, line in ipairs(result_lines) do
      if line == '' then
        block_count = block_count + 1
      end
    end
    match_count = block_count
    
    -- Check if all entries were excluded
    if #result_lines == 0 then
      vim.notify('All entries were excluded!', vim.log.levels.WARN)
      return
    end
    
    -- Build final pattern for display
    local final_pattern
    if #filter_patterns > 0 then
      local filter_part = table.concat(filter_patterns, '|')
      local exclude_part = table.concat(exclude_patterns, '|')
      final_pattern = '^(?!.*(' .. exclude_part .. ')).*(' .. filter_part .. ')'
    else
      local exclude_part = table.concat(exclude_patterns, '|')
      final_pattern = '^(?!.*(' .. exclude_part .. ')).*'
    end
    
    -- Build final header
    local final_header_lines = {}
    
    -- 1. Original files section
    if #original_files_section > 0 then
      for _, line in ipairs(original_files_section) do
        table.insert(final_header_lines, line)
      end
    else
      table.insert(final_header_lines, 'Original file: ' .. original_name)
    end
    
    -- 2. Time section
    if #time_section > 0 then
      table.insert(final_header_lines, '')
      for _, line in ipairs(time_section) do
        table.insert(final_header_lines, line)
      end
    end
    
    -- 3. Filter section
    if #filter_patterns > 0 then
      table.insert(final_header_lines, '')
      for _, filter_pattern in ipairs(filter_patterns) do
        table.insert(final_header_lines, 'Filter: ' .. filter_pattern)
      end
    end
    
    -- 4. Exclude section
    table.insert(final_header_lines, '')
    for _, exclude_pattern in ipairs(exclude_patterns) do
      table.insert(final_header_lines, 'Exclude: ' .. exclude_pattern)
    end
    
    -- 5. Combined regex for debugging
    table.insert(final_header_lines, '')
    table.insert(final_header_lines, 'Combined Regex: ' .. final_pattern)
    
    -- 6. Separator
    table.insert(final_header_lines, '')
    table.insert(final_header_lines, string.rep('-', 80))
    table.insert(final_header_lines, '')
    
    -- Combine
    local final_lines = {}
    for _, line in ipairs(final_header_lines) do
      table.insert(final_lines, line)
    end
    for _, line in ipairs(result_lines) do
      table.insert(final_lines, line)
    end
    
    -- Set winbar
    vim.wo.winbar = '%#Comment#' .. final_pattern .. ' %#Normal#' .. string.rep('─', 40)
    
    -- Update buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, final_lines)
    vim.bo.buftype = 'acwrite'
    vim.bo.modified = false
    vim.b.log_filter_original_file = original_file
    
    -- Preserve time-filtered flag if it was set
    if is_time_filtered then
      vim.b.log_filter_is_time_filtered = true
    end
    
    -- Position cursor
    local found_exact = false
    for i, line in ipairs(result_lines) do
      if line == current_line then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        found_exact = true
        break
      end
    end
    
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
  
  -- Call history selector
  show_history_selector(function(pattern)
    if not pattern or pattern == '' then
      return
    end
    
    do_exclude(pattern)
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
  
  -- Remove any existing .filtered, .compound, .timestamp extensions from original_file to get base name
  local base_file = original_file:gsub('%.filtered.*$', ''):gsub('%.compound$', ''):gsub('%.timestamp$', '')
  
  -- The target filtered file (always .filtered, no other extensions)
  local filtered_file = base_file .. '.filtered'
  
  -- Check if filtered file already exists
  if vim.fn.filereadable(filtered_file) == 1 then
    -- Find the next available .old_N suffix
    local old_num = 1
    local old_file = filtered_file .. '.old_' .. old_num
    
    while vim.fn.filereadable(old_file) == 1 do
      old_num = old_num + 1
      old_file = filtered_file .. '.old_' .. old_num
    end
    
    -- Rename existing .filtered to .old_N
    local success = vim.fn.rename(filtered_file, old_file)
  end
  
  -- Get current content before modifying buffer settings
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Temporarily change buftype to allow writing
  vim.bo.buftype = ''
  vim.cmd('write! ' .. vim.fn.fnameescape(filtered_file))
  
  -- Restore buftype to acwrite to keep it as a filtered buffer
  vim.bo.buftype = 'acwrite'
  vim.bo.modified = false
  
  -- Update the buffer name to the new file
  vim.api.nvim_buf_set_name(0, filtered_file)
  
  -- Preserve the original file reference for potential further filtering
  vim.b.log_filter_original_file = original_file
  
  vim.notify('Saved to: ' .. filtered_file, vim.log.levels.INFO)
end

function UndoFilter()
  -- Save current line content to search for after reload
  local current_line = vim.api.nvim_get_current_line()
  local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
  
  -- Clear the winbar filter display
  vim.wo.winbar = ''
  
  -- Clear any stored filter patterns
  vim.b.log_filter_patterns = nil
  
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

-- Parse timestamp from a log line (format: "2025-12-16 12:29:08.849")
-- Returns: timestamp string or nil if not found
local function parse_timestamp(line)
  -- Match timestamp pattern: YYYY-MM-DD HH:MM:SS.mmm
  local timestamp = line:match('^%s*(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d%.%d+)')
  return timestamp
end

-- Compare two timestamps (returns -1 if a < b, 0 if equal, 1 if a > b)
local function compare_timestamps(ts_a, ts_b)
  if not ts_a and not ts_b then return 0 end
  if not ts_a then return 1 end  -- Lines without timestamps go to the end
  if not ts_b then return -1 end
  
  if ts_a < ts_b then return -1 end
  if ts_a > ts_b then return 1 end
  return 0
end

-- Parse lines into log entry blocks (multi-line entries grouped by timestamp)
local function parse_log_entries(lines)
  local entries = {}
  local current_entry = nil
  
  for i, line in ipairs(lines) do
    local timestamp = parse_timestamp(line)
    
    if timestamp then
      -- Start a new log entry
      if current_entry then
        table.insert(entries, current_entry)
      end
      current_entry = {
        timestamp = timestamp,
        lines = {line}
      }
    else
      -- Continuation of current entry (or orphan line at start)
      if current_entry then
        table.insert(current_entry.lines, line)
      else
        -- Orphan line at the start without a timestamp - create entry without timestamp
        current_entry = {
          timestamp = nil,
          lines = {line}
        }
      end
    end
  end
  
  -- Don't forget the last entry
  if current_entry then
    table.insert(entries, current_entry)
  end
  
  return entries
end

-- Check if file has a compressed extension
local function is_compressed_file(filepath)
  local compressed_extensions = {'.zip', '.gz', '.tar.gz', '.tgz', '.7z', '.bz2', '.tar.bz2', '.xz', '.tar.xz'}
  local filename = filepath:lower()
  
  for _, ext in ipairs(compressed_extensions) do
    if filename:sub(-#ext) == ext then
      return true, ext
    end
  end
  
  return false, nil
end

-- Check if file is compressed and return the decompression command if available
local function get_decompress_command(filepath)
  if not config.decompress_commands then
    return nil, nil
  end
  
  local filename = filepath:lower()
  
  -- Check for multi-part extensions first (e.g., .tar.gz)
  for ext, cmd in pairs(config.decompress_commands) do
    if filename:sub(-#ext) == ext:lower() then
      return cmd, ext
    end
  end
  
  return nil, nil
end

-- Read file content, decompressing if needed
local function read_file_content(filepath)
  -- First check if file is compressed
  local is_compressed, ext = is_compressed_file(filepath)
  
  if is_compressed then
    -- Check if we have a decompression command configured
    local decompress_cmd = get_decompress_command(filepath)
    
    if not decompress_cmd then
      return nil, 'Compressed file (' .. ext .. ') detected but decompress_commands not configured. Please set up decompress_commands in your config.'
    end
    
    -- Format the command with the filepath
    -- Escape the filepath for Windows command line
    local escaped_filepath = filepath:gsub('"', '""')
    local cmd = string.format(decompress_cmd, escaped_filepath)
    
    -- On Windows, wrap the command with cmd /c to ensure proper parsing
    if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
      cmd = 'cmd /c "' .. cmd .. '"'
    end
    
    -- Decompress the file
    local handle = io.popen(cmd .. ' 2>&1')  -- Capture stderr too
    if not handle then
      return nil, 'Failed to run decompression command'
    end
    
    local output = handle:read('*all')
    local success = handle:close()
    
    -- Split output into lines
    local lines = {}
    for line in output:gmatch('[^\r\n]+') do
      table.insert(lines, line)
    end
    
    if #lines == 0 then
      return nil, 'Decompression command returned no data'
    end
    
    -- Check if output looks like 7zip status messages instead of file content
    local first_line = lines[1] or ''
    if first_line:match('^7%-Zip') or first_line:match('^Extracting') or first_line:match('^Everything is Ok') then
      return nil, 'Decompression command returned status messages instead of file content. Try using: 7z e -so "%%s" | findstr "."'
    end
    
    return lines, nil
  else
    -- Regular file read
    local file = io.open(filepath, 'r')
    if not file then
      return nil, 'Failed to read file'
    end
    
    local lines = {}
    for line in file:lines() do
      table.insert(lines, line)
    end
    file:close()
    
    return lines, nil
  end
end

-- Merge lines from new file into current buffer in chronological order
local function merge_lines_chronologically(current_lines, new_lines)
  -- Parse both sets of lines into log entry blocks
  local current_entries = parse_log_entries(current_lines)
  local new_entries = parse_log_entries(new_lines)
  
  -- Combine all entries
  local all_entries = {}
  for _, entry in ipairs(current_entries) do
    table.insert(all_entries, entry)
  end
  for _, entry in ipairs(new_entries) do
    table.insert(all_entries, entry)
  end
  
  -- Sort entries by timestamp
  table.sort(all_entries, function(a, b)
    return compare_timestamps(a.timestamp, b.timestamp) < 0
  end)
  
  -- Flatten entries back into lines with empty lines between entries
  local merged_lines = {}
  for i, entry in ipairs(all_entries) do
    -- Add empty line before entry (except first entry)
    if i > 1 then
      table.insert(merged_lines, '')
    end
    
    -- Add all lines from the entry
    for _, line in ipairs(entry.lines) do
      table.insert(merged_lines, line)
    end
  end
  
  return merged_lines
end

function AddLogFile()
  -- Use vim.ui.select to choose files (supports telescope if available)
  local has_telescope, telescope_builtin = pcall(require, 'telescope.builtin')
  
  if has_telescope then
    -- Use telescope's file picker for better UX (supports multi-select)
    local conf = require('telescope.config').values
    telescope_builtin.find_files({
      prompt_title = 'Select log file(s) to add (use ' .. config.multi_select_key .. ' to multi-select)',
      file_ignore_patterns = {},  -- Don't filter out any files (including .zip, .gz, etc.)
      file_sorter = require('telescope.sorters').get_fuzzy_file({ sorting_strategy = 'descending' }),
      attach_mappings = function(prompt_bufnr, map)
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        
        -- Map the configured key for multi-select
        map('i', config.multi_select_key, actions.toggle_selection + actions.move_selection_worse)
        map('n', config.multi_select_key, actions.toggle_selection + actions.move_selection_worse)
        
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()
          actions.close(prompt_bufnr)
          
          -- If no multi-selection, use single selection
          if #selections == 0 then
            local selection = action_state.get_selected_entry()
            if selection then
              selections = {selection}
            end
          end
          
          if #selections == 0 then
            return
          end
          
          -- Get current buffer info
          local original_file = vim.b.log_filter_original_file or vim.api.nvim_buf_get_name(0)
          local original_name = vim.fn.fnamemodify(original_file, ':t')
          
          -- Get current buffer lines and strip empty lines to avoid duplication
          local current_lines_raw = vim.api.nvim_buf_get_lines(0, 0, -1, false)
          local current_lines = {}
          for _, line in ipairs(current_lines_raw) do
            if line ~= '' then
              table.insert(current_lines, line)
            end
          end
          
          local success_count = 0
          local added_files = {}
          
          -- Add original file to the list if it has content
          if #current_lines > 0 and original_name ~= '' then
            table.insert(added_files, original_name)
          end
          
          -- Process each selected file
          for _, selection in ipairs(selections) do
            local filepath = selection.path or selection[1]
            
            -- Read the file (with decompression if needed)
            local new_lines_raw, err = read_file_content(filepath)
            
            if new_lines_raw then
              -- Strip empty lines from new file to avoid duplication when merging
              local new_lines = {}
              for _, line in ipairs(new_lines_raw) do
                if line ~= '' then
                  table.insert(new_lines, line)
                end
              end
              
              -- Merge chronologically with accumulated lines
              current_lines = merge_lines_chronologically(current_lines, new_lines)
              
              -- Strip empty lines from result to prepare for next merge
              local stripped_lines = {}
              for _, line in ipairs(current_lines) do
                if line ~= '' then
                  table.insert(stripped_lines, line)
                end
              end
              current_lines = stripped_lines
              
              success_count = success_count + 1
              table.insert(added_files, vim.fn.fnamemodify(filepath, ':t'))
              
              vim.notify('Added ' .. vim.fn.fnamemodify(filepath, ':t') .. ' (' .. #new_lines_raw .. ' lines)', vim.log.levels.INFO)
            else
              vim.notify(err or ('Failed to read: ' .. filepath), vim.log.levels.ERROR)
            end
          end
          
          -- After all merges are complete, do one final merge to add proper spacing
          if success_count > 0 then
            current_lines = merge_lines_chronologically(current_lines, {})
          end
          
          -- Only update buffer and show merged message if we successfully added files
          if success_count > 0 then
            -- Temporarily reset buftype to allow editing
            local original_buftype = vim.bo.buftype
            vim.bo.buftype = ''
            
            -- Prepend header with list of files added
            local header_lines = {}
            table.insert(header_lines, 'Original files:')
            for _, filename in ipairs(added_files) do
              table.insert(header_lines, filename)
            end
            table.insert(header_lines, '')
            table.insert(header_lines, string.rep('-', 80))
            table.insert(header_lines, '')
            
            -- Combine header with content
            local final_lines = {}
            for _, line in ipairs(header_lines) do
              table.insert(final_lines, line)
            end
            for _, line in ipairs(current_lines) do
              table.insert(final_lines, line)
            end
            
            -- Update buffer contents
            vim.api.nvim_buf_set_lines(0, 0, -1, false, final_lines)
            
            -- Mark buffer as compound and store original name
            local original_file = vim.b.log_filter_original_file or vim.api.nvim_buf_get_name(0)
            vim.b.log_filter_original_file = original_file
            vim.b.log_filter_is_compound = true
            
            -- Update buffer name to include .compound
            local current_name = vim.api.nvim_buf_get_name(0)
            if current_name ~= '' and not current_name:match('%.compound') then
              local base_name = vim.fn.fnamemodify(current_name, ':t:r')
              local new_name = base_name .. '.compound'
              pcall(vim.api.nvim_buf_set_name, 0, new_name)
            end
            
            -- Restore buftype if it was set
            if original_buftype ~= '' then
              vim.bo.buftype = original_buftype
            end
            
            vim.bo.modified = false
            vim.notify('Merged ' .. success_count .. ' file(s): ' .. table.concat(added_files, ', '), vim.log.levels.INFO)
          end
        end)
        
        return true
      end,
    })
  else
    -- Fallback: use vim.ui.input to get file path
    vim.ui.input({
      prompt = 'Enter log file path: ',
      completion = 'file',
    }, function(filepath)
      if not filepath or filepath == '' then
        return
      end
      
      -- Read the file (with decompression if needed)
      local new_lines, err = read_file_content(filepath)
      if not new_lines then
        vim.notify(err or ('Failed to read: ' .. filepath), vim.log.levels.ERROR)
        return
      end
      
      -- Get current buffer lines
      local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      
      -- Merge chronologically
      local merged_lines = merge_lines_chronologically(current_lines, new_lines)
      
      -- Replace buffer contents with merged lines
      vim.api.nvim_buf_set_lines(0, 0, -1, false, merged_lines)
      vim.notify('Added ' .. vim.fn.fnamemodify(filepath, ':t'), vim.log.levels.INFO)
    end)
  end
end

function FilterByTime()
  -- Parse existing headers BEFORE anything else to preserve Filter/Exclude patterns
  local existing_filter_patterns = {}
  local existing_exclude_patterns = {}
  
  if vim.bo.buftype == 'acwrite' then
    local current_lines = vim.api.nvim_buf_get_lines(0, 0, 100, false)
    for _, line in ipairs(current_lines) do
      if line:match('^Filter:%s*(.+)') then
        local filter_pattern = line:match('^Filter:%s*(.+)')
        table.insert(existing_filter_patterns, filter_pattern)
      elseif line:match('^Exclude:%s*(.+)') then
        local exclude_pattern = line:match('^Exclude:%s*(.+)')
        table.insert(existing_exclude_patterns, exclude_pattern)
      elseif line:match('^%-+$') then
        break  -- End of headers
      end
    end
  end
  
  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  -- Find first and last timestamps for default values
  local first_timestamp = nil
  local last_timestamp = nil
  
  for _, line in ipairs(lines) do
    local timestamp = parse_timestamp(line)
    if timestamp then
      if not first_timestamp then
        first_timestamp = timestamp
      end
      last_timestamp = timestamp
    end
  end
  
  -- Get start time from user
  vim.ui.input({
    prompt = 'Enter start time (YYYY-MM-DD HH:MM:SS): ',
    default = first_timestamp or '',
  }, function(start_time)
    if not start_time or start_time == '' then
      return
    end
    
    -- Get end time from user
    vim.ui.input({
      prompt = 'Enter end time (YYYY-MM-DD HH:MM:SS): ',
      default = last_timestamp or '',
    }, function(end_time)
      if not end_time or end_time == '' then
        return
      end
      
      -- Store original file reference
      local original_file = vim.b.log_filter_original_file or vim.api.nvim_buf_get_name(0)
      local original_name = vim.fn.fnamemodify(original_file, ':t')
      
      -- Parse lines into log entry blocks
      local entries = parse_log_entries(lines)
      local filtered_entries = {}
      local match_count = 0
      
      -- Filter entries by time range
      for _, entry in ipairs(entries) do
        if entry.timestamp then
          -- Compare timestamp with start and end times
          if entry.timestamp >= start_time and entry.timestamp <= end_time then
            table.insert(filtered_entries, entry)
            match_count = match_count + 1
          end
        end
      end
      
      if match_count == 0 then
        vim.notify('No log entries found in time range!', vim.log.levels.WARN)
        return
      end
      
      -- Flatten entries back into lines
      local filtered_lines = {}
      for _, entry in ipairs(filtered_entries) do
        for _, line in ipairs(entry.lines) do
          table.insert(filtered_lines, line)
        end
      end
      
      -- Preserve existing headers and add time filter info
      local existing_headers = {}
      local existing_header_end = 0
      
      -- Check if buffer has existing headers to preserve
      if #lines > 0 then
        local i = 1
        local in_header = true
        while i <= #lines and in_header do
          local line = lines[i]
          -- Check if we've reached the actual log content (line with timestamp)
          local has_timestamp = parse_timestamp(line)
          if has_timestamp then
            -- We've hit the log content, stop here
            in_header = false
            existing_header_end = i - 1
          else
            -- Still in header section
            i = i + 1
          end
        end
        
        -- If we went through everything without finding a timestamp, use all lines as header
        if in_header then
          existing_header_end = #lines
        end
      end
      
      -- Extract existing headers (excluding old From/To lines and separators)
      if existing_header_end > 0 then
        for i = 1, existing_header_end do
          local line = lines[i]
          if not line:match('^From:') and not line:match('^To:') and not line:match('^Combined Regex:') and line ~= '' and not line:match('^%-+$') then
            table.insert(existing_headers, line)
          end
        end
      end
      
      -- Parse existing headers into sections (use pre-parsed patterns if available)
      local original_files_section = {}
      local filter_section = {}
      local exclude_section = {}
      
      local in_files_list = false
      for _, line in ipairs(existing_headers) do
        if line:match('^Original file:') or line:match('^Original files:') then
          table.insert(original_files_section, line)
          in_files_list = line:match('^Original files:') ~= nil
        elseif in_files_list and not line:match('^Filter:') and not line:match('^Exclude:') then
          -- This is part of the file list
          table.insert(original_files_section, line)
        elseif line:match('^Filter:') then
          in_files_list = false
          table.insert(filter_section, line)
        elseif line:match('^Exclude:') then
          in_files_list = false
          table.insert(exclude_section, line)
        end
      end
      
      -- Override with pre-parsed patterns if we had them
      if #existing_filter_patterns > 0 then
        filter_section = {}
        for _, pattern in ipairs(existing_filter_patterns) do
          table.insert(filter_section, 'Filter: ' .. pattern)
        end
      end
      
      if #existing_exclude_patterns > 0 then
        exclude_section = {}
        for _, pattern in ipairs(existing_exclude_patterns) do
          table.insert(exclude_section, 'Exclude: ' .. pattern)
        end
      end
      
      -- Build final header in correct order
      local header_lines = {}
      
      -- 1. Original files section (always first)
      if #original_files_section > 0 then
        for _, line in ipairs(original_files_section) do
          table.insert(header_lines, line)
        end
      else
        if original_name and original_name ~= '' then
          table.insert(header_lines, 'Original file: ' .. original_name)
        end
      end
      
      -- 2. Time section
      table.insert(header_lines, '')
      table.insert(header_lines, 'From: ' .. start_time)
      table.insert(header_lines, 'To: ' .. end_time)
      
      -- 3. Filter section (if any)
      if #filter_section > 0 then
        table.insert(header_lines, '')
        for _, line in ipairs(filter_section) do
          table.insert(header_lines, line)
        end
      end
      
      -- 4. Exclude section (if any)
      if #exclude_section > 0 then
        table.insert(header_lines, '')
        for _, line in ipairs(exclude_section) do
          table.insert(header_lines, line)
        end
      end
      
      -- 5. Combined regex (if we have filters or excludes)
      if #filter_section > 0 or #exclude_section > 0 then
        table.insert(header_lines, '')
        
        -- Extract patterns from sections to rebuild combined regex
        local filter_patterns = {}
        for _, line in ipairs(filter_section) do
          local pattern = line:match('^Filter:%s*(.+)')
          if pattern then
            table.insert(filter_patterns, pattern)
          end
        end
        
        local exclude_patterns = {}
        for _, line in ipairs(exclude_section) do
          local pattern = line:match('^Exclude:%s*(.+)')
          if pattern then
            table.insert(exclude_patterns, pattern)
          end
        end
        
        -- Build combined regex
        local combined_regex
        if #filter_patterns > 0 and #exclude_patterns > 0 then
          local filter_part = table.concat(filter_patterns, '|')
          local exclude_part = table.concat(exclude_patterns, '|')
          combined_regex = '^(?!.*(' .. exclude_part .. ')).*(' .. filter_part .. ')'
        elseif #filter_patterns > 0 then
          combined_regex = table.concat(filter_patterns, '|')
        elseif #exclude_patterns > 0 then
          local exclude_part = table.concat(exclude_patterns, '|')
          combined_regex = '^(?!.*(' .. exclude_part .. ')).*'
        end
        
        if combined_regex then
          table.insert(header_lines, 'Combined Regex: ' .. combined_regex)
        end
      end
      
      -- 6. One separator at the end
      table.insert(header_lines, '')
      table.insert(header_lines, string.rep('-', 80))
      table.insert(header_lines, '')
      
      -- Combine preserved headers with filtered content
      local final_lines = {}
      for _, line in ipairs(header_lines) do
        table.insert(final_lines, line)
      end
      for _, line in ipairs(filtered_lines) do
        table.insert(final_lines, line)
      end
      
      -- Set winbar to show time filter
      vim.wo.winbar = '%#Comment#Time: ' .. start_time .. ' → ' .. end_time .. ' %#Normal#' .. string.rep('─', 40)
      
      -- Replace buffer contents
      vim.api.nvim_buf_set_lines(0, 0, -1, false, final_lines)
      
      -- Make buffer not directly saveable
      vim.bo.buftype = 'acwrite'
      vim.bo.modified = false
      
      -- Store original file path and mark as time filtered
      vim.b.log_filter_original_file = original_file
      vim.b.log_filter_is_time_filtered = true
      
      vim.notify('Filtered to ' .. match_count .. ' entries in time range', vim.log.levels.INFO)
    end)
  end)
end
