-- plugin/log-filter.lua
-- User commands and keymaps

-- Create user commands
vim.api.nvim_create_user_command('LogFilter', FilterLog, {})
vim.api.nvim_create_user_command('LogShow', ShowMatchingLines, {})
vim.api.nvim_create_user_command('LogSaveFiltered', SaveFiltered, {})
vim.api.nvim_create_user_command('LogAdd', AddLogFile, {})
vim.api.nvim_create_user_command('LogFilterTime', FilterByTime, {})

-- Set up keymaps
vim.keymap.set('n', '<leader>lr', FilterLog, { desc = '[L]og filter with [r]egex' })
vim.keymap.set('n', '<leader>ls', ShowMatchingLines, { desc = '[L]og [s]how in analysis buffer' })
vim.keymap.set('n', '<leader>lw', SaveFiltered, { desc = '[L]og [w]rite filtered to file' })
vim.keymap.set('n', '<leader>la', AddLogFile, { desc = '[L]og [a]dd file(s) chronologically' })
vim.keymap.set('n', '<leader>lt', FilterByTime, { desc = '[L]og filter by [t]ime range' })

-- Keymap to undo filter (restore buffer)
vim.keymap.set('n', '<leader>lu', UndoFilter, { desc = '[L]og [u]ndo filter (reload)' })
