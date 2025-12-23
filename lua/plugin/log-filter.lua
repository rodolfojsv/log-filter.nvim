-- plugin/log-filter.lua
-- User commands and keymaps

-- Create user commands
vim.api.nvim_create_user_command('LogFilter', FilterLog, {})
vim.api.nvim_create_user_command('LogShow', ShowMatchingLines, {})
vim.api.nvim_create_user_command('LogSaveFiltered', SaveFiltered, {})

-- Set up keymaps
vim.keymap.set('n', '<leader>logr', FilterLog, { desc = '[Log] Filter with [r]egex' })
vim.keymap.set('n', '<leader>logs', ShowMatchingLines, { desc = '[Log] [S]how in analysis buffer' })
vim.keymap.set('n', '<leader>logw', SaveFiltered, { desc = '[Log] [W]rite filtered to file' })

-- Keymap to undo filter (restore buffer)
vim.keymap.set('n', '<leader>logu', UndoFilter, { desc = '[Log] [U]ndo filter (reload)' })
