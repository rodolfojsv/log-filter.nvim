# log-filter.nvim Repository Structure

```
log-filter.nvim/
├── lua/
│   ├── log-filter/
│   │   ├── init.lua          # Main entry point with setup()
│   │   └── core.lua           # Core filtering logic
│   └── plugin/
│       └── log-filter.lua     # Commands and keymaps
├── .gitignore
├── LICENSE
└── README.md
```

## Files Created

1. **README.md** - Complete documentation with installation, configuration, and usage
2. **LICENSE** - MIT License
3. **.gitignore** - Standard ignore file
4. **lua/log-filter/init.lua** - Main module with setup() function
5. **lua/log-filter/core.lua** - All filtering logic (extracted from your log-filter.lua)
6. **lua/plugin/log-filter.lua** - User commands and keymaps

## Key Features

All configuration is now done via `setup()`:

```lua
require('log-filter').setup({
  history_file = 'C:/temp/nvim_log_filter_history.txt',  -- Where to store regex history
  max_history = 20,                                       -- Max number of patterns to remember
  load_entry_key = '<C-e>',                              -- Key to load history entry into prompt
})
```

## How to Use in Your Config

In your `lua/custom/plugins/` folder, create a file like `log-filter-config.lua`:

```lua
return {
  'rodolfojsv/log-filter.nvim',
  config = function()
    require('log-filter').setup({
      history_file = 'C:/temp/nvim_log_filter_history.txt',
      max_history = 20,
      load_entry_key = '<C-e>',
    })
  end,
}
```

Or if using lazy.nvim directly in init.lua:

```lua
{
  'rodolfojsv/log-filter.nvim',
  config = function()
    require('log-filter').setup({
      history_file = 'C:/temp/nvim_log_filter_history.txt',
      max_history = 20,
      load_entry_key = '<C-e>',
    })
  end,
}
```

## Next Steps

1. Initialize a git repository:
   ```powershell
   cd C:\Users\lph15526\AppData\Local\nvim\log-filter.nvim
   git init
   git add .
   git commit -m "Initial commit: log-filter.nvim"
   ```

2. Create GitHub repository (via GitHub web interface)

3. Push to GitHub:
   ```powershell
   git remote add origin https://github.com/rodolfojsv/log-filter.nvim.git
   git branch -M main
   git push -u origin main
   ```

4. Test it in your config by replacing your local plugin with:
   ```lua
   return {
     'rodolfojsv/log-filter.nvim',
     config = function()
       require('log-filter').setup({
         history_file = 'C:/temp/nvim_log_filter_history.txt',
         max_history = 20,
         load_entry_key = '<C-e>',
       })
     end,
   }
   ```

## Sharing with Co-workers

They can install it with lazy.nvim:

```lua
{
  'rodolfojsv/log-filter.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',  -- Optional but recommended
  },
  config = function()
    require('log-filter').setup({
      -- They can customize their own settings
      history_file = vim.fn.stdpath('cache') .. '/log_filter_history.txt',
      max_history = 20,
      load_entry_key = '<C-e>',
    })
  end,
}
```
