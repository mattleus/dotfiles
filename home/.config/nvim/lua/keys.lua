-- save by pressing Escape
vim.keymap.set('n', '<Esc>', ':w<CR>', { desc = 'Save' })
-- select all
vim.keymap.set('n', '<C-a>', 'ggVG', { desc = 'Select All' })
-- pasting over a selection no longer clobbers your clipboard
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])
-- move focus between windows (incl. the file tree) with Ctrl-h/j/k/l
for dir, key in pairs({ h = 'Left', j = 'Down', k = 'Up', l = 'Right' }) do
  vim.keymap.set('n', '<C-' .. dir .. '>', '<C-w>' .. dir, { desc = 'Focus ' .. key .. ' Window' })
end
-- duplicate line/selection below; :t copies without touching registers (clipboard stays intact)
vim.keymap.set('n', '<leader>d', ':t.<CR>', { desc = 'Duplicate Line Below' })
vim.keymap.set('x', '<leader>d', ":t'><CR>", { desc = 'Duplicate Selection Below' })

