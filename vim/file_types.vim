" file types and syntax highlighting
syntax on

filetype plugin indent on

au BufNewFile,BufRead,BufWritePost *.js         set syntax=javascript
au BufNewFile,BufRead,BufWritePost *.json       set syntax=javascript
au BufNewFile,BufRead,BufWritePost *.rb         set syntax=ruby
au BufNewFile,BufRead,BufWritePost *.sh         set syntax=bash
au BufNewFile,BufRead,BufWritePost *.zsh        set syntax=bash
au BufNewFile,BufRead,BufWritePost *.dockerfile set syntax=dockerfile
