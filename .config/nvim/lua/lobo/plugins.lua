local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local plugins = {
  'nvim-treesitter/nvim-treesitter', 
  'nvim-treesitter/playground',
  'tpope/vim-fugitive',
  'neovim/nvim-lspconfig',           
  'williamboman/mason.nvim',         
  'williamboman/mason-lspconfig.nvim',
  -- Autocompletion
  'VonHeikemen/lsp-zero.nvim', branch = 'v3.x',
  'neovim/nvim-lspconfig',
  'hrsh7th/nvim-cmp',
  'hrsh7th/cmp-nvim-lsp', 
  'nvim-lua/plenary.nvim',
  'L3MON4D3/LuaSnip',  
  {
	  'nvim-telescope/telescope.nvim',
    tag = '0.1.2',
	  dependencies = { {'nvim-lua/plenary.nvim'} }
  },
  { 
    'catppuccin/nvim',
  	name = 'catppuccin',
    -- start before everything else
    priority = 1000, 
	  config = function()
		  vim.cmd('colorscheme catppuccin')
	  end
  },
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { {"nvim-lua/plenary.nvim"} }
  },
  { 
    "lukas-reineke/indent-blankline.nvim", 
    main = "ibl", 
  },
}


local opts = {}


require("lazy").setup(plugins, opts)

require("mason-lspconfig").setup()
local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())

require('lspconfig')['pyright'].setup {
    capabilities = capabilities
}
