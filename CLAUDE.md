# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A combined dotfiles repo and MkDocs Material documentation site for a personal developer environment framework. The dotfiles are real configuration files (zsh, git, mise, direnv, tmux, vim, etc.) that get symlinked into `$HOME` via `bootstrap.sh`. The docs site explains the framework's design and opinions. Both ship in a single repo. Licensed GPLv3-or-later.

Read `meta/context.md` for the full project history, locked-in decisions, rejected paths, and collaboration patterns established across prior sessions. That document is the authoritative handoff artifact. It is internal (it contains an error log and governance notes) and lives in `meta/` rather than `docs/` precisely so it is never published to the public site.

## Build and validation commands

```sh
# MkDocs site (local dev — use uv, not pip)
uvx --with-requirements docs/requirements.txt mkdocs serve    # live-reload at http://127.0.0.1:8000
uvx --with-requirements docs/requirements.txt mkdocs build --strict  # production build; warnings are errors

# Shell syntax validation
zsh -n zsh/**/*.zsh                       # all zsh files
sh -n profile bootstrap.sh                # POSIX files

# POSIX profile test suite (30 tests, TAP output)
sh sh/tests/profile_test.sh              # single shell
sh sh/tests/profile_test.sh --multi      # sweep dash/bash/busybox

# JSON/XML config validation
python3 -c "import json, sys; json.load(open(sys.argv[1]))" <file>
python3 -c "import xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" <file>
```

Every content push must pass: `mkdocs build --strict`, `zsh -n` on all zsh files, `sh -n` on POSIX files, and the POSIX test suite.

## CI

`.github/workflows/docs.yml` builds and deploys the MkDocs site to gh-pages on push to `master` when `docs/**`, `mkdocs.yml`, or the workflow file changes.

## Architecture

**Zsh startup chain:** `~/.zshenv` (root — 10 lines, sets XDG vars + ZDOTDIR) -> `$ZDOTDIR/.zshenv` -> `$ZDOTDIR/.zprofile` -> `$ZDOTDIR/.zshrc` (sources `conf.d/*.zsh` in lexicographic order). New shell behavior goes in a numbered `conf.d/` fragment, never directly in `.zshrc`.

**POSIX profile:** `profile` (symlinked to `~/.profile`) is the subprocess shim — read by non-zsh processes, cron, LaunchAgents. Must remain strictly POSIX sh (no bashisms). Has its own 30-test suite.

**bootstrap.sh:** POSIX sh, idempotent symlink installer. Backs up existing files, creates XDG directories, symlinks configs, copies `.example` templates on first run (not symlinked so users can edit locally). Also audits shell startup files for rogue tool-installer injections.

**Docs site structure:** Two distinct sections in `mkdocs.yml` nav — **Reference** (bound to dotfile artifacts, practical) and **Handbook** (opinionated design guidance, judgment-based). The Handbook's Design section has seven stub pages organized around "separation" as a unifying meta-skill, following a specific 8-part rhetorical pattern documented in `docs/handbook/design/index.md`.

## Content conventions

- Opinionated but honest about counter-positions. Every stance acknowledges where it's wrong.
- No emoji in any content.
- First-person plural ("we recommend") in docs, not second-person ("you should").
- Short sentences. Concrete over abstract. No "seamlessly integrates" prose.
- Code examples: real languages (Ruby, Python primarily), realistic problem domains, sized to the point.
- Admonitions (MkDocs callout blocks) for asides only; use sparingly.

## Placeholder convention

Distinctive real strings as placeholders — `zftadvancements`, `billwoika.com`, etc. Fork the framework with a single `sed` pass. Full table in `docs/reference/customization.md`. Do not use Jinja templating or generic placeholders.

## Formatting

Per `.editorconfig`: UTF-8, LF line endings, 2-space indent (tabs only in Makefiles), final newline, trim trailing whitespace (except `.md`).

## Deliberately excluded

Plugin managers (oh-my-zsh, zinit), prompt frameworks (starship, powerlevel10k), dotfile managers (chezmoi, yadm), non-POSIX shells (fish, nushell), Cursor IDE. See `meta/context.md` Section 3.10 for reasoning.

## Working patterns

- Push back on ambiguous direction before committing to work. Propose multiple readings of ambiguous pivots and ask which.
- Use Q1/Q2/Q3 numbered confirmations before any substantial content push.
- Flag scope honestly when a request is too large for one push.
- Do not promote content from `_drafts/` without explicit approval.
- Do not restructure navigation mid-session without confirmation.
- The Handbook audience is engineers at all levels — junior through senior on every page.
