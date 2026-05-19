# Developer Environment Framework

An opinionated framework for personal development environments — mise-based,
XDG-compliant, dotfiles-driven, designed to be reproducible across machines
and honest about its choices.

This site is the in-depth reference. For a quick overview and install
instructions, see the [README](https://github.com/billwoika/dotfiles/blob/master/README.md).

## What you'll find here

The site is organized into three sections:

- **[Reference](reference/index.md)** — start here. Repository
  structure, onboarding runbook, customization guide, test suite, and
  troubleshooting. Everything you need to clone, install, and
  configure the dotfiles.
- **[Framework](shell-environment/index.md)** — the detailed
  documentation for every component: shell environment, toolchain
  (mise, Make, containers, editors), git configuration, and operations
  (secrets, SSH, networking). Bound to the dotfiles artifact.
- **[Philosophy](handbook/index.md)** — opinionated arguments about
  engineering practice and design: separation as a meta-skill, git
  conventions, value types, platform portability. Rigorous positions,
  honestly contestable. Decoupled from the dotfiles themselves.

Pages are short, opinionated, and practical. The framework's primary
contribution is the *coherence* of the choices — every recommendation
fits with the others, and deviations are flagged as deliberate
deviations rather than left implicit.

## Three layers, one framework

!!! note "Layer 1 — the README"
    Short-form overview, installation instructions, the quick map. About
    a 15-minute read. If you want to know whether the framework is for
    you, start there.

!!! info "Layer 2 — this docs site"
    Three sections: **Reference** (install, configure, troubleshoot),
    **Framework** (detailed documentation per component), and
    **Philosophy** (opinionated arguments about engineering practice).

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
[archive directory](https://github.com/billwoika/dotfiles/tree/master/archive)
of the repo.

## License

[GPLv3-or-later](https://www.gnu.org/licenses/gpl-3.0.html).
Copyright © 2026 Bill Woika.

GPLv3 was chosen deliberately. Internal use within an organization is
unrestricted; distribution of derivatives requires preserving the same
license.
