---
hide:
  - navigation
---

# Developer Environment Framework

An opinionated framework for personal development environments —
mise-based, XDG-compliant, dotfiles-driven, designed to be
reproducible across machines and honest about its choices.

Most dotfiles repositories are collections of configuration files with
a bootstrap script. This framework is that too, but it is also a set
of documented positions about how a development environment should
work and why. The dotfiles are the implementation. The documentation
is the reasoning. Both ship together because the reasoning is what
makes the implementation coherent rather than arbitrary.

This site is the in-depth reference. For a quick overview and install
instructions, see the
[README](https://github.com/billwoika/dotfiles/blob/master/README.md).

## What you'll find here

The site is organized into three sections. Each serves a different
audience and a different purpose.

### [Reference](reference/index.md)

Start here. The Reference section is the operational manual for the
dotfiles themselves: repository structure, platform-specific setup
guides (macOS, Fedora, Debian/Ubuntu), an onboarding runbook that
takes a fresh machine to a working development environment, the
customization guide for making the framework your own, the test suite
that validates POSIX profile compliance, and troubleshooting for when
things go wrong.

If the question is "how do I install this, configure this, or fix
this," the answer is in Reference. Every page is bound to a specific
artifact in the repository — a config file, a script, a directory
structure — and stays current with the code.

### [Framework](shell-environment/index.md)

The detailed documentation for every component the framework manages.
This is where the architectural decisions live.

**Shell Environment** covers the full zsh startup chain from
`~/.zshenv` through `conf.d/` fragments, the POSIX profile that
serves as the subprocess shim for non-zsh processes, XDG compliance,
environment variable layering, performance constraints, the strategy
for handling tool installers that want to inject lines into shell
startup files, and a command-line techniques reference covering
piping, redirection, heredocs, grep, sed, awk, xargs, printf, and
the macOS/Linux coreutils divergences that break shell scripts.

**Tools** documents the framework's positions on mise as a polyglot
runtime manager, Make as a thin task-runner wrapper, package managers
(Homebrew, apt, dnf), code quality tooling (linters and formatters
with the distinction between them), containers and devcontainers,
editor and IDE configuration, browser developer tools, and database
and API tooling.

**Git** covers the framework's git configuration (aliases, merge
strategy, diff tooling) and the tool-enforced practices that keep
repositories clean: lefthook for pre-commit and pre-push hooks,
branch protection as policy, and commit hygiene as habit.

**Operations** addresses the infrastructure layer: secrets management,
SSH and key management, and networking (VPN, DNS, container
networking, proxy and traffic capture).

Each page explains not just the what but the why — the trade-offs
considered, the alternatives rejected, and the conditions under which
the framework's choice would be wrong.

### [Philosophy](handbook/index.md)

Opinionated arguments about engineering practice and design, decoupled
from the dotfiles themselves. These pages are the framework's
positions on how software should be built, not how a development
environment should be configured.

**Git Conventions** makes the case for specific commit, branching, and
review practices — not as rules to memorize but as habits that
compound over the life of a codebase.

**The Case for Code Quality** argues that linting and formatting are
not style preferences but engineering practices with measurable
returns, and draws the distinction between the two.

**Logging** makes the case that structured logging is the only
reliable form of operational output. Covers twelve-factor log
management (application writes to stdout, infrastructure routes),
trace ID generation and hierarchical correlation, enumerated event
types and named exceptions, PII redaction discipline, distributed
tracing via OpenTelemetry, and the vendor lock-in cost of
proprietary instrumentation SDKs.

**Tactical Posture** addresses how to approach a codebase — the habit
of understanding global context before making local changes. Covers
the propagation problem (code spreads and its damage compounds
silently over time), the one-liner illusion (textual size is not
behavioral size), the refactoring trap (fixing everything at once
instead of scoping to what is needed), and the superstructure beyond
the code: the business vertical, the user expectations, and the
contracts that the codebase serves.

**The Layers** presents an illustrative five-layer model for thinking
about software systems — infrastructure, data, application logic,
presentation, and observability. Examines how dependency direction
determines blast radius, how the industry has systematically
flattened layers through managed services and database-as-API
products (Prisma, Firebase, MongoDB), and why the commercial
incentive to minimize time-to-first-feature often reintroduces the
coupling that layers were designed to prevent.

**Testing** is an honest treatment of testing as necessary ceremony.
Covers tests as contract enforcers (not coverage metrics), the
tautology problem (tests that assert what was just constructed), the
testing hierarchy with frank assessments of each level's failure
modes, and an RSpec-specific pitfalls guide covering context nesting,
invisible setup, lazy evaluation traps, collection matcher selection,
and async job testing.

**Design** is the largest section in the handbook, organized around a
single underlying question asked at multiple scales: *what code
belongs together, and what code belongs apart?*

The Design section is split into two parts. **Foundations** covers
Separation of Concerns (the vocabulary of change-drivers, god
classes, and the cost of both entangled code and premature
separation) and Locality (file organization strategies, boundaries
and contracts, the discipline that makes any strategy work, and
encapsulation as an entailed consequence of sound boundary design).
**Patterns** covers Decoupling Patterns (the evolution from
enumerating behaviors to discovering them — registries, factories,
dependency injection, and the builder pattern as production
architecture with testability as the diagnostic signal), a detour
into the Metaprogramming Trap (why implicit magic is almost always
the wrong reach in application code), and Value Types (modeling data
by how it is used rather than what it looks like, TypeScript's type
system as a contract that must be honored, and domain expertise as
the foundation of typing discipline).

Every position acknowledges where it is wrong. The framework's stance
is that patterns are tools to be evaluated, not orthodoxies to be
defended — opinionated, but more interested in helping the reader
decide than in declaring what is correct.

## How this site is built

The documentation is a [MkDocs](https://www.mkdocs.org/) site using
the [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)
theme. The source lives in the `docs/` directory of the
[dotfiles repository](https://github.com/billwoika/dotfiles). The
site builds and deploys automatically on push to `master`.

## License

[GPLv3-or-later](https://www.gnu.org/licenses/gpl-3.0.html).
Copyright 2026 Bill Woika.

GPLv3 was chosen deliberately. Internal use within an organization is
unrestricted; distribution of derivatives requires preserving the same
license.
