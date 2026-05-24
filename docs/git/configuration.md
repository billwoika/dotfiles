# Git Configuration

Git is the one tool every engineer on this stack uses dozens of times
per day. Its configuration surface is enormous, mostly sensible, and
almost entirely mis-defaulted. This page establishes an XDG-compliant
`~/.config/git/config` with path-based identity profiles, commit
signing via SSH keys, and a set of defaults that catch common failure
modes before they happen.

The organizing idea is **path-based profiles**: one global config that
sets universal defaults, plus profile-specific overrides that activate
automatically based on where a repository lives on disk. No more
forgetting to set your work email before the first commit, no more
leaking a personal SSH signing key into a work commit, no more
per-repo `git config user.email` dance.

!!! note "Why path-based, not per-repo?"

    Per-repo `.git/config` overrides work but fail at scale: every new
    clone requires remembering to set them, and the state lives inside
    the git directory where it is easy to miss during audits.
    Path-based profiles via `includeIf` move the policy up one level —
    as long as you clone work repos under `~/work/` and personal ones
    under `~/personal/`, identity is correct without any per-repo
    action. The filesystem layout becomes the contract.

## File layout

```
~/.config/git/
├── config                       # Main config — global defaults + includeIf rules
├── ignore                       # Global gitignore (backstop)
├── attributes                   # Global gitattributes
├── work.config                  # Loaded when gitdir matches ~/work/
├── personal.config              # Loaded when gitdir matches ~/personal/
├── opensource.config            # Loaded when gitdir matches ~/opensource/
└── allowed_signers              # SSH signing key registry for git verify-commit
```

Git reads `~/.config/git/config` when `XDG_CONFIG_HOME` is set (which
the framework guarantees via `~/.zshenv` and `~/.profile`). The legacy
`~/.gitconfig` is still honored if present, but maintaining both is a
recipe for drift — pick one location and stick with it. Delete
`~/.gitconfig` after migrating.

## Main config

The main config sets universal defaults and declares which profile to
load for each path prefix. It contains **no email, no signing key,
and no repository-specific configuration** — those live in the
profile files.

Key settings worth calling out:

| Section | Setting | Why |
|---------|---------|-----|
| `[init]` | `defaultBranch = master` | Default branch name for `git init`. See note below |
| `[pull]` | `rebase = true` | Rebase on pull rather than merge — cleaner history |
| `[push]` | `autoSetupRemote = true` | Auto-create remote branch on first push |
| `[fetch]` | `prune = true` | Remove local refs for branches deleted on remote |
| `[merge]` | `conflictStyle = zdiff3` | Show original content alongside both sides (git 2.35+) |
| `[rebase]` | `updateRefs = true` | Update dependent branches when rebasing their base |
| `[rebase]` | `autoSquash = true` | Auto-squash `fixup!` and `squash!` commits |
| `[rebase]` | `autoStash = true` | Stash local changes before rebase, restore after |
| `[rerere]` | `enabled = true` | Reuse recorded conflict resolutions |
| `[diff]` | `algorithm = histogram` | Better rename detection |
| `[diff]` | `colorMoved = zebra` | Highlight moved lines in a distinct color |
| `[commit]` | `gpgsign = true` | Default all commits to signed |
| `[commit]` | `verbose = true` | Show diff in commit message editor |
| `[branch]` | `sort = -committerdate` | List branches by committer date, newest first |
| `[help]` | `autocorrect = prompt` | Never auto-execute a suggested command |

The full config is at `git/config` in the dotfiles repository.

### On `defaultBranch = master`

In 2020, GitHub changed its default branch name from `master` to
`main`. The term `master` in the context of version control predates
the English language in its etymological roots — it derives from the
concept of a master copy or master record, the same usage found in
master recording, master key, and master plan. It has no relationship
to the connotation GitHub's rename was responding to.

This framework uses `master` for three reasons:

1. **It is git's original convention.** Git itself still defaults to
   `master` unless overridden. The rename was a GitHub platform
   decision, not a git project decision.
2. **The rename introduced real cost for symbolic benefit.** Every
   existing repository, script, CI pipeline, tutorial, and Stack
   Overflow answer that referenced `master` became slightly wrong
   overnight. The schism between pre-2020 and post-2020 repositories
   is permanent — there is no migration path that does not touch every
   downstream consumer. This was the absolute least a company of
   Microsoft's scale could do, and the friction it imposed landed
   entirely on the users.
3. **Consistency with existing repositories matters.** The majority of
   repositories in active production use predate the rename. A
   framework that defaults to `main` for new repos while working
   daily in `master` repos creates exactly the kind of muscle-memory
   split and scripting fragility that a dotfiles framework should
   eliminate.

The framework's git aliases (`merged`, `cleanup`) handle both `main`
and `master` for interoperability with repos that use either
convention. The position is practical, not political.

## Profile files

Each profile file contains exactly the identity-specific settings —
email, signing key, and anything else that varies between contexts.
Keep them short.

```ini
# ~/.config/git/work.config
[user]
    email = dev@zftadvancements.com
    signingkey = ~/.ssh/id_ed25519_work.pub

[gpg]
    format = ssh

[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers

# Work repos use git@github.com-work to route through a work-specific
# SSH identity (see SSH page for host alias setup).
[url "git@github.com-work:zftadvancements/"]
    insteadOf = https://github.com/zftadvancements/
    insteadOf = git@github.com:zftadvancements/
```

```ini
# ~/.config/git/personal.config
[user]
    email = you@billwoika.com
    signingkey = ~/.ssh/id_ed25519_personal.pub

[gpg]
    format = ssh

[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers

[url "git@github.com-personal:"]
    insteadOf = https://github.com/
    insteadOf = git@github.com:
```

To verify which profile is active:

```sh
git config --list --show-origin | grep user.email
```

The `--show-origin` flag prints the exact file each value was loaded
from, which makes debugging trivial when a profile doesn't activate as
expected.

!!! warning "includeIf pattern gotchas"

    The pattern `gitdir:~/work/` matches when the repository's `.git`
    directory resolves to a path starting with `~/work/`. The trailing
    slash is **required** — without it, only a literal file at `~/work`
    would match. Use `gitdir/i:` for case-insensitive matching
    (relevant on macOS with case-insensitive filesystems). Symlinks
    are resolved, so cloning into a symlinked directory still matches
    the real path.

## Commit signing with SSH keys

The framework uses SSH keys (not GPG) for commit signing. SSH keys
are already managed for authentication; reusing them for signing
eliminates the GPG key management overhead entirely.

### The allowed_signers file

The `allowed_signers` file maps email addresses to public keys. Git
uses it to verify commit signatures:

```
dev@zftadvancements.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
you@billwoika.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
```

### Registering keys with GitHub

Add your SSH key to GitHub twice: once as an "Authentication Key"
(for push/pull) and once as a "Signing Key" (for commit signature
verification). Both entries use the same `.pub` file contents. After
registering, commits signed with that key show as "Verified" in the
GitHub UI.

## Diff and merge tools

The framework uses **delta** as the git pager. Delta provides
syntax-highlighted diffs, line numbers, and commit decorations. It is
configured in the main git config under the `[delta]` section.

## Useful aliases

The framework ships these in the git config itself (separate from the
[shell aliases](../shell-environment/aliases.md)):

| Alias | Command | Purpose |
|-------|---------|---------|
| `s` | `status -sb` | Short status with branch |
| `lg` | `log --oneline --graph --decorate --all` | Visual log |
| `last` | `log -1 HEAD --stat` | Last commit with stats |
| `branches` | `branch -vv --sort=-committerdate` | Branches by recency |
| `pushf` | `push --force-with-lease --force-if-includes` | Safe force-push |
| `uncommit` | `reset --soft HEAD^` | Undo last commit, keep changes |
| `amend` | `commit --amend --no-edit` | Amend without editing message |
| `cleanup` | merged branches | xargs branch -d | Delete merged branches |
| `whoami` | `config --list --show-origin` | Show all active config |
| `profile` | `config --show-origin user.email` | Show active identity |

## Repository maintenance

Periodic maintenance keeps large repositories fast:

```sh
# Run the full maintenance suite (repack, commit-graph, etc.)
git maintenance run --auto

# Enable scheduled maintenance (runs automatically)
git maintenance start
```
