# Git

Git's flexibility is also its weakness: every team builds its own
conventions on top of the same primitives, and the conventions only
matter to the extent that engineers actually follow them.

The framework's git story has two parts:

1. **Configuration patterns the framework provides** — multi-identity
   setup via path-based profiles, commit signing with SSH keys,
   sensible defaults via `~/.config/git/config`, `.gitattributes` and
   `.gitignore` patterns at the global and project level.

2. **Tool-enforced practices the framework supports concretely** —
   pre-commit hooks via lefthook, branch protection scripted via
   `gh`, lockfile diff suppression via `.gitattributes`. See the
   [Tool-Enforced Practices](tool-enforced-practices.md) page.

What's deliberately **not** in the framework's git story: convention
claims about what to write in commit messages, when to rebase versus
merge, how to structure pull requests, code review etiquette. Those
belong in a team's engineering handbook, not in a tooling framework.

## In this section

- **[Configuration](configuration.md)** — XDG-compliant config,
  path-based identity profiles, commit signing with SSH keys, the
  delta pager, and useful aliases.
- **[Tool-Enforced Practices](tool-enforced-practices.md)** —
  pre-commit hooks, branch protection, lockfile discipline,
  conventional commit hooks, and the patterns that aren't strict
  enforcement.
