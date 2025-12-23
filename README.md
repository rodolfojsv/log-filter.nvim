# log-filter.nvim

A powerful Neovim plugin for filtering log files using regex patterns with context inclusion and history management.

## Features

- **Regex-based filtering** with support for Vim patterns and ripgrep acceleration
- **Context inclusion** - automatically includes lines above matches until empty line
- **Pattern history** - saves and navigates through previously used regex patterns via Telescope
- **Smart cursor positioning** - maintains your position when filtering
- **Visual filter indicator** - shows active filter in winbar and buffer header
- **Analysis mode** - open filtered results in a separate buffer for editing
- **Save filtered results** - export to `.filtered` or `.filtered.analysis` files
- **Auto-reload** - automatically reloads original content before applying new filter

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'rodolfojsv/log-filter.nvim',
  config = function()
    require('log-filter').setup({
      history_file = 'C:/temp/nvim_log_filter_history.txt',  -- Path to store regex history
      max_history = 20,  -- Maximum number of history entries
      load_entry_key = '<C-e>',  -- Key to load selected history entry into prompt
    })
  end,
}
```

## Configuration

All options are optional and have sensible defaults:

```lua
require('log-filter').setup({
  -- Path to file storing regex pattern history
  history_file = vim.fn.stdpath('cache') .. '/log_filter_history.txt',
  
  -- Maximum number of regex patterns to store in history
  max_history = 20,
  
  -- Key mapping to load selected history entry into prompt for editing (in Telescope)
  load_entry_key = '<C-e>',
})
```

## Usage

### Commands

- `:LogFilter` - Open filter prompt with history
- `:LogShow` - Open filtered results in analysis buffer
- `:LogSaveFiltered` - Save filtered results to file

### Default Keymaps

- `<leader>logr` - **[R]**egex filter - Filter buffer with regex pattern
- `<leader>logs` - **[S]**how in analysis buffer - Open in editable buffer
- `<leader>logw` - **[W]**rite filtered - Save to file (`.filtered` or `.filtered.analysis`)
- `<leader>logu` - **[U]**ndo filter - Reload original buffer

### Workflow

1. **Filter a log file**: Press `<leader>logr`
   - Type a new regex pattern OR
   - Navigate history with Ctrl+N/Ctrl+P and press Enter OR
   - Navigate to an entry, press Ctrl+E to load it for editing

2. **Context inclusion**: Lines above each match are automatically included until an empty line is encountered

3. **Apply different filter**: Press `<leader>logr` again (automatically reloads original first)

4. **Analysis mode**: Press `<leader>logs` to open filtered content in a new buffer where you can edit it

5. **Save results**: Press `<leader>logw`
   - From main filter: saves as `originalfile.filtered`
   - From analysis buffer: saves as `originalfile.filtered.analysis`

6. **Return to original**: Press `<leader>logu` to reload the unfiltered file

### Example Regex Patterns

```
error|Error|ERROR|fail          # Match any error-related text
warn|WARN|warning               # Match warnings
\d{4}-\d{2}-\d{2}               # Match dates (YYYY-MM-DD)
192\.168\.                      # Match IP addresses starting with 192.168
exception.*occurred             # Match exception lines
```

### Recommended Keymaps

You can customize the keymaps in your config:

```lua
vim.keymap.set('n', '<leader>lf', '<cmd>LogFilter<CR>', { desc = '[L]og [F]ilter' })
vim.keymap.set('n', '<leader>la', '<cmd>LogShow<CR>', { desc = '[L]og [A]nalysis buffer' })
vim.keymap.set('n', '<leader>lw', '<cmd>LogSaveFiltered<CR>', { desc = '[L]og [W]rite filtered' })
vim.keymap.set('n', '<leader>lu', function()
  vim.wo.winbar = ''
  vim.cmd('edit!')
end, { desc = '[L]og [U]ndo filter' })
```

## Requirements

- Neovim >= 0.9.0
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for enhanced history selection
- Optional: [ripgrep](https://github.com/BurntSushi/ripgrep) for faster filtering on large files (500k+ lines)

## How It Works

1. **Pattern matching**: Uses Vim's `\v` (very magic) regex mode by default
2. **Ripgrep acceleration**: For saved files over 500k lines, automatically uses ripgrep if available
3. **Context blocks**: Each match triggers backward traversal to include context until empty line
4. **Block separation**: Blank lines separate different context blocks
5. **Buffer protection**: Filtered buffers are marked as `acwrite` to prevent accidental overwrites

## License

MIT

## Credits

Created by [Rodolfo Silva](https://github.com/rodolfojsv)
