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

-- undo across every open buffer; u alone only undoes the current file,
-- which is half a story after a project-wide LSP rename (Space-rn)
vim.api.nvim_create_user_command('UndoAllBuffers', function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf, function() vim.cmd('silent! undo') end)
    end
  end
end, {})

-- reload buffers when something outside nvim changes the file on disk
-- (git restore/switch, formatters, agent edits). edit is still shown.
o.autoread = true
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
  callback = function()
    if vim.fn.mode() ~= 'c' then vim.cmd('checktime') end
  end,
})

-- throw away unsaved edits in every buffer, reloading all files from disk.
-- the mirror image of :wa; bang skips the confirmation.
vim.api.nvim_create_user_command('DiscardAllBuffers', function(opts)
  if not opts.bang then
    if vim.fn.confirm('Discard unsaved changes in ALL buffers?', '&Yes\n&No', 2) ~= 1 then return end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then
      vim.api.nvim_buf_call(buf, function() vim.cmd('silent! edit!') end)
    end
  end
end, { bang = true })

