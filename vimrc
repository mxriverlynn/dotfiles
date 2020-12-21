execute pathogen#infect()

colorscheme desert

set guifont=HackNerdFontCompleteM-Regular:h18
set runtimepath^=~/.vim/bundle/ag
set noerrorbells visualbell

" tabs to spaces
set tabstop=2
set shiftwidth=2
set expandtab

" file types and syntax highlighting
syntax on
filetype plugin indent on
au BufNewFile,BufRead *.js         set syntax=javascript
au BufNewFile,BufRead *.json       set syntax=javascript
au BufNewFile,BufRead *.rb         set syntax=ruby
au BufNewFile,BufRead *.sh         set syntax=bash
au BufNewFile,BufRead *.zsh        set syntax=bash
au BufNewFile,BufRead *.dockerfile set syntax=dockerfile

let mapleader = ","
nnoremap <LEADER>d :NERDTreeToggle<CR>
nnoremap <LEADER>f :NERDTreeFind<CR>
nnoremap <LEADER>t :Files<CR>

" Start NERDTree and put the cursor back in the other window.
autocmd GUIEnter * NERDTree | wincmd p

if executable('ag')
  let g:ackprg = 'ag --vimgrep'
endif

" swap between buffers without the 'no write since last change' error
set hidden

" handle swap files
set undofile
set undolevels=1000         " How many undos
set undoreload=10000        " number of lines to save for undo

set backup                        " enable backups
set swapfile                      " enable swaps
set undodir=$HOME/.vim/tmp/undo     " undo files
set backupdir=$HOME/.vim/tmp/backup " backups
set directory=$HOME/.vim/tmp/swap   " swap files

" Make those folders automatically if they don't already exist.
if !isdirectory(expand(&undodir))
  call mkdir(expand(&undodir), "p")
endif
if !isdirectory(expand(&backupdir))
  call mkdir(expand(&backupdir), "p")
endif
if !isdirectory(expand(&directory))
  call mkdir(expand(&directory), "p")
endif
