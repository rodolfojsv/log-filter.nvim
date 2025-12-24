# log-filter.nvim

A powerful Neovim plugin for filtering and analyzing log files with advanced multi-file support, time-based filtering, and smart exclusion patterns.

## Features

- **Multi-file chronological merging** - Combine multiple log files sorted by timestamp
- **Time-based filtering** - Filter logs by date/time range with preserved multi-line entries
- **Regex-based filtering** with OR logic - Stack multiple patterns with automatic reload
- **Smart exclusion** - Exclude entire log entry blocks matching patterns
- **Compressed file support** - Read .zip, .gz, .7z and other compressed formats
- **Context inclusion** - Automatically includes complete multi-line log entries
- **Pattern history** - Saves and navigates through previously used regex patterns via Telescope
- **Smart cursor positioning** - Maintains your position when filtering
- **Visual filter indicator** - Shows active filters in winbar and buffer header
- **Save filtered results** - Export with `.filtered` extension and automatic backup system
- **Auto-reload** - Automatically reloads original content before applying new filters

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
  
  -- Key for multi-selecting files in Telescope file picker
  multi_select_key = '<C-e>',
  
  -- Commands for decompressing various file formats
  -- %s will be replaced with the file path
  decompress_commands = {
    ['.zip'] = '7Filter with regex pattern (positive match)
- `:LogFilterNegated` - Exclude lines matching regex pattern
- `:LogFilterTime` - Filter by time range
- `:LogAdd` - Add and merge multiple log files chronologically
- `:LogShow` - Open filtered results in analysis buffer
- `:LogSaveFiltered` - Save filtered results to file

### Default Keymaps

- `<leader>lr` - **[R]**egex filter - Add regex pattern to filter (OR logic)
- `<leader>lnr` - **[N]**egated **[R]**egex - Exclude entries matching pattern
- `<leader>lt` - **[T]**ime filter - Filter by date/time range
- `<leader>la` - **[A]**dd files - Merge multiple log files chronologically
- `<leader>ls` - **[S]**how in analysis buffer - Open in editable buffer
- `<leader>lw` - **[W]**rite filtered - Save to `.filtered` file
- `<leader>lu` - **[U]**ndo filter - Reload original buffer and clear filter memory
## Usage

### Commands

- `:LogFilter` - Open filter prompt with history
- `:LogShow` - Open filtered results in analysis buffer
- `:LogSaveFiltered` - Save filtered results to file

### Default Keymaps

- `<leader>logr` - **[R]**egex filter - Filter buffer with regex pattern
#### Basic Regex Filtering

1. **Filter a log file**: Press `<leader>lr`
   - Type a new regex pattern OR
   - Navigate history with Ctrl+N/Ctrl+P and press Enter OR
   - Navigate to an entry, press Ctrl+E to load it for editing

2. **Stack additional filters**: Press `<leader>lr` again
   - File automatically reloads to base content
   - New pattern is added with OR logic: `pattern1|pattern2`
   - All previously applied filters are re-applied together

3. **Exclude unwanted entries**: Press `<leader>lnr`
   - Entire log entry blocks matching the pattern are excluded
   - Works with stacked filters: shows entries matching filters but not excludes
   - Example: Filter for "ERROR" but exclude "component=test"

#### Combined Filtering Example

#### Positive Filters (use with `<leader>lr`)
```
error|Error|ERROR|fail          # Match any error-related text
warn|WARN|warning               # Match warnings
\d{4}-\d{2}-\d{2}               # Match dates (YYYY-MM-DD)
192\.168\.                      # Match IP addresses starting with 192.168
exception.*occurred             # Match exception lines
Connection.*established         # Match connection messages
```

#### Exclusion Patterns (use with `<leader>lnr`)
```
DEBUG|TRACE                     # Exclude debug/trace lines
component=test                  # Exclude test component entries
ignore|skip                     # Exclude lines with these words
Send Status                     # Exclude status messages
healthcheck                     # Exclude healthcheck entries
```

#### Combined Usage
Filter for errors but exclude test environment:
```
<leader>lr → error|ERROR
<leader>lnr → component=test
``` and multi-file picker
- Optional: [ripgrep](https://github.com/BurntSushi/ripgrep) for faster filtering on large files
- Optional: 7-Zip or similar for compressed file support (`.zip`, `.gz`, `.7z`, etc.
Show connection events but not healthchecks:
```
<leader>lr → connection|Connection
<leadMulti-line entry parsing**: Logs are parsed into blocks separated by empty lines, with each block grouped by its timestamp
2. **Chronological merging**: Multiple files are merged by comparing timestamps on each log entry
3. **Pattern accumulation**: Each `<leader>lr` reloads the base file and re-applies all accumulated filter patterns with OR logic
4. **Block-level exclusion**: `<leader>lnr` excludes entire multi-line entries if ANY line in the block matches the exclude pattern
5. **Ripgrep acceleration**: For saved files, automatically uses ripgrep if available for faster filtering
6. **Smart reloading**: Filters automatically reload base content (original file or time-filtered version) before applying patterns
7. **Header preservation**: File lists, timestamps, filters, and excludes are preserved and stacked across operations

## Important Notes

- **Multi-line entries**: Log entries spanning multiple lines are kept together as blocks
- **Block exclusion**: Exclude patterns check the entire entry block, not just individual lines
- **Filter stacking**: Multiple `<leader>lr` calls create OR conditions: `pattern1|pattern2|pattern3`
- **Exclude stacking**: Multiple `<leader>lnr` calls exclude any block matching ANY exclude pattern
- **Time filter base**: After `<leader>lt`, filters work on the time-filtered subset
- **Clear with undo**: `<leader>lu` reloads original file and clears all filter/exclude memory
Filter: WARN

Exclude: ignore
Exclude: component=test

Combined Regex: ^(?!.*(ignore|component=test)).*(ERROR|WARN)
```

#### Multi-File Analysis

1. **Open first log file** in Neovim
2. **Add more files**: Press `<leader>la`
   - Select one or multiple files with `<C-e>`
   - Files are merged chronologically by timestamp
3. **Filter merged content**: Use `<leader>lr` and `<leader>lnr` as above
4. **Filter by time**: Press `<leader>lt`
   - Enter start time (pre-filled with first timestamp)
   - Enter end time (pre-filled with last timestamp)
   - Preserves existing regex filters and excludes

#### Saving and Analysis

1. **Analysis mode**: Press `<leader>ls` to open filtered content in a new editable buffer
2. **Save results**: Press `<leader>lw`
   - Saves as `originalfile.filtered`
   - Existing `.filtered` files are backed up as `.filtered.old_1`, `.filtered.old_2`, etc.
   - Automatically switches to the saved file
3. **Clear all filters**: Press `<leader>lu` to reload the original file and clear filter memorybuffer where you can edit it

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
