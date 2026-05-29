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
from the dotfiles themselves. Sixteen pages covering how to think about
software — not how to configure a development environment.

**Tactical Posture** addresses how to approach a codebase: understand
the global context before making the local change. The propagation
problem, the one-liner illusion, the refactoring trap, and why
understanding the superstructure — the business, the users, the
contracts — is what separates engineers from linters.

**The Layers** presents an illustrative five-layer model
(infrastructure, data, application logic, presentation,
observability) for reasoning about software systems. Dependency
direction and blast radius, the data layer's coupling to
infrastructure (including the `AT TIME ZONE` inversion between
PostgreSQL and Redshift), the document store validation problem, and
the industry's flattening of layers through managed services and
database-as-API products.

**Design Principles** establishes the framework's position that
patterns are tools, not goods — and that the meta-skill is
recognizing which kind of separation problem you are facing.
Five pages follow, each addressing a distinct form of the question
*what code belongs together, and what code belongs apart?*

- **Separation of Concerns** — change-drivers, god classes, the cost
  of entangled code and premature separation.
- **Locality** — file organization, boundaries and contracts,
  encapsulation, boundary violations in Rails.
- **Decoupling Patterns** — registries, factories, dependency
  injection, the builder pattern, testability as the diagnostic
  signal.
- **The Metaprogramming Trap** — why implicit magic is the wrong
  reach in application code, and why the measure of quality is
  whether the team can work with it.
- **Value Types** — modeling values by usage not representation,
  TypeScript's type system as a contract, domain expertise as the
  foundation of typing discipline.

**The Case Against Least Privilege** is a deliberately heterodox
argument that the principle of least privilege as practiced today
produces the opposite of its intended outcome. The implementation has
drifted from restricting write access to production systems (where the
risk lives) to restricting read access to everything (where the cost
is invisible). Knowledge silos, organizational amnesia, the IAM
paradox, and the elitist architecture that results when the people who
design access policies give themselves all access and do not
experience the friction they impose on everyone else.

**The Case for Code Quality** argues that linting and formatting are
engineering practices with measurable returns, not style preferences.

**Error Handling** treats errors and exceptions as the highest-priority
signal in the system. Catch quickly, present appropriately: blocking
errors get human-friendly messages and support references,
non-blocking errors are absorbed and reported internally. Fail fast
vs graceful degradation, error boundaries by architectural layer,
the exception vs return-value debate, the swallowed-error
anti-pattern, and alert fatigue — including the vendor whose expired
SSL certificates went unnoticed for months because the daily failure
was indistinguishable from the noise floor.

**Logging** covers structured logging as the only reliable operational
output. Twelve-factor log management, trace ID generation, enumerated
events, PII redaction, distributed tracing via OpenTelemetry, and
vendor lock-in.

**Testing** is an honest treatment of testing as ceremony worth
maintaining. Contract enforcement, the tautology problem, the testing
hierarchy, RSpec pitfalls, coverage thresholds, and time-dependent
heisentests.

**Code Review** addresses the hardest management skill disguised as a
technical practice. The reviewer's dilemma: responsible for every line
the team ships, but rewriting every commit in your own image defeats
the purpose of having a team. The resolution is reviewing at the right
layer — contracts and design decisions get scrutiny, implementation
details get trust. How to give reviews that teach rather than police,
how to receive them without defensiveness, and the failure modes that
turn review into either a rubber stamp or a bottleneck.

**Technical Debt** defines what the term actually means — and what it
does not. Three forms of real debt (deliberate trade-offs, entropy,
ignorance) distinguished from the fourth thing that gets called debt
but is actually a design preference. Covers how to make the business
case in the language of cost, risk, and opportunity, and when the
rational decision is to accept the debt rather than repay it.

**Git Conventions** covers commit style, PR conventions, branching
strategy, code review, and mistake recovery.

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
