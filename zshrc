#! /bin/zsh

# ruby / rails / bundler config
eval "$(rbenv init -)"

# load nvm
export NVM_DIR="$HOME/.nvm"
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && . "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# auto-load .nvmrc files
function use_nvm {
  if [ -f .nvmrc ] && [ -d "$HOME/.nvm" ]; then
    nvm use
  fi
}
use_nvm


# load yvm
export YVM_DIR=/usr/local/opt/yvm
[ -r $YVM_DIR/yvm.sh ] && . $YVM_DIR/yvm.sh

# set `dir` exa configuration and colors
function set_exa_config {
  local USER_PERMS="ur=37;40:uw=37;40:ux=37;40:ue=37;40"
  local GROUP_PERMS="gr=37;40:gw=37;40:gx=37;40:ge=37;40"
  local OTHER_PERMS="tr=37;40:tw=37;40:tx=37;40"
  local USER_GROUP="uu=37;40:un=31;40"

  export EXA_COLORS="ex=31;40:sn=32;40:da=36;40:di=33;40:gm=31;40:$USER_GROUP:$USER_PERMS:$GROUP_PERMS:$OTHER_PERMS"

  alias dir="exa -lahF --git"
}
set_exa_config

export GIT_PS1_SHOWDIRTYSTATE=true
export GIT_PS1_SHOWUNTRACKEDFILES=true
export GIT_PS1_SHOWUPSTREAM=auto
export GIT_PS1_SHOWSTASHSTATE=true

export TERM=xterm-color
export CLICOLOR=1
export LSCOLORS=Dxfxcxdxbxegedabagacad

export EDITOR=mvim
export CC=/usr/bin/gcc

# set the terminal prompt
function pprom {
  local BLUE="\[\033[0;34m\]"
  local BROWN="\[\033[0;33m\]"
  local CYAN="\[\033[0;36m\]"
  local GRAY="\[\033[1:30m\]"
  local GREEN="\[\033[0;32m\]"
  local PURPLE="\[\033[0;35m\]"
  local RED="\[\033[0;31m\]"
  local YELLOW="\[\033[1;33m\]"
  local WHITE="\[\033[1;37m\]"
  local LIGHT_BLUE="\[\033[1;34m\]"
  local LIGHT_CYAN="\[\033[1;36m\]"
  local LIGHT_GRAY="\[\033[0;37m\]"
  local LIGHT_GREEN="\[\033[1;32m\]"
  local LIGHT_PURPLE="\[\033[1:35m\]"
  local LIGHT_RED="\[\033[1;31m\]"
  local NO_COLOUR="\[\033[0m\]"

  local TITLEBAR='\[\033]0;\u@\h\007\]'

PS1="$TITLEBAR\n\w/$LIGHT_GREEN\$(__git_ps1 ' (%s)')\n$NO_COLOUR$ "
PS2='> '
PS4='+ '
}
pprom

export PATH="/usr/local/opt/icu4c/bin:$PATH"
export PATH="/usr/local/opt/icu4c/sbin:$PATH"
export LDFLAGS="-L/usr/local/opt/icu4c/lib"
export CPPFLAGS="-I/usr/local/opt/icu4c/include"
export PKG_CONFIG_PATH="/usr/local/opt/icu4c/lib/pkgconfig"

export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)"
export PORT=3000
