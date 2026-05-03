# Git Conventions

The framework's [Git Reference](../git/configuration.md) covers what
*can* be enforced by tools: pre-commit hooks, branch protection,
lockfile diff suppression, conventional commit hook validation. This
page covers what can only be adopted as norms: commit message style,
PR conventions, branching strategy, code review etiquette.

Teams should read this as a starting point and modify freely. Nothing
here is sacred; the framework's only firm position is that the team
should **agree on its conventions explicitly**, write them down, and
apply them consistently.

## Why these are conventions, not rules

The line between "rule" and "convention" matters. Rules can be enforced
mechanically — a pre-commit hook can reject a commit, branch protection
can prevent a force-push, CI can fail a build. Conventions can only be
adopted: they live in muscle memory, code review feedback, and the
shared mental model of the team.

The temptation is to make every convention into a rule, on the theory
that mechanical enforcement is more reliable than human discipline.
This is mostly wrong, for two reasons:

1. **Most conventions have legitimate exceptions.** A rule that rejects
   commits without a Conventional Commit prefix will reject the commit
   that fixes the urgent production incident at 2am. A rule that
   requires PR descriptions of a minimum length will reject the PR
   that's a single typo fix. Mechanical enforcement is brittle in ways
   human judgment is not.

2. **Rules atrophy understanding.** Engineers who are forbidden by a
   hook from doing the wrong thing don't develop the judgment about
   *why* it's the wrong thing. When the hook misfires (and hooks always
   eventually misfire), they have no internal model for what to do.

The framework's position: enforce the things that are non-negotiable
(security, irreversible mistakes, broken builds). Convention-ize the
things that require judgment (commit message quality, PR scope, review
depth). Trust engineers to develop the judgment.

## Commit messages

### Subject line

- **50 characters max, 72 absolute hard limit.** GitHub truncates
  subject lines past 50 characters in the PR view. `git log --oneline`
  becomes hard to scan past 72.
- **Imperative mood, present tense.** "Add user search" not "Added
  user search" or "Adds user search." This matches what git itself
  generates ("Merge branch X") and reads as an instruction the commit
  is performing.
- **Capitalize the first word, no trailing period.**
- **Always include the ticket number in the subject.** The full body
  of the commit is rarely read in practice; using the subject line
  allows for quick grepping of log outputs to isolate the linkage
  between tickets and commits.

### Body

- **Wrap at 72 characters.** `git log` formats commit bodies in a
  fixed-width view; longer lines wrap awkwardly. Most editors can be
  configured to wrap at 72 for git commit messages specifically — the
  framework's [vim configuration](../tools/editors.md) does this
  automatically for the `gitcommit` filetype.
- **Explain the *why*, not the *what*.** The diff shows what changed;
  the body should explain why it changed. "Refactored the auth flow"
  is bad. "The auth flow had three places that constructed Session
  objects with subtly different defaults; consolidating them prevents
  the class of bug where a session was missing the CSRF token" is good.
- **Reference issues and PRs in trailers**, not inline. `Closes: #1234`
  on its own line at the bottom; not "Closes #1234" in a paragraph.

### Trailers (optional)

If the team uses trailers, agree on which ones and use them
consistently. Common ones:

- `Co-authored-by: Name <email>` — for pair programming or significant
  collaboration. GitHub renders multiple authors on the commit page.
- `Closes: #1234`, `Fixes: #1234` — auto-closes the referenced issue
  on merge.
- `Refs: #1234` — for related issues that aren't being closed.
- `Signed-off-by:` — only if the team requires DCO sign-off.

### Conventional Commits (optional)

The framework is neutral on Conventional Commits. The arguments for:

- Tooling support (semantic-release, changelog generators) works
  automatically.
- Commit history is more scannable for "what kind of change is this?"
- Subject lines self-document scope.

The arguments against:

- Adds ceremony to every commit.
- Inappropriate prefixes (`feat:` for what's actually a bug fix because
  the engineer wasn't sure) produce a misleading category structure.
- Engineers spend time deciding which prefix to use instead of writing
  a good message.

Adopt if the team gets value from the tooling integration and is
willing to enforce the discipline. Don't adopt because it sounds
professional. If adopting, the framework can enforce the format via
[lefthook](../git/tool-enforced-practices.md#conventional-commit-hooks-optional).

## Branching

### Naming

- **Use a short, descriptive slug.** `add-user-search` not
  `feature/add-user-search-PROJ-1234-final-v2`.
- **Lowercase, hyphens, no underscores.** Match the conventions of
  GitHub URLs and most CI systems.
- **Personal branches in personal namespace.** Engineers can use
  `bill/scratch-test` for personal exploration; team branches are
  `add-user-search` without a prefix.
- **No long-running feature branches.** Branch lifetime should be
  measured in days, not weeks. Branches that live longer than a week
  drift from master and create progressively harder rebases.

### Rebase or merge?

This is the most contested decision in git workflow. The framework's
recommended position, defensible but not universal:

- **Rebase your feature branch onto master before merging.** Keeps the
  feature's commits on top of the master timeline, no merge commit
  pollution, `git log --oneline` stays linear and scannable.
- **Squash on merge if a feature branch has more than ~3 commits**
  that aren't individually meaningful (work-in-progress commits,
  fixups, "address review feedback" commits). The PR's final commit
  is what enters history; the work-in-progress is preserved in the PR
  itself for archaeology.
- **Don't rebase shared branches.** If two engineers are working on
  the same feature branch, rebasing it under them is a sin. Rebase
  only branches you own.
- **Don't rebase master.** This is enforced by
  [branch protection](../git/tool-enforced-practices.md#branch-protection-via-gh-cli).

The minority view: merge commits preserve the topology of "these
commits were developed on a branch," which is genuinely useful for
some forms of historical analysis. Teams with strong DBA-style
historical traditions sometimes prefer merge commits. Both are
defensible; pick one and stick with it.

## Pull requests

### PR descriptions

- **Lead with what and why.** First paragraph: what the PR does and
  why. Reviewers who are time-constrained should be able to make a
  reasonable approval/rejection decision from the first paragraph alone.
- **Mention what *isn't* changed if it's surprising.** "This refactors
  the auth flow but does not change the public API" — explicitly noting
  this saves the reviewer from worrying about it.
- **Include test plan or manual verification steps** for changes that
  aren't covered by automated tests. "Click the login button as user
  X, observe Y" is a real artifact that helps the next reviewer who
  has to debug a regression.
- **Link to the issue or design doc** if one exists. Don't restate it.

### PR templates

A `.github/pull_request_template.md` committed to the project produces
a consistent PR description structure. The framework recommends a
small template — three or four prompts — rather than a long checklist.
Long checklists get blindly checked off; short prompts get answered
thoughtfully.

```markdown
## What

<!-- One-paragraph summary. What does this PR do? -->

## Why

<!-- One-paragraph rationale. What problem does this solve? -->

## How (optional)

<!-- Implementation notes for the reviewer, if there are non-obvious
     design decisions worth flagging. Skip if the diff explains itself. -->

## Verification

<!-- How was this tested? Automated tests cover X; manually verified Y. -->
```

### PR scope

- **Smaller is better.** A 200-line PR gets reviewed in 15 minutes; a
  2000-line PR gets approved without being read.
- **One concern per PR.** Don't combine a refactor with a bug fix in
  the same PR — they have different review concerns and different
  revertability characteristics.
- **Stack PRs for related work.** If the work genuinely requires
  larger changes, structure them as a stack of small PRs (PR #1 sets
  up the new structure, PR #2 migrates the first call site, etc.).
  Tools like Graphite or `git absorb` make this easier.
- **Link PRs from different repos.** If the requirements dictate
  cross-repo modification, each PR should contain a reference to
  every other related pull request.

### Self-review

The single highest-leverage practice: **review your own PR before
asking anyone else to.** Look at the diff in the PR view (not the
local diff — the PR view shows what reviewers see). Catch the obvious
issues. Add inline comments to your own PR explaining non-obvious
choices, so reviewers don't have to ask. This catches roughly half of
the issues a reviewer would have raised, and shows respect for the
reviewer's time.

## Code review

### As an author

- **Respond to every comment.** Even if the response is just "Done"
  or "Won't fix because X." Silence on a review comment is corrosive.
- **Don't take feedback personally.** Code review is the work, not
  an attack on the work. Engineers who get defensive about review
  feedback get less of it, and produce worse code as a result.
- **Push back when warranted.** If a reviewer is wrong or asking for
  something you have a strong reason to disagree with, say so. Reviews
  are a conversation, not a checklist.

### As a reviewer

- **Review for correctness, not style.** Style should be enforced by
  formatters (biome, ruff, rubocop). If you find yourself commenting
  on whitespace or naming conventions a formatter could catch, the
  formatter is misconfigured.
- **Distinguish blocking comments from suggestions.** Use prefixes:
  `nit:` for non-blocking style suggestions, `q:` for questions that
  don't require changes, no prefix for blocking concerns. The author
  should be able to tell at a glance which comments require a response.
- **Approve when ready, even with open comments.** If the open
  comments are nits and questions, approve and let the author resolve
  them. Holding approval hostage to non-blocking feedback slows the
  team down.
- **Time-box reviews.** A review that takes longer than 30 minutes is
  too long; the PR is too large or the change too complex. Push back
  on PR scope rather than spending an hour on review.

### Review depth

This is the question with the least universal answer. Different teams
need different depths. Calibrate based on:

- **Risk.** Production payment processing gets line-by-line review;
  documentation typo fixes get a 30-second skim.
- **Familiarity.** Code in your area of expertise reviews faster; code
  in unfamiliar territory takes longer because you're learning while
  reviewing.
- **Author seniority.** A junior engineer's PR may benefit from
  detailed feedback; a senior engineer's PR may not need any.

The team should agree, explicitly, on what review depth is expected
for what kinds of changes. "Two LGTMs" is not an answer; "two LGTMs
for production-affecting changes, one LGTM for internal-only changes,
self-merge for documentation" is.

## When you make a mistake

Git is forgiving. The reflog (`git reflog`) records every commit
operation — including ones that "discarded" commits. Almost any
mistake can be undone within 30 days.

- **Pushed to the wrong branch?** Force-push the original state back
  (using `--force-with-lease`, never `--force`). The framework's
  `gpushf` [alias](../shell-environment/aliases.md) does this safely.
- **Reset a branch you didn't mean to?** `git reflog` shows the
  pre-reset SHA. `git reset --hard <sha>` restores it.
- **Deleted a branch you wanted?** `git reflog` shows the branch's
  last position. Re-create with `git checkout -b <branch> <sha>`.
- **Committed credentials?** Don't try to rewrite history yourself —
  the credentials are already on every clone of the repo. Rotate the
  credentials immediately; the rewrite is secondary cleanup.

The single rule for recovering from mistakes: **don't make the second
mistake.** The first instinct after a git mistake is often to do
something drastic. Stop, breathe, look at `git reflog`, ask for help
in Slack. The vast majority of git mistakes can be resolved with one
careful command; making it worse with a panicked second command is
how mistakes become disasters.

## What this page deliberately doesn't cover

- **Specific vendor issue-tracker workflow integration.** Each
  team's project management is too specific.
- **Release branch strategy.** Some teams need long-lived release
  branches; most don't. If you do, document yours separately.
- **Hotfix process.** Closely tied to release strategy and
  team-specific.
- **Trunk-based development vs GitFlow vs OneFlow.** Religious topic;
  most modern teams converge on a simple "branch from master, PR to
  master" pattern that doesn't need a name.
- **Specific commit-message template tooling** (commitizen,
  cocogitto). If the team adopts Conventional Commits, the framework's
  lefthook pattern handles validation; further tooling is optional.
