let mapleader = ","

function! CopyFileToClipboard()
  :let @+ = expand("%")
  echo 'Copied filename to system clipboard'
endfunction

nnoremap <LEADER>d :NERDTreeToggle<CR>
nnoremap <LEADER>f :NERDTreeFind<CR>
nnoremap <LEADER>t :Files<CR>
nnoremap <LEADER>cf :call CopyFileToClipboard()<CR>
