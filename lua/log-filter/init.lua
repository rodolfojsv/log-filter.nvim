-- log-filter/init.lua
-- Main entry point for log-filter.nvim

require('log-filter.core')
require('plugin.log-filter')

local M = {}

-- Default configuration
local defaults = {
  history_file = vim.fn.stdpath('cache') .. '/log_filter_history.txt',
  max_history = 20,
  load_entry_key = '<C-e>',
  multi_select_key = '<C-e>',
  -- Decompression commands (nil by default - user must configure)
  -- Example: decompress_commands = {
  --   ['.zip'] = '7z x -so "%s"',
  --   ['.gz'] = 'gzip -dc "%s"',
  --   ['.tar.gz'] = 'tar -xzOf "%s"',
  --   ['.7z'] = '7z x -so "%s"',
  -- }
  -- %s will be replaced with the file path
  decompress_commands = nil,
}

-- Module configuration (will be set by setup)
M.config = {}

function M.setup(options)
  -- Merge user options with defaults
  M.config = vim.tbl_deep_extend('force', defaults, options or {})
  
  -- Initialize the core module with config
  InitializeConfig(M.config)
end

-- Export functions for programmatic use
M.filter_log = FilterLog
M.filter_log_negated = FilterLogNegated
M.show_matching_lines = ShowMatchingLines
M.save_filtered = SaveFiltered
M.undo_filter = UndoFilter
M.add_log_file = AddLogFile
M.filter_by_time = FilterByTime

return M
