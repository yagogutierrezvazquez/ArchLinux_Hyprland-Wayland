#
# ~/.bashrc
#

# If not running interactively, don't do anything
# Personal commands (e.g. matrix)
export PATH="$HOME/.local/bin:$PATH"

[[ $- != *i* ]] && return

#  Intel Driver Controller
export LIBVA_DRIVER_NAME=iHD

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Fetch when a new kitty window opens (config: ~/.config/fastfetch, generated
# by matugen). FETCH_SHOWN keeps nested shells from repeating it.
if [[ $TERM == xterm-kitty && -z $FETCH_SHOWN ]] && command -v fastfetch >/dev/null; then
    export FETCH_SHOWN=1
    fastfetch
fi

# One empty line between a command's output and the next prompt (not before
# the first prompt, so a new window starts right under the fetch)
_prompt_gap() { [[ -n $_PROMPT_GAP ]] && echo; _PROMPT_GAP=1; }
PROMPT_COMMAND="_prompt_gap${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
