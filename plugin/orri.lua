if vim.g.loaded_orri then
  return
end
vim.g.loaded_orri = true

vim.api.nvim_create_user_command('Orri', function()
  require('orri').open()
end, { desc = 'Stream this buffer to the orri viewer' })

vim.api.nvim_create_user_command('OrriStop', function()
  require('orri').disconnect()
end, { desc = 'Stop streaming to the orri viewer' })

vim.api.nvim_create_user_command('OrriToggle', function()
  require('orri').toggle()
end, { desc = 'Toggle orri streaming' })
