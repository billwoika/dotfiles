# Tool-Enforced Practices

Git's flexibility is also its weakness: every team builds its own
conventions on top of the same primitives, and the conventions only
matter to the extent that engineers actually follow them. The reliable
way to make a practice stick is to make a tool enforce it.

This page covers the practices the framework can support concretely
— pre-commit hooks, repository-local hook configuration, commit-message
structure enforcement, branch protection, and lockfile discipline —
each backed by a specific tool or git configuration that produces
deterministic behavior.

!!! info "Scope of this page"

    Tool-enforced practices only. Conventions about *what to write in
    a commit message*, *when to rebase versus merge*, *how to
    structure a pull request description* — these belong in a team's
    engineering handbook, not in a tooling framework. The framework's
    job is to make the right thing easy and the wrong thing visible;
    the team's job is to decide what "right" means in the cases
    where reasonable engineers disagree.

## Pre-Commit Hooks via lefthook

The framework's recommended pre-commit hook runner is **lefthook**
(`evilmartians/lefthook`), pinned in `mise.toml` alongside the
project's other tools. lefthook is fast (Go binary, parallel execution
by default), language-agnostic, and configured via a single
`lefthook.yml` committed to the project root — making the team's hook
policy version-controlled and PR-reviewable.

### Why lefthook over alternatives

- **vs. `pre-commit` (the Python tool)** — pre-commit installs hooks
  in isolated Python environments, which is fine for Python projects
  but adds latency for non-Python projects. lefthook runs your
  project's existing tooling directly.
- **vs. `husky` (the Node tool)** — husky is fine for Node projects
  but binds you to npm/yarn/bun for hook management. lefthook is
  independent of any package manager.
- **vs. raw `.git/hooks/`** — raw hooks aren't shareable; each engineer
  has to install them manually. The standard escape hatch
  (`core.hooksPath`) addresses sharing but loses the parallel
  execution and the staged-files-only optimization that lefthook
  provides.

### Reference lefthook.yml

```yaml
# lefthook.yml — commit at project root
#
# After installing: `lefthook install` (once per clone) registers the
# hooks with git. The framework's bootstrap doesn't run this for you;
# each project does it as part of its own setup script or README.

pre-commit:
  parallel: true
  commands:

    # Lint only the files staged for commit — fast feedback,
    # no full-project sweep.
    biome:
      glob: "*.{js,jsx,ts,tsx,json}"
      run: bunx biome check --error-on-warnings {staged_files}

    ruff:
      glob: "*.py"
      run: uvx ruff check {staged_files}

    rubocop:
      glob: "*.rb"
      run: bundle exec rubocop --force-exclusion {staged_files}

    # Verify Markdown links don't break (cheap, runs on .md changes only)
    markdown-links:
      glob: "*.md"
      run: bunx markdown-link-check {staged_files}

    # Block commits that include the string "DO NOT COMMIT" (a marker
    # convention for "I'm leaving this in temporarily").
    no-do-not-commit:
      run: |
        if git diff --cached | grep -E "DO NOT COMMIT"; then
          echo "Found 'DO NOT COMMIT' in staged changes."
          exit 1
        fi

pre-push:
  commands:
    # Run the full test suite before a push to main.
    # Use `git push --no-verify` to skip in true emergencies.
    test:
      run: mise run test
      skip:
        - merge
        - rebase
```

!!! tip "Two important lefthook design choices"

    **First:** hooks run on *staged files only* (the `{staged_files}`
    token), not the whole project. A repository-wide lint sweep on
    every commit is a known pre-commit antipattern — it makes
    commits slow, encourages people to skip the hook, and produces
    lint failures unrelated to the change being made. Stage-scoped
    is faster and more focused.

    **Second:** `parallel: true` runs all commands concurrently. On a
    multi-core machine a 10-command pre-commit sweep finishes in
    roughly the time of the slowest command, not the sum of all of
    them. The serial alternative — the default in pre-commit and
    husky — is meaningfully slower in practice.

## Hooks-on-Clone via core.hooksPath

Even with lefthook, there's a coordination problem: `lefthook install`
has to be run once per clone, by each engineer, on each machine.
Engineers who clone a repo and start working without reading the
README never run it, and their commits skip the project's hook
policy.

The framework's recommended pattern: make hook installation part of
the project's one-time setup task in `mise.toml`:

```toml
# In the project's mise.toml [tasks] section:
[tasks.setup]
description = "One-time project setup; run after `git clone`"
run = """
  mise install
  lefthook install
  bundle install
  uv sync
"""
```

Engineers run `mise run setup` (or `make setup` via the wrapper) once
after cloning. The README's "Getting started" section opens with this
command.

Some teams go further and **auto-install lefthook on first commit**
using a small shell wrapper. This is a deliberate tradeoff: it's
friendlier for new contributors but adds a tiny amount of magic to
the first commit. The framework's recommendation is the explicit
`mise run setup` pattern — less magical, equally reliable, and the
setup step is a useful place for other one-time project initialization
(database migrations, seed data, dependency installation).

## Conventional Commit Hooks (Optional)

If the team has chosen to use Conventional Commits (`feat:`, `fix:`,
`chore:`, `BREAKING CHANGE:`, etc.), a commit-msg hook can enforce the
format. The framework is **neutral** on whether to use Conventional
Commits — it's a team norm, covered in the engineering handbook —
but if the team has chosen to, lefthook can validate the format on
every commit:

```yaml
# In lefthook.yml
commit-msg:
  commands:
    conventional-format:
      run: |
        # Only enforce on commits to feature branches, not merges or rebases
        head_commit=$(cat {1})
        if echo "$head_commit" | head -1 | \
           grep -qE '^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\(.+\))?: .+'; then
          exit 0
        fi
        echo "Commit message must follow Conventional Commits format."
        echo "  Examples: feat: add user search"
        echo "            fix(auth): correct OAuth redirect URL"
        echo "            chore!: drop Node 18 support"
        exit 1
```

!!! warning "On commit-msg hooks specifically"

    Commit-msg hooks are the most controversial of the hook types
    because they reject commits at the moment the engineer has just
    finished writing them. The friction is real, and it falls
    disproportionately on engineers new to the project. If you
    adopt this hook, ship it with a clear error message that
    explains the format and links to the team's commit-message
    documentation. The hook should be a teaching tool, not just a
    gatekeeper.

## Lockfile Discipline via .gitattributes

Lockfiles (`Gemfile.lock`, `uv.lock`, `bun.lock`, `package-lock.json`,
`Cargo.lock`) are generated artifacts that change with every dependency
update and produce noisy PR diffs. The framework's global
`.gitattributes` marks them as `linguist-generated`, which collapses
them by default in GitHub's PR-review UI.

```gitattributes
# Mark generated lockfiles
*.lock          linguist-generated=true
Gemfile.lock    linguist-generated=true
yarn.lock       linguist-generated=true -diff
package-lock.json linguist-generated=true -diff
bun.lock        linguist-generated=true -diff
```

For lockfiles where the format is genuinely opaque (`package-lock.json`,
`yarn.lock`, `bun.lock`), also add `-diff` to disable diff rendering
entirely — git prints "Binary files differ" rather than attempting to
render the diff. This is faster on commits that touch lockfiles and
avoids merge conflicts that look like meaningful changes but aren't.

Note the deliberate omission: `Gemfile.lock` and `uv.lock` are **not**
marked `-diff`. They're text-based, occasionally human-readable, and
reviewing their diffs sometimes catches genuine issues (a transitive
dependency upgrade that pulls in a sketchy package, a version
downgrade nobody intended). The framework keeps these as diffable text
but collapsed by default — the right blend of discoverability and
noise reduction.

## Branch Protection via gh CLI

GitHub's branch protection rules — require PR review, require status
checks to pass, restrict force-push, etc. — are typically configured
through the GitHub web UI. They can also be configured through the
`gh` CLI, which makes them scriptable, reproducible, and committable
as configuration.

The framework's recommended pattern: a `.github/branch-protection.sh`
script that sets the team's policy on the protected branch:

```sh
#!/bin/sh
# .github/branch-protection.sh
# Set branch protection on main to match the team's policy.
# Run once after repo creation or after policy changes.
set -eu

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/branches/main/protection" \
  -f required_status_checks[strict]=true \
  -f required_status_checks[contexts][]=ci/test \
  -f required_status_checks[contexts][]=ci/lint \
  -f enforce_admins=false \
  -f required_pull_request_reviews[required_approving_review_count]=1 \
  -f required_pull_request_reviews[dismiss_stale_reviews]=true \
  -f required_pull_request_reviews[require_code_owner_reviews]=false \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f required_linear_history=true

echo "Branch protection set on ${REPO}:main"
```

What this enforces:

- PRs require at least one approving review before merge.
- Status checks (CI: test, CI: lint) must pass before merge.
- Stale reviews are dismissed when new commits land — a reviewer who
  approved a PR three commits ago must re-review the latest version.
- Force-push to main is blocked. Engineers cannot accidentally rewrite
  shared history.
- Branch deletion is blocked. The main branch cannot be removed even
  by a repo admin.
- Linear history is required — PRs must be rebased or squash-merged,
  not merge-committed. This keeps `git log --oneline` readable
  indefinitely.

!!! note "On linear history specifically"

    Linear history (`required_linear_history=true`) is mildly
    opinionated. Some teams prefer merge commits as a way of
    preserving the historical fact of "these commits were on a
    branch." The framework's recommendation toward linear history is
    for projects where the linear `git log` is the primary
    historical artifact. For projects where the merge-commit
    topology genuinely matters (release branches, long-lived feature
    branches with their own histories), linear history may be the
    wrong choice. This is a team decision; the script above can be
    adjusted.

## Useful Patterns That Aren't Strict Enforcement

Two patterns worth mentioning that are encouraged by configuration but
not strictly enforced:

- **`commit.verbose = true`** (in main git config) shows the diff of
  staged changes in the commit-message editor. This makes engineers
  more likely to write accurate commit messages because the change is
  right there while they type — they can refer to specific lines,
  notice things they didn't intend to commit, and produce more useful
  messages.

- **`rebase.autoStash = true`** (also in main config) automatically
  stashes uncommitted changes before a rebase and reapplies them
  after. The alternative — "rebase failed because of uncommitted
  changes, you must stash manually" — is a small but persistent
  annoyance. autoStash makes the common case of "pull and rebase
  while I have local changes" just work.

Both are configuration, not enforcement — engineers can override
either in their personal config. The framework's stance: the team's
main config sets sensible defaults, individual engineers customize
where they have personal preferences, and PR review catches the cases
where customization produced something the team doesn't want.
