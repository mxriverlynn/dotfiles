set runtimepath^=~/.vim/bundle/ag

if executable('ag')
  let g:ackprg = 'ag --vimgrep'
endif
