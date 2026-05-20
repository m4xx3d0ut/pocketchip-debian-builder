vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.termguicolors = true
opt.number = true
opt.relativenumber = false
opt.cursorline = true
opt.mouse = "a"
opt.clipboard = ""
opt.hidden = true
opt.encoding = "utf-8"
opt.history = 1000
opt.equalalways = false
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true
opt.smarttab = true
opt.wrap = false
opt.ignorecase = true
opt.smartcase = true
opt.splitright = true
opt.splitbelow = true
opt.timeout = true
opt.timeoutlen = 1000
opt.updatetime = 700
opt.signcolumn = "yes"
opt.statusline = " %f %m %= %l:%c "

if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC 52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
    }
  end
end

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "checktime",
})

vim.api.nvim_create_autocmd("TermClose", {
  pattern = "*",
  callback = function(args)
    if vim.v.event.status == 0 then
      vim.api.nvim_buf_delete(args.buf, { force = true })
    end
  end,
})

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local function tmux_or_window(tmux_cmd, win_cmd)
  if command_exists(tmux_cmd) then
    vim.cmd(tmux_cmd)
  else
    vim.cmd("wincmd " .. win_cmd)
  end
end

local map = vim.keymap.set
local opts = { silent = true }

map("n", "<leader>w", "<cmd>write<cr>", vim.tbl_extend("force", opts, { desc = "Save file" }))
map("n", "<leader>q", "<cmd>quit<cr>", vim.tbl_extend("force", opts, { desc = "Quit window" }))
map("n", "<leader>Q", "<cmd>qa!<cr>", vim.tbl_extend("force", opts, { desc = "Quit all" }))
map("n", "<leader>bn", "<cmd>bnext<cr>", vim.tbl_extend("force", opts, { desc = "Next buffer" }))
map("n", "<leader>bp", "<cmd>bprevious<cr>", vim.tbl_extend("force", opts, { desc = "Previous buffer" }))
map("n", "<leader>bd", "<cmd>bdelete<cr>", vim.tbl_extend("force", opts, { desc = "Delete buffer" }))
map("n", "<leader>sv", "<cmd>vsplit<cr>", vim.tbl_extend("force", opts, { desc = "Vertical split" }))
map("n", "<leader>sh", "<cmd>split<cr>", vim.tbl_extend("force", opts, { desc = "Horizontal split" }))
map("n", "<leader>sc", "<cmd>close<cr>", vim.tbl_extend("force", opts, { desc = "Close split" }))
map("n", "<leader><Left>", "<cmd>vertical resize -2<cr>", opts)
map("n", "<leader><Right>", "<cmd>vertical resize +2<cr>", opts)
map("n", "<leader><Up>", "<cmd>resize +2<cr>", opts)
map("n", "<leader><Down>", "<cmd>resize -2<cr>", opts)
map("n", "<leader>to", "<cmd>tabnew<cr>", opts)
map("n", "<leader>tc", "<cmd>tabclose<cr>", opts)
map("n", "<leader>tn", "<cmd>tabnext<cr>", opts)
map("n", "<leader>tp", "<cmd>tabprevious<cr>", opts)
map("n", "<A-j>", "<cmd>m .+1<cr>==", opts)
map("n", "<A-k>", "<cmd>m .-2<cr>==", opts)
map("n", "n", "nzzzv", opts)
map("n", "N", "Nzzzv", opts)
map("n", "<leader>co", "<cmd>copen<cr>", opts)
map("n", "<leader>cc", "<cmd>cclose<cr>", opts)
map("n", "<leader>cn", "<cmd>cnext<cr>", opts)
map("n", "<leader>cp", "<cmd>cprev<cr>", opts)
map("n", "<leader>h", "<cmd>nohlsearch<cr>", opts)
map("n", "<leader>tt", "<cmd>terminal<cr>", opts)
map("n", "<leader>tv", "<cmd>vsplit | terminal<cr>", opts)
map("n", "<leader>th", "<cmd>split | terminal<cr>", opts)
map("n", "<C-z>", "u", opts)
map("n", "<C-y>", "<C-r>", opts)

map("n", "<leader>e", function()
  if command_exists("NvimTreeToggle") then
    vim.cmd.NvimTreeToggle()
  else
    vim.cmd.Ex()
  end
end, vim.tbl_extend("force", opts, { desc = "Files" }))

map("n", "<C-h>", function() tmux_or_window("TmuxNavigateLeft", "h") end, opts)
map("n", "<C-j>", function() tmux_or_window("TmuxNavigateDown", "j") end, opts)
map("n", "<C-k>", function() tmux_or_window("TmuxNavigateUp", "k") end, opts)
map("n", "<C-l>", function() tmux_or_window("TmuxNavigateRight", "l") end, opts)

map("i", "jk", "<esc>", opts)
map("i", "<C-s>", "<esc>:w<cr>a", opts)
map("i", "<C-z>", "<C-o>u", opts)
map("i", "<C-y>", "<C-o><C-r>", opts)
map("v", ">", ">gv", opts)
map("v", "<", "<gv", opts)
map("v", "J", ":m '>+1<cr>gv=gv", opts)
map("v", "K", ":m '<-2<cr>gv=gv", opts)
map("t", "<Esc>", "<C-\\><C-n>", opts)
map("t", "<C-h>", "<C-\\><C-n><C-w>h", opts)
map("t", "<C-j>", "<C-\\><C-n><C-w>j", opts)
map("t", "<C-k>", "<C-\\><C-n><C-w>k", opts)
map("t", "<C-l>", "<C-\\><C-n><C-w>l", opts)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if vim.fn.isdirectory(lazypath) == 0 and vim.fn.executable("git") == 1 and vim.env.POCKETCHIP_NVIM_BOOTSTRAP ~= "0" then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end

if vim.fn.isdirectory(lazypath) == 1 then
  vim.opt.rtp:prepend(lazypath)
  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.setup({
      { "ellisonleao/gruvbox.nvim", priority = 1000, config = function() pcall(vim.cmd.colorscheme, "gruvbox") end },
      { "numToStr/Comment.nvim", opts = {} },
      { "lewis6991/gitsigns.nvim", opts = { signs = { add = { text = "+" }, change = { text = "~" }, delete = { text = "-" } } } },
      { "christoomey/vim-tmux-navigator" },
      {
        "nvim-tree/nvim-tree.lua",
        keys = { { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Files" } },
        opts = {
          view = { width = 24 },
          renderer = { icons = { show = { file = false, folder = false, folder_arrow = false, git = false } } },
          filters = { dotfiles = false },
        },
      },
      { "nvim-lualine/lualine.nvim", opts = { options = { icons_enabled = false, section_separators = "", component_separators = "|" } } },
    }, {
      checker = { enabled = false },
      change_detection = { enabled = false },
      install = { missing = true },
      performance = {
        rtp = {
          disabled_plugins = {
            "gzip",
            "netrwPlugin",
            "tarPlugin",
            "tohtml",
            "tutor",
            "zipPlugin",
          },
        },
      },
    })
  end
end
