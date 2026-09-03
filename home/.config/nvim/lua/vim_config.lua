local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true                -- absolute number on the cursor line, relative elsewhere
o.relativenumber = true        -- relative line numbers for fast jumps
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
o.clipboard = 'unnamedplus'    -- share the system clipboard
o.scrolloff = 16               -- keep cursor away from the screen edge
o.undofile = true              -- persistent undo across sessions
o.mouse = ''                   -- no mouse in nvim; also lets Herdr keep host mouse capture off so Escape isn't swallowed

-- flash the text that was just yanked; stays lit until you move the cursor or edit
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function() vim.hl.on_yank({ timeout = -1 }) end,
})
vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'TextChanged' }, {
  callback = function()
    vim.api.nvim_buf_clear_namespace(0, vim.api.nvim_create_namespace('nvim.hlyank'), 0, -1)
  end,
})

