# Platform Portability

## Problem statement

A developer builds a dotfiles framework on their work-issued Mac. The
shell configuration is POSIX-compliant, the directory layout follows
XDG, the tool versions are managed by mise. By every structural
measure, the framework is portable. A year later, the developer
accepts a new role where the company issues Ubuntu workstations — or
they want the same framework on a personal Linux desktop, or they spin
up a cloud development environment running Fedora. The framework
breaks. Every onboarding step says `brew install`. Every SSH
instruction says `--apple-use-keychain`. The bootstrap script prints
macOS-only post-install guidance regardless of what `uname` reports.

The developer now faces a familiar choice: fork the framework and
maintain two copies, or spend a weekend retrofitting platform awareness
into a system that was structurally ready for it but never operationally
delivered.

### Why multiple platforms are the norm, not the exception

Most engineering departments issue Macs. macOS is the consensus
professional workstation for software teams outside of .NET and Azure
shops — the POSIX underpinnings are real, the hardware is uniform
enough to make MDM and compliance tractable, and the ecosystem of
developer tooling assumes it. But virtually everything the developer
builds — the APIs, the data pipelines, the infrastructure, the
container images — runs on Linux in production. The gap between the
development environment and the deployment target is a permanent
feature of the job.

Many developers also choose Linux for personal machines. Some prefer
the directness of developing on the same kernel family their code
ships to. Some work at companies that issue Linux workstations. Some
maintain home labs or side projects on hardware where macOS is not an
option. A dotfiles framework that works only on macOS serves only one
of these contexts — and the one it misses is often the one the
developer cares about most on their own time.

### Work and personal on a single machine

There is a related problem that compounds the platform question: most
serious developers carry a single laptop. The employee handbook says
that machine is for work only. The developer works 55 hours a week on
it. At some point they need to download a kid's permission slip, check
a personal email, review the results of a roof inspection, or push a
commit to a side project. This is not a hypothetical edge case — it is
the default state of affairs for any developer putting in long hours on
employer-owned hardware.

The policy position — strict separation between work machine and
personal life — is sound in principle. It is the correct default.
Regulatory environments enforce it for good reason: a military SOC, a
healthcare system handling PHI, a financial platform under SOX audit.
In those contexts, personal artifacts on a work machine are not a
minor policy violation but a compliance failure with real
consequences, and the right answer is a physically separate device.

But for the median web platform developer at a Series B startup, the
zero-tolerance policy is a fiction that everyone quietly violates and
no one has a framework for managing. The result is worse than the
policy intended: personal files scattered in Downloads, SSH keys with
ambiguous ownership, git commits signed with the wrong identity,
browser profiles that blur organizational boundaries. The absence of
structure does not produce separation — it produces *unmanaged*
mixing.

This framework takes the position that providing clean structure for
the messy reality is better than pretending the reality does not
exist. Path-based git identity (`~/work/` vs `~/personal/`), separate
SSH keys per context, host aliases that route through the correct
credentials — these are the operational patterns that make the
work/personal boundary explicit, auditable, and reversible. They do
not endorse personal use of work machines. They acknowledge that it
happens and ensure that when it does, the two contexts do not
contaminate each other.

**The caveat deserves equal weight.** In 99% of employee handbooks,
personal use of work equipment is explicitly prohibited. This
framework's separation patterns accommodate a pragmatic reality, not
an endorsed one. Whether the accommodation is appropriate depends
entirely on the regulatory and organizational context. Read the
handbook. Know the policy. If the policy is zero-tolerance and the
environment is high-compliance, the correct answer is a separate
machine — not a clever directory layout.

## What's wrong

Platform assumptions baked into documentation and scripts become
invisible walls. A framework that advertises POSIX compliance and XDG
compliance — portable by architecture — but only documents macOS
workflows delivers a false promise. The structure is portable; the
instructions are not. The developer who tries to use the framework on
Linux discovers this gap at the worst possible time: during initial
setup on a new machine, when they have the least patience for
debugging someone else's assumptions.

The same failure mode appears in the work/personal dimension. Without
explicit structure, the two contexts bleed into each other silently.
A git commit signed with a personal key lands in a work repository.
An SSH connection authenticates with the wrong identity. The developer
does not notice until a code review, an audit, or a failed deployment
surfaces the mistake.

## The principle

**Separate platform-specific behavior from platform-independent
behavior.** Isolate the varying dimension — which OS, which package
manager, which keychain API, which system PATH mechanism — from the
stable dimension: the configuration structure, the tool choices, the
directory layout, the identity model. This is Separation by Variation
applied to the infrastructure layer rather than the application layer.

The goal is not to port macOS idioms into Linux or vice versa. It is
to use each environment natively to accomplish the same tasks in the
way that leverages its strengths. Homebrew is the natural package
manager on macOS; `apt` and `dnf` are the natural package managers on
Debian and Fedora. macOS Keychain is the native secret store; Linux
Secret Service is the native secret store. Trying to shove `brew
install` into a Linux workflow — or `apt` into a Mac — is shoving a
round peg in a square hole. The framework shares the *what* (install
direnv, configure the SSH agent, expose mise shims to GUI
applications) and lets the *how* be native to each platform.

The same principle applies to context separation: isolate the
work-specific configuration (identity, signing keys, host aliases)
from the personal-specific configuration, with the stable dimension
being the shared framework that both contexts use identically.

## The patterns

Three patterns from this framework's own implementation:

### Runtime detection as a shared variable

```zsh
# conf.d/05-environment.zsh
case "$(uname -s)" in
  Darwin)   export OSTYPE_SHORT="macos"   ;;
  Linux)    export OSTYPE_SHORT="linux"   ;;
  FreeBSD)  export OSTYPE_SHORT="bsd"     ;;
  *)        export OSTYPE_SHORT="unknown" ;;
esac
```

A single detection point at the top of the startup chain. Every
downstream fragment that needs to branch on platform reads
`$OSTYPE_SHORT` rather than running its own `uname` call. The
detection is centralized; the branching is distributed.

### Guard clauses for platform-only blocks

```sh
# bootstrap.sh — only runs on macOS, skips silently elsewhere
if [ -d "/Applications/TextMate.app" ]; then
  link "/Applications/TextMate.app/Contents/Resources/mate" \
    "${HOME}/.local/bin/mate"
fi
```

```sh
# macos/setup-file-associations.sh — hard gate at the top
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is macOS-only." >&2
  exit 1
fi
```

Two styles for two situations. The soft guard (check and skip) is
right when the feature is optional and the script has other work to
do. The hard gate (check and exit) is right when the entire script
is platform-specific and running it elsewhere is always a mistake.

### Parallel documentation with content tabs

```markdown
=== "macOS"

    ```sh
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
    ```

=== "Linux"

    ```sh
    ssh-add ~/.ssh/id_ed25519_work
    ```
```

Neither platform is hidden behind a note box or buried in a
parenthetical. The reader selects their platform once; the site
remembers the choice across pages.

## When this is the right reach

When the tooling genuinely differs between platforms. Package
managers (`brew` vs `apt` vs `dnf`), keychain APIs (macOS Keychain vs
Linux Secret Service), system PATH mechanisms (`/etc/paths.d/` vs
`~/.config/environment.d/`), GUI application detection
(`/Applications/*.app` vs `.desktop` files). These are real
differences that cannot be papered over.

When documentation covers interactive setup steps — onboarding
runbooks, troubleshooting guides, optional post-install
configuration — that have different commands per OS.

When identity separation is needed: multiple git profiles, multiple
SSH keys, multiple signing identities that must not cross-contaminate.

## When this is the wrong reach

When the underlying tool is already cross-platform. mise, git, SSH
core configuration, tmux, direnv, starship, zoxide, fzf — all of
these work identically on macOS and Linux. Adding platform-conditional
branches for tools that behave the same on both platforms is ceremony.
It is the same failure mode the
[Design section introduction](index.md) warns about: a factory that
does nothing the constructor wouldn't, overhead with no payoff.

Containers are the strongest version of this argument. When the
runtime ships with the code — a Dockerfile that declares its base
image, its dependencies, its entry point — the host platform becomes
irrelevant. A containerized service runs the same whether the
engineer built it on macOS or Linux, because the container *is* the
platform. This is the benefit of containerization distilled to its
core: it eliminates the platform portability question entirely for
the artifact that matters most (the production runtime). The
platform-conditional work in this page applies to the *developer's
interactive environment* — the shell, the editor integrations, the
package manager, the SSH agent — precisely because those are the
pieces that containers do not standardize.

The same caution applies to context separation. A solo developer
working on a single personal machine with one GitHub account does not
need path-based git identity splitting, separate SSH host aliases, or
dual signing keys. The separation machinery exists for a real problem;
applying it where the problem is absent adds configuration surface
that must be maintained for no benefit.

## Common antipatterns

**"macOS-first, Linux-eventually."** Documenting only the primary
platform with a vague promise that "Linux steps differ slightly." The
Linux steps never get written. The promise rots. New users on Linux
discover the gap during onboarding and either leave or reverse-
engineer the equivalent steps without contributing them back.

**Dual maintenance.** Forking configuration files per OS rather than
sharing a single configuration with conditional branches. Two copies
of `10-path.zsh` — one for macOS, one for Linux — when the actual
difference is zero lines. The copies drift. Bugs fixed in one are not
fixed in the other.

**Platform leakage.** `brew install` appearing as the universal
installation command in documentation that claims to support Linux.
Homebrew is a macOS convention, not a Unix convention. The inverse is
equally wrong: pointing macOS users at `apt` packages. The failure
mode is treating one platform's idioms as portable when they are not —
each platform has a native way to accomplish the task, and the
framework should point to it rather than porting a foreign one.

**Policy as architecture.** Treating "the employee handbook says no
personal use" as a design constraint that eliminates the need for
context separation. The policy is correct; the assumption that it is
universally followed is not. The result is developers with no
framework for a situation they are already in.

## Questions to ask before reaching for it

1. Does this code actually behave differently between platforms, or
   am I over-conditioning?
2. Is the platform difference in the tool itself, or just in how it
   is installed? If the latter, the difference belongs in the
   onboarding doc, not in the runtime config.
3. Can we unify by choosing a cross-platform installation method? mise
   and many CLI tools offer `curl | sh` installers that work
   identically on macOS and Linux.
4. Does the context separation I'm adding solve a problem I actually
   have, or am I implementing it because the framework supports it?
5. If I'm in a regulated environment, is software-level separation
   sufficient, or does the compliance requirement demand physical
   separation?
