# Developer Environment Framework

An opinionated framework for personal development environments — mise-based,
XDG-compliant, dotfiles-driven, designed to be reproducible across machines
and honest about its choices.

This site is the in-depth reference. For a quick overview and install
instructions, see the [README](https://github.com/billwoika/dotfiles/blob/main/README.md).

## What you'll find here

The framework is organized by topic, mirroring how engineers actually look
things up:

- **[Shell Environment](shell-environment/index.md)** — zsh architecture, the `conf.d/` pattern,
  how the framework keeps shell state predictable across sessions
- **[Tools](tools/index.md)** — mise as the primary toolchain manager,
  Make as a thin task-runner wrapper, and how they work together
- **[Git](git/index.md)** — multi-identity setup, signing, the
  tool-enforced practices the framework supports concretely
- **[Operations](operations/index.md)** — secrets management with
  1Password and direnv, environment isolation, project-level patterns
- **[Handbook](handbook/index.md)** — opinionated guidance on practices
  and design decisions: the separation skill, when to reach for design
  patterns and when not to, with the Reference's configuration content
  as the practical counterpart
- **[Reference](reference/index.md)** — the customization placeholder
  table, version notes, and the relationship between this site and
  earlier framework versions

Pages are short, opinionated, and practical. The framework's primary
contribution is the *coherence* of the choices — every recommendation
fits with the others, and deviations are flagged as deliberate
deviations rather than left implicit.

## Three layers, one framework

The framework is structured into three deliberate layers, each with a
distinct audience and purpose:

!!! note "Layer 1 — the README"
    Short-form overview, installation instructions, the quick map. About
    a 15-minute read. If you want to know whether the framework is for
    you, start there.

!!! info "Layer 2 — this docs site"
    The detailed reference. Topic-based pages with specific patterns
    and rationale. **This is where you look when you have a specific
    question** — "how does the multi-identity git setup actually work?"

!!! tip "Layer 3 — runbooks alongside code"
    Operational knowledge that's specific to a particular service or
    deployment doesn't live here — it lives in the project repo that
    owns those operations. The framework provides patterns; runbooks
    instantiate them.

## Stability

The framework is on its 7th major iteration as of 2026. The recent
work has been:

- **v2.4** — Container chapter (runtime-agnostic Docker / Podman / OrbStack)
- **v2.5** — Make as a thin wrapper around mise tasks
- **v2.6** — Editor and IDE chapter (50+ pages covering VS Code, JetBrains,
  the IDE-spawned subprocess problem, debugging, LSP, source control, DDL)
- **v2.7** — Tool-enforced git practices (lefthook, branch protection),
  migration to MkDocs (this site)

Older versions are preserved as Word document snapshots in the
[archive directory](https://github.com/billwoika/dotfiles/tree/main/archive)
of the repo.

## License

[GPLv3-or-later](https://www.gnu.org/licenses/gpl-3.0.html).
Copyright © 2026 Bill Woika.

GPLv3 was chosen deliberately. Internal use within an organization is
unrestricted; distribution of derivatives requires preserving the same
license.
