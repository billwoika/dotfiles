# ─────────────────────────────────────────────────────────────────────
# 26-terminal-osc.zsh — terminal integration on the framework's terms
#
# Emits the two escape sequences that make a modern terminal smart
# about the shell, from the shell side, with no vendor script:
#
#   OSC 7    current working directory (file://host/path). Powers
#            "new tab opens where I was" (Ptyxis preserve-directory),
#            and correct drag-a-tab-out behavior.
#   OSC 133  FinalTerm prompt marks (A=prompt, C=output starts,
#            D=command done + exit code). Powers jump-to-prompt and
#            command-status UI in terminals that expose it (WezTerm,
#            kitty, iTerm2, tmux 3.4 copy-mode) and costs nothing in
#            those that don't yet (Ptyxis).
#
# Why this exists: Fedora ships /etc/profile.d/vte.sh for exactly
# this, but it only reaches zsh through /etc/zprofile — LOGIN shells.
# GUI terminals (Ptyxis included) spawn non-login shells by default,
# so zsh gets nothing. Rather than flip login-shell on and depend on
# a distro side-channel, the framework owns the emission. Numbered 26
# so it can defer to integrations 25-tool-cache.zsh already loaded.
# ─────────────────────────────────────────────────────────────────────

# Terminals that can't use it.
case "${TERM}" in dumb|linux) return 0 ;; esac

# Defer to an integration that is already emitting these:
#   vte.sh registered its hooks (login shell under a VTE terminal)
(( ${+functions[__vte_precmd]} )) && return 0
#   iTerm2's script (loaded by 25-tool-cache.zsh when LC_TERMINAL=iTerm2)
[[ -n "${ITERM_SHELL_INTEGRATION_INSTALLED-}" ]] && return 0
#   WezTerm's script (loaded by 25-tool-cache.zsh when TERM_PROGRAM=WezTerm)
(( ${+functions[__wezterm_osc7]} )) && return 0
#   VS Code's injected integration (VSCODE_INJECTION=1)
[[ -n "${VSCODE_INJECTION-}" ]] && return 0
#   kitty with shell_integration enabled (we reject its ZDOTDIR mode,
#   but a user running `no-rc` plus kitty's manual opt-in shouldn't
#   get double marks)
(( ${+functions[_ksi_precmd]} )) && return 0

autoload -Uz add-zsh-hook

# Percent-encode $PWD byte-wise and report it. LC_ALL=C makes zsh
# subscript bytes, not characters, so multibyte paths encode correctly.
__dotfiles_osc7() {
  local LC_ALL=C
  local url='' ch
  local -i i
  for (( i = 1; i <= ${#PWD}; i++ )); do
    ch="${PWD[i]}"
    if [[ "$ch" == [A-Za-z0-9/._~-] ]]; then
      url+="$ch"
    else
      printf -v ch '%%%02X' "'$ch"
      url+="$ch"
    fi
  done
  printf '\e]7;file://%s%s\a' "${HOST}" "${url}"
}

# Inside tmux these reach tmux, which understands both (OSC 7 with
# allow-passthrough for the outer terminal; OSC 133 marks power
# copy-mode prompt jumps natively since 3.4). No special casing.
typeset -gi __dotfiles_osc_cmd_open=0

__dotfiles_osc_preexec() {
  printf '\e]133;C\a'
  __dotfiles_osc_cmd_open=1
}

__dotfiles_osc_precmd() {
  local -i st=$?
  # Close the previous command with its exit code — but only if one
  # actually ran (no spurious D on the first prompt or after ^C at
  # an empty prompt).
  if (( __dotfiles_osc_cmd_open )); then
    printf '\e]133;D;%d\a' "$st"
    __dotfiles_osc_cmd_open=0
  fi
  __dotfiles_osc7
  printf '\e]133;A\a'
}

add-zsh-hook precmd  __dotfiles_osc_precmd
add-zsh-hook preexec __dotfiles_osc_preexec
