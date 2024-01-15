local opt = vim.opt


opt.relativenumber = true
opt.number = true

--tabs and indent

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true

-- Line 

opt.scrolloff = 8
opt.wrap = false

-- Search settings

opt.hlsearch = false
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Cursor highlight and colors

opt.termguicolors = true
opt.cursorline = true

-- clipboard

opt.clipboard:append("unnamedplus")
opt.iskeyword:append("-")
opt.iskeyword:append("_")

opt.updatetime = 50
