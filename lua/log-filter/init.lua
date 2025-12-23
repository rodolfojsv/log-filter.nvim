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
M.show_matching_lines = ShowMatchingLines
M.save_filtered = SaveFiltered
M.undo_filter = UndoFilter

return M
