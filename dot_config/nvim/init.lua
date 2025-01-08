vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.markdown_recommended_style = 0 -- https://github.com/neovim/neovim/blob/d25889ab7607918a152bab5ce4d14e54575ec11b/runtime/ftplugin/markdown.vim

vim.opt.autowrite = true
vim.opt.confirm = true
vim.opt.expandtab = true
vim.opt.fileformats = 'unix'
vim.opt.ignorecase = true
vim.opt.listchars = { eol = '%', tab = '<->', space = '.', multispace = '...+', nbsp = '_' }
vim.opt.number = true
vim.opt.report = 0
vim.opt.shiftwidth = 2
vim.opt.showmatch = true
vim.opt.smartcase = true
vim.opt.smartindent = true
vim.opt.softtabstop = 2
vim.opt.tabstop = 8
vim.opt.visualbell = true
vim.opt.wrapscan = false

-- https://dev.to/cbartlett/word-wrapping-in-vim-4oog
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.list = false

if vim.g.vscode then
    -- VSCode extension
else
    -- ordinary Neovim
  require("config.lazy")
  vim.cmd.colorscheme "catppuccin"
end

