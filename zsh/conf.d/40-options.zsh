# $ZDOTDIR/conf.d/40-options.zsh
# ─────────────────────────────────────────────────────────────────────
# Shell behavior options. Each is a deliberate choice; see the framework
# docs/shell-environment/architecture.md for rationale on specific settings.
# ─────────────────────────────────────────────────────────────────────

# ── Directory navigation ────────────────────────────────────────────
setopt AUTO_CD              # `docs` → `cd docs` when docs is a dir and not a command
setopt AUTO_PUSHD           # cd pushes onto the dir stack
setopt PUSHD_IGNORE_DUPS    # no duplicates in dir stack
setopt PUSHD_MINUS          # `cd -2` swaps with stack[2]
setopt PUSHD_SILENT         # no chatter on pushd/popd

# ── Globbing ────────────────────────────────────────────────────────
setopt EXTENDED_GLOB        # #, ~, ^ operators; glob qualifiers (N, D, .)
setopt GLOB_DOTS            # * matches dotfiles too
setopt NO_CASE_GLOB         # case-insensitive globbing
setopt NUMERIC_GLOB_SORT    # numeric-aware sort for *.jpg etc.

# ── Correction ──────────────────────────────────────────────────────
setopt CORRECT              # prompt to correct mistyped commands
# setopt CORRECT_ALL        # also correct arguments — usually too eager

# ── Job control ─────────────────────────────────────────────────────
setopt LONG_LIST_JOBS       # verbose job control output
setopt NO_BG_NICE           # don't auto-nice background jobs
setopt NO_HUP               # don't SIGHUP background jobs on shell exit
setopt NO_CHECK_JOBS        # don't warn about background jobs on exit

# ── Input / output ──────────────────────────────────────────────────
setopt NO_CLOBBER           # > fails if file exists; use >| to force
setopt INTERACTIVE_COMMENTS # allow # comments in interactive shell
setopt RC_QUOTES            # 'don''t' as a single-quote literal

# ── Prompt ──────────────────────────────────────────────────────────
setopt PROMPT_SUBST         # expand variables/commands in PROMPT

# ── Miscellaneous ───────────────────────────────────────────────────
setopt NO_BEEP              # no audible bell on error
setopt NO_FLOW_CONTROL      # free ^S and ^Q for keybinds
setopt MULTIOS              # `cmd >a >b` writes to both
setopt COMBINING_CHARS      # handle combining Unicode chars correctly
