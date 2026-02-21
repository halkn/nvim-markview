if vim.g.loaded_markview then
  return
end
vim.g.loaded_markview = true

vim.api.nvim_create_user_command("MarkviewOpen", function()
  require("markview").open()
end, { desc = "Open Markview browser preview" })

vim.api.nvim_create_user_command("MarkviewClose", function()
  require("markview").close()
end, { desc = "Close Markview browser preview" })

vim.api.nvim_create_user_command("MarkviewToggle", function()
  require("markview").toggle()
end, { desc = "Toggle Markview browser preview" })
