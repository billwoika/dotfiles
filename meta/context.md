# meta/context.md (formerly .claude-context.md)

> **Audience.** This document is written by Claude (the model used to
> co-author this repository) and addressed to two audiences:
>
> 1. **Future-you, Bill** — when you're scanning to remember what we
>    decided about something and why
> 2. **Future Claude** — a different instance of me, in a future session,
>    trying to reconstruct enough context to be useful without
>    re-litigating settled questions
>
> Throughout, "I" refers to Claude as the writing voice. "You" refers to
> the future reader, whether human or model. "We" refers to the
> collaboration that produced this work. The document records decisions
> that have been firmly made and is meant to prevent re-derivation, not
> to foreclose revisitation — if you want to change a decision, change
> it deliberately, and update this document so the change is visible.
>
> **A caveat about this document's own reliability.** This is an
> account written by Claude about Claude's behavior, partly from active
> conversation memory and partly reconstructed from prior-session
> transcripts. It is itself subject to the failure modes it documents:
> tidy-narrative bias, soft-pedalling of mistakes, possible factual
> drift in earlier-session details. Treat it as evidence with caveats,
> not as ground truth.

---

## 1. What this repository is

The repository (`dotfiles`) is two artifacts in one:

1. **A working set of dotfiles** — real configuration files that run on
   Bill's daily-driver machines: zsh setup, mise toolchain config,
   direnv, git profiles, ssh, tmux, vim, VS Code and JetBrains
   templates, devcontainer reference, macOS opt-in helpers, POSIX
   `~/.profile` shim with a 30-test test suite.

2. **A docs site** that explains the framework underlying those
   dotfiles — published via MkDocs Material to GitHub Pages from the
   `docs/` directory. This is the in-depth reference that complements
   the dotfiles.

The two artifacts ship together in a single repo. The reasoning:
maintaining one publishing pipeline, one license, and one cadence is
sustainable; maintaining two parallel artifacts (separate dotfiles and
docs repos) would be more work for no reader benefit.

The documentation was originally a Word document built via `docx-js`,
versioned through 7 major iterations (v2.0 → v2.7). At v2.7 the
canonical source moved to MkDocs. The frozen Word manuscript is
preserved in `archive/v2.7-snapshot.docx` (209 pages, 227 KB).

## 2. Project shape and current state

**Repository layout** (reconciled 2026-05-31; the initial-commit
snapshot this section originally carried was stale by ~75 files):

```
dotfiles/
├── LICENSE                  GPLv3-or-later, Bill Woika 2026
├── README.md                Layer-1 short-form intro
├── CLAUDE.md                Claude Code project instructions (points here)
├── mkdocs.yml               MkDocs Material site config
├── bootstrap.sh             Idempotent symlink installer
├── profile                  ~/.profile — POSIX shim
├── .editorconfig + .editorconfig.example
├── .gitignore + gitignore.example
├── .github/workflows/docs.yml    Auto-deploy MkDocs to gh-pages
├── meta/                    Internal repo docs — NOT published to the site
│   └── context.md           This handoff artifact (was .claude-context.md at root)
├── _drafts/                 Excluded from MkDocs build
├── archive/                 Word manuscript snapshots (v2.7-snapshot.docx)
├── docs/                    MkDocs source — EVERYTHING here is published
│   ├── index.md
│   ├── framework-platform-portability.md
│   ├── requirements.txt     Pinned MkDocs dependencies
│   ├── shell-environment/   (renamed from shell/ — Cloudflare WAF on "shell")
│   ├── tools/
│   ├── git/
│   ├── operations/          (SSH lives here)
│   ├── reference/           index, customization, onboarding, repository,
│   │                        test-suite, troubleshooting
│   │   ├── platform-setup/  macOS / Fedora / Debian-Ubuntu / disk / firmware
│   │   └── firmware/        Firmware and UEFI section
│   ├── handbook/            Opinion-heavy companion section
│   │   └── design/          7 separation stubs + metaprogramming-trap
│   └── stylesheets/
├── zsh/                     22 files — zshenv shim + .z* + 17 conf.d/ fragments
├── mise/config.toml         User-scope mise config
├── direnv/direnvrc          1Password / Vault / sops helpers
├── git/                     config, ignore, attributes + 4 .example profiles
│                            (work, personal, opensource, allowed_signers)
├── ssh/config.example
├── tmux/tmux.conf
├── vim/vimrc
├── vscode/                  3 reference templates (settings, extensions, launch)
├── jetbrains/               README + runConfiguration XMLs
├── macos/                   File-association setup script
├── linux/                   Linux-only opt-in helpers (parallel to macos/)
├── devcontainer/            Reference templates
└── sh/tests/profile_test.sh POSIX test suite (30 tests)
```

**File counts (2026-05-31):** 140 git-tracked files. Docs grew from the
5-page proof-of-concept to 75 Markdown pages across the published site.

**Build state (verified 2026-05-31):**

- 22 zsh files (startup chain + 17 conf.d fragments) pass `zsh -n`
- `profile` and `bootstrap.sh` pass `sh -n`
- POSIX test suite passes 30/30
- `bootstrap.sh --dry-run` is clean
- All `.example` templates referenced by bootstrap exist

## 3. Locked-in decisions, organized by topic

This is the substantive ledger. Each entry records the decision, the
reasoning, and where in the artifacts the decision is realized.

### 3.1 Licensing

**Decision: GPLv3-or-later, with Bill Woika as copyright holder.**

The license file at `LICENSE` opens with a Bill Woika copyright notice
and the "or any later version" clause, then includes the canonical
GPLv3 text below.

Reasoning: Bill explicitly chose GPLv3 over MIT after considering both.
The reasoning was that the framework is personal-portable — Bill
intends to be able to use it at his employer (Springbig) and elsewhere
— and GPLv3's copyleft clause protects against the framework being
forked, modified, and redistributed by any future entity in a way that
removes the freedoms it was distributed with. Internal use within an
organization is unrestricted (no distribution = no GPL trigger). If
someone later tries to package and redistribute the work externally,
the copyleft clause kicks in.

The earlier candidate was MIT. Bill switched to GPLv3 deliberately,
not by default. From the April 28 session: "Yea, they won't care about
the GPL, and the scenarios where they would package or redistribute
would be against my wishes most likely, so I want it to trigger then."

Realized in: `LICENSE` (root). Referenced in `docs/index.md` and
`README.md`.

### 3.2 Repository arrangement

**Decision: One repo. The dotfiles repo absorbs MkDocs.**

The repo is `dotfiles` (kept as the name even though it's now also the
docs source). Adding `docs/` and `mkdocs.yml` at the repo root was
preferred over renaming the repo because (a) renames have knock-on
effects on URLs, clones, and the dotfiles-as-personal-artifact
framing; (b) "dotfiles" is accurate enough as a name even though it
undersells the scope.

Realized in: the entire repo structure.

### 3.3 Three-layer documentation model

**Decision: README → docs site → runbooks-alongside-code.**

- **Layer 1 (README.md)** — short-form overview, install instructions,
  the quick map. ~15-minute read.
- **Layer 2 (docs site)** — detailed reference, topic-based pages with
  patterns and rationale. The "where you go for a specific question"
  artifact.
- **Layer 3 (runbooks alongside code)** — operational knowledge that
  belongs in the project repo it operates on, not in the framework.
  The framework provides patterns; runbooks instantiate them.

Realized in: `README.md` (Layer 1), `docs/` (Layer 2). Layer 3 is a
pattern, not an artifact in this repo.

### 3.4 Reference vs Handbook split

**Decision: The docs site has two distinct sections — Reference and
Handbook — with different purposes and content rules.**

- **Reference** — concrete recommendations bound to specific artifacts
  in the dotfiles. "Use mise. Configure git this way. Run lefthook for
  pre-commit hooks." Practical and actionable.
- **Handbook** — opinionated guidance on practices and design decisions.
  Architecture patterns, code-quality practices, design pattern usage.
  Business-logic-agnostic. Covers when *not* to apply patterns as
  primary content.

The two sections are peer top-level nav items in `mkdocs.yml`. Each
serves the same audience (engineers using or evaluating the framework)
but answers different questions: Reference answers "how do I configure
X?"; Handbook answers "should I introduce Y here, or is it overkill?"

This split was the result of meaningful conversational refinement —
Bill initially proposed splitting the documents entirely (a quickstart
plus a separate philosophical treatise), and I pushed back on that
framing as undersized for the dev-environment content and oversized
for the practices content. We landed on one repo, one MkDocs site,
two distinct sections.

Realized in: `mkdocs.yml` nav (Handbook between Operations and
Reference); `docs/handbook/index.md` and `docs/handbook/design/index.md`
articulate the separation explicitly.

### 3.5 Handbook audience: engineers at all levels

**Decision: Every Handbook page must work for engineers at all levels.**

The framing target:

- A junior engineer who hasn't seen the patterns named, doesn't yet
  have intuition for when each one applies
- An intermediate engineer who knows the pattern names but applies
  them indiscriminately, and would benefit from explicit framing of
  when *not* to reach for them
- A senior engineer who knows the patterns cold and is reading to find
  out whether the framework's positions add anything

Bill specifically corrected an earlier assumption I had made — that
the Handbook could assume engineers already knew DI, factories,
adapters. He pointed out that "there are far more jr and intermediate
level developers who do not know what, say, a factory or builder
pattern is, and even more who know the term but don't know how to
leverage it or when." This audience reframe is binding.

The implication for content: pages must teach the pattern enough that
juniors can engage, surface evaluation skills as the primary
contribution (because evaluation is the missing skill in most
existing tutorials), and use realistic examples (no contrived `Square
extends Shape`).

Realized in: `docs/handbook/index.md` (states this explicitly).

### 3.6 Handbook rhetorical pattern

**Decision: Every Handbook page follows the same rhetorical structure.**

1. **Concrete problem statement** — a specific, recognizable scenario
   from real codebases. No abstract principles upfront.
2. **What's wrong** — concrete consequences (failed tests, wasted
   debugging time, broken refactors), not abstract violations.
3. **The principle** — stated in terms of the page's main concept
   (e.g. separation, in the Design section).
4. **The pattern(s) that operationalize the principle** — with
   realistic examples in Ruby or Python.
5. **When this is the right reach** — specific situations.
6. **When this is the wrong reach** — equally specific. Roughly equal
   weight to #5.
7. **Common antipatterns** — named failure modes from over- or
   misapplication.
8. **Questions to ask before reaching for it** — a short evaluation
   checklist.

This pattern was specifically requested by Bill: "There's nothing
worse than a solution without a problem in software development, and
finding the right problem that we're going to demonstrate how to
solve, one way or another, I think is a good way to keep both
audiences captivated throughout the section."

Realized in: `docs/handbook/design/index.md` (states the pattern
explicitly for all section pages to follow).

### 3.7 Design section: separation as the unifying meta-skill

**Decision: The Design section is organized around "separation" as
the underlying meta-skill, not as a topic-by-topic catalog of patterns.**

The seven topics:

| Page | Separation problem | Pattern(s) introduced |
|------|---------------------|----------------------|
| separation-of-concerns | Mixed concerns in single units | Foundational vocabulary |
| locality | Where in the file tree code lives | Co-location vs layered |
| separation-by-lifecycle | Construction vs use | Factory pattern |
| separation-by-dependency | Code vs its collaborators | Dependency injection |
| separation-by-boundary | Domain vs external world | Adapter pattern |
| separation-by-variation | Stable vs varying behavior | Strategy, factory's variant role |
| value-types | Stringly-typed code | Constants, enums, value objects |

The framing came from Bill: "I think those are both examples of the
larger topic of 'separation' as such. Why does code live where it
does in relationship to other code? Do we co-locate code near its
execution runtime neighbors? Or we enforce the directory standardized
as a map to locating the right fragment?"

This reframing replaced an earlier topic-list approach (god classes,
factories, DI, adapters, etc.) that I had proposed. The separation
framing is structurally better because (a) it surfaces the meta-skill
rather than just the patterns, (b) it produces better cross-references,
and (c) new patterns the framework wants to take positions on can be
added as new "answers to separation problems" without restructuring.

Realized in: `docs/handbook/design/index.md` and the seven stub pages.

### 3.8 Design section: page length and tone

**Decision: 1500-2500 words per page; opinionated but honest about
counter-positions.**

The audience constraint (working for juniors and seniors
simultaneously) plus the rhetorical pattern (8 distinct sections per
page, with realistic examples) requires real content density. Earlier
estimates of 600-1000 words per page were unrealistic. 4-6 pages each,
~2000 words.

The tone the framework has used throughout — "opinionated but
acknowledges counter-positions" — extends into the Handbook. Every
position takes a clear stance and acknowledges legitimate counters
honestly. "When this is right" and "when this is wrong" get roughly
equal space.

Realized in: `docs/handbook/index.md` (states the discipline);
`docs/handbook/design/index.md` (sets the pattern); the section as it
gets written.

### 3.9 Placeholder convention

**Decision: Distinctive real strings as placeholders; substitute by
sed when forking.**

The convention table:

| Placeholder | Used for |
|-------------|----------|
| `springbig` (lowercase, hyphenated) | Org name, repo paths, kebab-case identifiers |
| `springbig.com` | Org domain, public URLs |
| `springbig.internal` | Internal infrastructure suffix |
| `bastion.springbig.internal` | Specific bastion host |
| `staging-db.springbig.internal` | Specific internal DB host |
| `billwoika.com` | Personal domain |
| `dev@springbig.com` | Work email / git identity |
| `you@billwoika.com` | Personal email / git identity |
| `your-username` | SSH user, GitHub username |

Reasoning: Distinctive real strings (`springbig`, `billwoika`) are
easier to grep-and-replace than generic placeholders precisely because
they don't collide with anything else. A `sed` pass replacing
`springbig` with `acme` will only touch the framework's placeholder
text.

Bill's reasoning: "given that it's an actual company with limited
duplication for any other possible reason, it will be very easy to
grep."

Templating (Jinja, MkDocs macros) was considered and rejected —
literal strings stay readable in any markdown viewer without a build
step, and substitution is a one-time forking action, not a per-build
step.

Realized in: every artifact in the repo. `docs/reference/customization.md`
documents the convention as the canonical reference.

### 3.10 What's deliberately not in the framework

**AI tooling.** Deferred until Bill's bespoke unifying solution for
AWS SSM/IAM identity management is finalized. The AI document needs
specific, concrete recommendations to be useful, and abstract
guardrails essays without that grounding are easy to write and hard
to act on. Bill's words: "I'm still finalizing my answer."

**Application-code architecture as a standalone treatise.** I
initially misread Bill's "architecture" pivot as wanting a separate
DDD/clean-code book. Bill clarified: the architecture content is
*part of the framework as a section*, not a separate treatise.

**Cursor (the IDE).** Excluded by Bill explicitly: "I don't like it,
and it's just a vscode derivative with a proprietary model built on
top." Mention removed from any IDE chapter content.

**Bespoke AWS SSM/SSH wrapper functions.** Originally `aws-ssh` shipped
in `conf.d/65-aws-aliases.zsh` and embedded Springbig's environment
naming convention. Bill is finishing a separate tool for AWS identity
management, so the entire `65-aws-aliases.zsh` was removed and
Appendix B.6 in the manuscript was rewritten to acknowledge that
"once your AWS usage is more than occasional, write a real tool
tailored to your org's IAM model."

**Plugin managers for zsh** (oh-my-zsh, prezto, zinit). The framework's
`conf.d/` pattern provides composability without the dependency.

**Default-installed prompt frameworks** (starship, powerlevel10k). The
framework's prompt is small zsh; engineers who want fancier add it
themselves.

**Framework-level dotfile managers** (chezmoi, yadm). Plain symlinks
are obvious about what they do.

**Fish, nushell, or other non-POSIX-derived shells.** The framework's
`~/.profile` shim is what makes the subprocess story work; switching
the primary shell to a non-POSIX shell breaks it.

**Multi-desktop Linux support (KDE / Sway / i3 equivalents).** The
framework's Linux desktop guidance assumes **GNOME on Wayland** and is
now explicit about it (see `fedora.md` "GNOME desktop tuning" note,
added 2026-06). Reasoning: GNOME-on-Wayland is the default on Fedora
Workstation and Ubuntu (what most readers get without choosing), its
settings are scriptable via `gsettings`/`dconf` (so the tuning is
reproducible, not a click-path), and GNOME 46+ ships the `gcr-ssh-agent`
stack the framework depends on. NB this is NOT a "GNOME vs Wayland" or
"Wayland vs X11" choice — GNOME is the desktop, Wayland the display
protocol, and the framework targets the Wayland default. We deliberately
do NOT document KDE/Sway equivalents for the `gsettings` tuning —
supporting every Linux desktop is beyond a personal framework's remit —
but the note names the settings to look for and flags that the
SSH-agent guidance is the one desktop-independent piece. If Bill ever
moves off GNOME, this is the decision to revisit. (The implicit
assumption existed for the whole project; surfacing/defending it was
prompted by Bill's "are we consciously choosing this?" question.)

### 3.11 Framework versioning

**Decision: Versioned via the docs site, not the dotfiles. Word doc
snapshots preserved in `archive/`.**

Manuscript version history:

- **v2.0** — Initial mise-based rebuild from earlier proto-based draft
- **v2.1** — Sections 17-19 (Git, SSH, terminal multiplexing)
- **v2.2** — Appendix A (Secrets), Appendix B (Aliases)
- **v2.3** — Appendix C
- **v2.4** — Section 21 (Containers — Docker, Podman, OrbStack
  honorable mention)
- **v2.5** — Section 7.2 (Make as thin wrapper around mise tasks)
- **v2.6** — Sections 22 (Editors and IDEs) + 23 (Database/API tools)
- **v2.7** — Section 17.10 (tool-enforced git practices), MkDocs
  migration, sanitization pass

Going forward, the docs site is the source of truth. Page-level
updates happen as needed without ceremonial version bumps.

Realized in: `archive/v2.7-snapshot.docx`,
`docs/reference/customization.md` (records the version history).

## 4. Active conventions

These are the rules currently in force across all framework content.
Future-Claude: honor these. Future-you: change deliberately if you
want them changed, and update this section.

### 4.1 Voice and tone

- **Opinionated but honest about counter-positions.** Every position
  acknowledges where it's wrong as well as where it's right.
- **No emoji** unless germane to the content (this is a Bill
  preference; documented in user preferences).
- **Em-dashes for parentheticals.** Smart quotes. Inter font for body,
  JetBrains Mono for code in the docs site.
- **First-person plural ("we recommend") in the docs**, not
  second-person ("you should") which can feel preachy.
- **Short sentences over long ones.** Concrete over abstract. The
  framework rejects "this seamlessly integrates" prose.
- **Callout blocks (admonitions in MkDocs) for asides** that would
  break the flow if inline. Use sparingly.

### 4.2 Scope rules

- **Reference content is bound to artifacts.** A Reference page exists
  because it documents a specific artifact in the dotfiles.
- **Handbook content is bound to judgment.** A Handbook page takes a
  position on a question where reasonable engineers disagree.
- **No content has an audience the framework's voice can't honestly
  serve.** If a topic requires expertise the framework doesn't have
  (system architecture, distributed systems, microservices), it's
  out of scope.

### 4.3 Code examples

- **Real languages.** Ruby and Python primarily, Node where it
  illustrates a pattern better. No pseudocode.
- **Realistic problem domains.** HTTP clients, database access, file
  processing, message queues, report generation. Not `Square extends
  Shape` or `Animal.bark()`.
- **Sized to the point being illustrated.** Long enough to be
  recognizable; short enough to fit the page's flow.
- **Always pinned via mise** in any tool-version context. The framework
  has positions on `uv`, `bun`, `mise` — examples reflect those.

### 4.4 Referencing standards

- **Forward references** to pages that don't exist yet require stub
  pages or relaxed `--strict` mode. The framework's discipline is to
  create stub pages when the navigation is being established, then
  replace them with real content as it's written.
- **Cross-references** within the docs site use Markdown relative
  links (`[link](../section/page.md)`).
- **External references** to canonical texts: Vernon's *Implementing
  DDD* for aggregate design; Martin's *Clean Architecture* for
  layering; Fowler's *PoEAA* for the pattern catalog; Gamma et al.
  for the original GoF patterns.

## 5. Rejected paths

Positions that were considered and explicitly rejected. Future-Claude:
do not resurface these without first reviewing why they were rejected.

### 5.1 MIT licensing

Considered initially as the conventional permissive choice. Rejected
in favor of GPLv3 because Bill specifically wants the copyleft trigger
to fire if anyone tries to repackage and redistribute. MIT would
allow that without restriction.

### 5.2 Two separate repositories (dotfiles + docs)

Considered. Rejected because one publishing pipeline is sustainable;
two artifacts with parallel maintenance footprints would be more work
for no reader benefit.

### 5.3 Renaming the repo to "dev-environment-framework"

Considered. Rejected because renames have knock-on effects on URLs,
clones, the dotfiles-as-personal-artifact framing, and a more
descriptive name would oversell the artifact. "dotfiles" is honest if
slightly understated.

### 5.4 Quickstart + philosophical treatise as separate documents

Bill proposed this in late conversation. I pushed back: "quickstart"
undersells what we have; "philosophical treatise" oversells what's
likely to actually get written; two documents double maintenance.
Bill agreed and we landed on one repo with two distinct sections.

### 5.5 Application-code architecture as a separate book

I initially misread Bill's "architecture" pivot as wanting a standalone
treatise on DDD, clean architecture, and design patterns. Bill
corrected: "I thought we had pivoted toward the guide not the code
framework." The architecture content is *part of* the framework as
a section, not a separate work.

### 5.6 Jinja templating for placeholder substitution

Considered. Rejected because (a) literal strings stay readable in any
markdown viewer; (b) `grep` works on literal strings; (c) substitution
is a one-time forking action, not a per-build step. The framework's
placeholder convention is literal-string-with-distinctive-real-org-name.

### 5.7 Plugin managers, default prompt frameworks, framework-level
### dotfile managers, non-POSIX shells

See Section 3.10. Each rejected for specific reasons documented there.

### 5.8 Treatise-style architecture content

Bill explicitly excised this: "I think we excise the treatise element,
and have this repo stick to concrete recommendations/mandates bounded
to the dotfile artifacts in one section, and specific (but business
logic agnostic as to be portable) examples of opinionated but realistic
guidelines."

The Handbook content is opinionated but bounded — concrete patterns
with concrete evaluation criteria, not philosophical positions on
software in general.

## 6. Working patterns

How we've been collaborating. Future-Claude: this is the working mode,
not a starting hypothesis to be re-derived.

### 6.1 Push-and-validate cycle

Work happens in discrete pushes:

1. **Discuss the change** — surface the decision to be made, propose
   options, push back where appropriate.
2. **Confirm before drafting** — explicit Q1/Q2/Q3 confirmations on
   substantive choices before committing to large content pushes.
3. **Draft the content** — substantial pushes that complete a coherent
   piece of work (a section, a chapter, a restructure).
4. **Build and validate** — `mkdocs build --strict`, `zsh -n`, `sh -n`,
   POSIX test suite, all in the same push.
5. **Repackage** — produce a new tarball; stage standalone copies of
   key files for direct viewing.
6. **Present** — through the present_files tool, with a summary of
   what landed and what's queued.

This pattern has held since early in the project. Skipping the
build-and-validate step has caused regressions in the past; it's
non-negotiable for any push that produces content.

### 6.2 Pushback as productive contribution

I push back on Bill's proposals when I think they create downstream
problems. Bill has welcomed this. Examples that produced better
outcomes:

- Pushing back on the "quickstart + treatise" framing → landed on
  one-repo-two-sections.
- Pushing back on "architecture as separate book" → confirmed the
  architecture is a section within the framework.
- Pushing back on the AI document being written before the bespoke
  tool is finalized → deferred until grounded.
- Pushing back on writing a "complete treatment" architecture document
  vs starting smaller → landed on iterative growth pattern.

The pushback has a specific shape: surface the concern explicitly,
flag what changes if we proceed as proposed, suggest a smaller or
better-scoped alternative, then ask Bill to choose. Future-Claude
should continue this. Excessive deference is not the working mode.

### 6.3 Confirmation before substantive work

Q1/Q2/Q3 numbered confirmations before any substantial content push.
This catches scope misreads early. The pattern:

- Surface the choices that will affect a large piece of work
- Number them
- Get explicit confirmation
- Then draft

Bill has used these confirmations to redirect substantial work
(audience reframe, separation-as-meta-skill framing, treatise
excision). Without them, those redirections would have come after a
push of work was already drafted.

### 6.4 Honest scope-flagging

When a proposed piece of work is too big for one push, I flag it.
Examples: "this is going to be a *large* turn"; "realistic page
counts per push are smaller"; "this push will be the slower one
because the writing target is harder than what I've been doing."
Bill has consistently agreed to slow down rather than rush.

The opposite — committing to scope I can't deliver, then producing
shallow work — has not been the pattern. Future-Claude: maintain this.

### 6.5 Reading transcripts before drafting context

This document was preceded by reading the transcripts in
`/mnt/transcripts/` to recover context not in active memory. Future-
Claude: do the same before drafting any substantial new content if
your active context lacks the project history. The transcripts are
imperfect (heavy compaction artifacts, JSON noise, mid-conversation
state) but recoverable.

## 7. Error log

This is the load-bearing new content. It's organized by category, not
chronology, so patterns are visible. For each entry: what happened,
how it surfaced, how it was corrected, what the takeaway is.

This section is symmetric — Claude's errors and Bill's errors are
both documented. Bill explicitly requested factual treatment: "my
mistakes — if properly documented and annotated — are other people's
future successes."

### 7.1 Claude's errors of interpretation

**E1: Architecture pivot misread (current session).**

What happened: When Bill said he wanted to "start with architecture
which I'm more settled in my positions on," I initially proposed
three interpretations of "architecture" (framework-meta, application-
code, computing-setup) and asked which. Bill said "Oh I certainly
mean number 2" (application-code architecture). I then drafted a
proposal for a substantial standalone document on DDD, clean
architecture, dependency injection, etc., framing it as a separate
treatise.

How it surfaced: Bill's correction: "Oh I thought we had pivoted
towards the guide not the code framework."

How it was corrected: I unwound the misread explicitly, acknowledged
that "architecture" was meant as a section within the existing docs
(the framework being already opinionated about shell, toolchain, git
— extending that to code architecture as a section), and re-drafted.
The corrected approach landed as the Design section within the
Handbook.

Takeaway: When interpreting an ambiguous pivot, propose the multiple
readings, but don't anchor on the most expansive interpretation.
"Architecture" in a conversation about a dev-environment framework is
more likely about the framework's structure or the section being
added than about a separate treatise on software architecture.

**E2: Audience assumption error (current session).**

What happened: When proposing the architecture section's first content,
I assumed the audience was "engineers who already know DI, factories,
adapters" and the framework's contribution was just taking positions
on when to apply them. I sketched short pages that argued positions
without teaching the patterns.

How it surfaced: Bill's correction: "as has been from the start this
is geared towards engineers at all levels (I know some senior
colleagues of mine who could use a refresher, or on the other hand
have never heard of mise or are stuck using nvm) so the crucial
framing of the tone has to remain 'convince and actionable to jr's,
but with enough detail to keep senior's interested.'"

How it was corrected: I redid the proposal with a both-audiences
framing: pages must work for engineers who haven't seen the patterns
named *and* engineers who know them cold. Realistic page lengths
became 1500-2500 words rather than 600-1000.

Takeaway: The framework's audience has been "engineers at all levels"
since project start. I drifted from this in proposing the architecture
section because I had been thinking about pattern evaluation as a
senior-level skill. The drift was specifically an assumption about
the section's content, not the framework's general audience.

**E3: Section-completion silent state (April 28 session, recovered
from compaction summaries).**

What happened: At one point in the manuscript build, Section 22 (the
editor/IDE chapter) had been silently completed in earlier turns
whose results weren't fully captured in compaction summaries. I
prepared to draft what was already drafted.

How it surfaced: I caught this myself before drafting by checking the
file state. The state-check was a discipline that worked.

Takeaway: When picking up after compaction, always check current file
state before drafting. Compaction summaries can lose details about
which work has actually been completed.

### 7.2 Claude's errors of pacing and scope

**E4: Underestimating sample-chapter writing target.**

What happened: When sketching the Handbook content, I initially proposed
600-word pages on each design topic. The both-audiences requirement
(juniors and seniors), the rhetorical pattern (8 sections per page),
and the realistic-examples discipline make 2000-word pages plausible
and 600-word pages essentially impossible.

How it surfaced: I caught this in the next round of planning when
sketching what a real page would look like. The fix was acknowledging
the bigger budget upfront before drafting.

Takeaway: Per-page word budgets need to be tested against an actual
sample outline before committing to them. "Concise" doesn't mean
"short" when there's substantive teaching content to deliver.

**E5: Tutorial-vs-evaluation content drift.**

What happened: When proposing the architecture content, I initially
sketched it as tutorial content explaining each pattern. Bill's
audience reframe made it clear that tutorial content is widely
available elsewhere; the framework's contribution is teaching
*evaluation* — when to use the pattern, when not to, how to recognize
the situations where it helps vs hurts.

How it surfaced: Through the audience reframe (E2 above) and the
follow-up discussion of "Position A / B / C" for how the pages should
balance teaching and evaluation.

How it was corrected: Pages now teach evaluation as the primary
content, with enough pattern definition that juniors can engage.
Tutorials live in standard texts (Vernon, Martin, Fowler, GoF).

Takeaway: When the content niche is "what's not already written
elsewhere," the framework should focus on that niche (evaluation) and
defer to canonical sources for the rest (tutorial introduction).

**E6: "While we're at it" promotion of `_drafts/git-conventions.md`.**

What happened: In multiple sessions I considered promoting
`_drafts/git-conventions.md` from the drafts directory to published
content (in the Handbook), since it fit thematically.

How it surfaced: I caught this in pre-confirmation discussion. The
draft isn't ready; promoting it as a side-effect of restructuring
would add scope without adding value.

How it was corrected: Left in `_drafts/`. To be promoted later when
Bill decides it's ready, on its own merits.

Takeaway: "While we're at it" reasoning is a scope-creep antipattern.
Each piece of work should be justified on its own merits, not as a
piggy-back on adjacent work.

### 7.3 Bill's errors of direction (documented per Bill's explicit request)

These are documented because Bill specifically asked for symmetric
treatment. They are recorded factually, not accusatorily. The point
is the takeaway, not the assignment of fault.

**B1: Late-introduced architecture/code-quality requirement.**

What happened: After many iterations of the framework being positioned
as environment-only (dev environment, toolchain, configuration), Bill
pivoted in this session to wanting architectural opinions added.
This required scope renegotiation mid-conversation, including the
treatise-vs-framework-section discussion.

How it surfaced: Through my pushback on whether this fit the
framework's existing scope.

Takeaway: Adding new dimensions to a project that has been bounded a
specific way for many iterations creates real rework. The earlier
the new dimension is surfaced — even speculatively — the cheaper the
incorporation. "We might want to add X later" is a useful signal even
when X isn't immediately on the table.

The recovery worked because Bill was open to scope renegotiation and
accepted the resulting framing (one repo, two sections, treatise
excised). A less-flexible insistence on the original "treatise"
framing would have produced worse work.

**B2: "Treatise" framing requiring walk-back.**

What happened: Bill initially proposed the architectural content as a
"philosophical treatise on more abstract guidance frameworks." I
pushed back that this was likely to be either too ambitious to finish
or too divergent from the framework's actual character. Bill
ultimately agreed: "I think we excise the treatise element."

Takeaway: Strongly-framed proposals at the start of a discussion can
benefit from explicit pushback testing. The proposer benefits when
the listener flags scope or character mismatch early. This is what
the working pattern of pushback (Section 6.2) is for.

**B3: Initial split-into-two-documents proposal without considering
single-repo-two-sections alternative.**

What happened: Bill proposed splitting the framework into two
documents (a "quickstart" plus a "philosophical treatise") without
first considering whether the conceptual distinction could live as
two sections of one document.

How it surfaced: I proposed the one-repo-two-sections alternative
(Option B in my response) and argued for it. Bill agreed.

Takeaway: When a problem suggests a natural separation, consider
whether the separation needs to be physical (two artifacts) or
conceptual (two sections). Conceptual separation is often cheaper
and equally clear.

**B4: Earlier-session ambiguities in pivots.**

What happened: At several points in earlier sessions, pivots like
"let's get to architecture" or "let's discuss containerization" were
introduced without specifying which kind of architecture or what
level of containerization treatment. This required clarifying
questions before drafting.

Takeaway: A short clarifying sentence ("by architecture I mean
application-code architecture, as a section in the existing
framework") prevents Claude from anchoring on an interpretation that
turns out to be wrong. The cost of the clarifying sentence is small;
the cost of recovering from a wrong-anchor draft is large.

### 7.4 Recovery patterns that worked

These are the working modes that have produced productive recoveries
when something went wrong. Future-Claude: maintain these.

- **Pushback before commitment.** "Let me push back gently before
  drafting" before committing to a substantial push has caught
  multiple misreads early.
- **Numbered confirmations.** Q1/Q2/Q3 before substantial work has
  given Bill specific places to redirect rather than discovering the
  redirect after a draft was complete.
- **Explicit scope flagging.** Calling out when a push is going to be
  large, slower-than-typical, or harder-than-typical has set
  expectations that Bill has consistently honored with patience.
- **Rereading the transcripts.** When current context is incomplete,
  recovering from prior sessions has produced better drafting than
  working from active context only.
- **Bill's "preserve more rather than less" framing.** Applied to this
  document specifically, but generalizable: when in doubt about
  whether to include something, include it with caveats.

## 8. Governance source material

This section is preliminary. It's the analytical layer over the error
log, intended as scaffold material for Bill's eventual AI usage and
governance content (which is its own document, not this one).

### 8.1 Failure mode taxonomy from this conversation

The errors above sort into three broad categories:

**Model-level failures.** Failures rooted in how the model defaults
behave in the absence of grounding. Examples from this conversation:
the architecture-as-treatise misread (E1) is partly model-level —
"architecture" in software contexts often means high-level systems
work, and the model anchors on the most expansive reading without
strong grounding.

**Interaction-level failures.** Failures rooted in insufficient
back-and-forth before commitment. Examples: the audience assumption
error (E2) and the underestimated word budget (E4) both came from
proceeding to draft without explicit confirmation of audience and
content density.

**Human-level failures.** Failures rooted in the human's direction
being incomplete or shifting. Examples: the late-introduced
architecture requirement (B1) and the ambiguous pivots (B4) created
work that wouldn't have been needed with earlier, clearer direction.

### 8.2 Recovery patterns by failure type

**For model-level failures:** propose multiple interpretations, ask
which, anchor on the user's choice. Don't commit to the most
expansive or most familiar interpretation by default.

**For interaction-level failures:** require explicit confirmation
before substantive work. Q1/Q2/Q3 patterns. Stop and confirm rather
than infer.

**For human-level failures:** flag when scope is shifting or when
direction is ambiguous. The flag itself is the request for
clarification; the user can choose to clarify or accept the
imprecision.

### 8.3 Observations not yet integrated into governance content

Some observations from this conversation that don't fit cleanly into
the model/interaction/human categorization but seem important:

- **Tone-and-character preservation matters.** The framework has a
  specific voice (opinionated, honest about counter-positions,
  concrete over abstract). When I draft content that drifts from
  that voice — over-deferring, hedging too much — the quality of
  the work degrades. Future-Claude should treat the existing voice
  as binding.

- **Working memory is asymmetric.** Bill remembers the project's
  history continuously across sessions; I reconstruct it from
  transcripts plus active context. Documents like this one are
  partial mitigation, but the asymmetry is real and Future-Claude
  should be aware of it.

- **Pushback works because Bill welcomes it.** This is not a
  universal property of human-Claude collaboration. With a different
  user, the same pushback frequency might be unwelcome. The working
  mode here is calibrated to Bill specifically.

- **The "preserve more rather than less" framing is itself a
  governance principle.** When in doubt, document. When uncertain,
  include with caveats. The cost of over-documentation is small;
  the cost of under-documentation is unrecoverable in many cases.

### 8.4 Caveat: this section is not the AI usage guide

The AI usage guide is a separate document, deferred until Bill's
bespoke unifying tool is finalized. The observations above are raw
material that may inform that guide — not finished guidance. Future-
Claude: don't extract these into prescriptive rules without Bill's
explicit direction. The guide needs its own treatment.

## 9. Artifact inventory

For quick reference. Cross-referenced from earlier sections.

**At repository root:**

- `LICENSE` — GPLv3-or-later, Bill Woika 2026
- `README.md` — Layer 1 short-form intro (13 KB, ~3500 words)
- `mkdocs.yml` — MkDocs Material site config
- `bootstrap.sh` — Idempotent symlink installer
- `profile` — POSIX `~/.profile` shim
- `.editorconfig` + `.editorconfig.example` — Editor formatting rules
- `.gitignore` + `gitignore.example` — Git ignore patterns

**Documentation source (`docs/`):**

- `index.md` — Site landing page
- `requirements.txt` — Pinned MkDocs dependencies
- `shell/{index,architecture}.md` — Reference: shell setup
- `tools/{index,mise-and-make}.md` — Reference: toolchain
- `git/{index,tool-enforced-practices}.md` — Reference: git
- `operations/{index,secrets}.md` — Reference: secrets management
- `reference/{index,customization}.md` — Reference: meta and
  customization
- `handbook/index.md` — Handbook framing
- `handbook/design/index.md` — Design section index, separation
  framing
- `handbook/design/*.md` (7 stubs) — Future content per the rhetorical
  pattern

**Configuration directories** (each contains real configs that get
symlinked or copied per `bootstrap.sh`):

- `zsh/` (22 files)
- `mise/config.toml`
- `direnv/direnvrc`
- `git/` (config + ignore + attributes + 3 .example profiles)
- `ssh/config.example`
- `tmux/tmux.conf`
- `vim/vimrc`
- `vscode/` (3 reference templates)
- `jetbrains/` (README + 2 runConfig XMLs)
- `macos/setup-file-associations.sh`
- `devcontainer/` (5 reference templates)
- `sh/tests/profile_test.sh`

**Archive (`archive/`):**

- `README.md` — explains what's archived
- `v2.7-snapshot.docx` — frozen 209-page Word manuscript

**Drafts (`_drafts/`):**

- `git-conventions.md` — future engineering handbook content, deferred
- `README-v2.6-old.md` — previous README, archived

**CI (`.github/workflows/`):**

- `docs.yml` — MkDocs build + gh-pages deploy

## 10. Open questions and queued work

Things not yet decided or completed.

### 10.1 Queued content

- **The 7 Design section stubs need real content.** ~2000 words each,
  per the rhetorical pattern in the section index. Recommended order:
  separation-of-concerns → locality → separation-by-lifecycle (factories)
  → separation-by-dependency (DI) → separation-by-boundary (adapters)
  → separation-by-variation (strategy) → value-types.

- **The remaining ~25 chapters from the Word manuscript** can convert
  mechanically to MkDocs pages. Five representative chapters were
  converted as proof-of-concept (Section 1 → docs/index.md;
  Section 4 → docs/shell/architecture.md; Section 7 →
  docs/tools/mise-and-make.md; Section 17.10 → docs/git/tool-
  enforced-practices.md; Appendix A → docs/operations/secrets.md).
  The five exercise every formatting pattern; the rest is
  straightforward.

- **`_drafts/git-conventions.md`** — to be promoted to a Handbook
  section when Bill decides it's ready.

### 10.2 Deferred work

- **AI tooling document.** Deferred until Bill's bespoke unifying tool
  for AWS SSM/IAM identity management is finalized. The document
  needs concrete grounding to be useful.

- **AI governance content.** Bill mentioned this can scaffold off the
  error log in this document. That's source material, not finished
  guidance — the actual governance document is its own future
  project.

### 10.3 IDE migration (DONE — happened as planned)

Bill moved from chat to the IDE/CLI workflow (Claude Code in the
repo). This handoff artifact served that move and now lives at
`meta/context.md` rather than the original root `.claude-context.md`
— the rename happened during the 2026-05-31 reconciliation, when the
file was recovered from git history after a prior convention change
had deleted it and left `CLAUDE.md` pointing at a dead path.

### 10.4 Repository reorganization (DONE — layout has since moved)

The reorg Bill anticipated happened. Notable moves since the initial
snapshot: `docs/shell/` → `docs/shell-environment/` (Cloudflare WAF
flagged "shell" in URLs); SSH content moved under `operations/`; the
whole `platform-setup/` tree (macOS/Fedora/Debian) and a Fedora-first
`onboarding.md` runbook were added; a `linux/` helper dir now mirrors
`macos/`; internal meta-docs split into `meta/` (this file), kept out
of the published `docs/` tree on purpose. Section 2 was refreshed on
2026-05-31 to match. Treat Section 2's dated snapshot as authoritative
over any layout description elsewhere in this document.

### 10.5 Open framing questions

- **Whether the framework eventually grows beyond personal scope.**
  Currently personal-portable, GPLv3. Bill has mentioned it being
  optionally adoptable by Springbig. That hasn't happened, and the
  framework's voice still reflects "one engineer's coherent set of
  choices" rather than "team handbook." If Springbig adoption
  becomes real, the voice question reopens.

- **Whether the Handbook absorbs other practice-level content.** The
  framework has accumulated practice-level content beyond
  configuration (debugging philosophy in Section 22, git workflow
  positions in Section 17.10, AI tooling guardrails when they're
  ready). Whether all of these end up in the Handbook section, or
  some stay in the Reference section as "Reference content with
  opinions," is undecided.

- **Whether the docs site eventually versions.** Currently no `mike`
  plugin (deferred until there's actually a v2 to publish). The
  question is whether the framework's evolution gets versioned at
  the docs-site level, or whether continuous evolution on `main` is
  sufficient indefinitely.

## 11. Onboarding instructions for Future Claude

Read these first when starting a new session.

### 11.1 What to read

In order:

1. This document, in full.
2. The most recent transcript in `/mnt/transcripts/` if you need
   detail beyond what's recorded here.
3. The current state of the repo (`docs/`, `mkdocs.yml`, `README.md`).
4. The user's most recent message — but only after grounding via
   1-3.

### 11.2 What to do before drafting

- **Confirm the audience.** "Engineers at all levels — junior who
  hasn't seen the patterns, intermediate who applies indiscriminately,
  senior who wants positions." All three populations every page.
- **Confirm the rhetorical pattern.** Concrete problem statement first.
  Equal weight on when-not-to-use. Realistic examples in Ruby or
  Python.
- **Confirm the section.** Reference pages document artifacts.
  Handbook pages take positions on judgment questions.
- **Confirm the scope.** A single push should produce one coherent
  piece of work, validated, packaged, and presented. If a request
  exceeds that, flag the size and propose splitting.

### 11.3 What pattern to use for substantive work

1. Discuss the change. Surface decisions.
2. Push back on scope, audience, or approach if appropriate.
3. Confirm via Q1/Q2/Q3 numbered questions before drafting.
4. Draft.
5. Build (`mkdocs build --strict`), validate (`zsh -n`, `sh -n`,
   POSIX tests), repackage, present.
6. Summarize what landed and what's queued.

### 11.4 What not to do

- **Don't be excessively deferential.** Bill welcomes pushback. Defer
  on substance only when he's settled a position; push back on
  unsettled or ambiguous direction.
- **Don't anchor on the most expansive interpretation of an ambiguous
  pivot.** Propose multiple readings, ask which.
- **Don't write "AI governance content" without Bill's specific
  direction.** The error log here is source material; the actual
  governance document is its own project.
- **Don't promote draft content to published without Bill's explicit
  approval.** `_drafts/` is `_drafts/` deliberately.
- **Don't restructure mid-session without confirmation.** Restructures
  ripple through cross-references and require multiple build cycles
  to settle.

### 11.5 Voice continuity

The framework has a specific voice. When in doubt, look at:

- `README.md` (Layer 1 voice — concise, opinionated, friendly)
- `docs/handbook/design/index.md` (Handbook voice — opinionated,
  honest about counter-positions, concrete)
- `docs/git/tool-enforced-practices.md` (Reference voice — bound to
  artifacts, practical, with admonitions for asides)

These are the touchstones. Drift from them and the work feels off.

---

## Appendix A: Reference to standard texts

When the Handbook needs depth that the framework doesn't provide:

- **Vaughn Vernon, *Implementing Domain-Driven Design*** — for
  aggregate design and DDD tactical patterns
- **Robert Martin, *Clean Architecture*** — for layering and
  dependency-direction arguments (used selectively; Martin's
  *Clean Code* is treated more cautiously)
- **Martin Fowler, *Patterns of Enterprise Application Architecture*** —
  for the catalog of enterprise patterns (repository, unit-of-work,
  data mapper, etc.)
- **Gamma et al., *Design Patterns*** — for the original GoF pattern
  catalog
- **Sandi Metz, *Practical Object-Oriented Design***  — for the
  "messages between objects" framing that informs the Design section
  (especially relevant for Ruby examples)

These are the canonical references the Handbook directs readers to
when they want fuller treatment than the framework provides.

## Appendix B: Document maintenance

If you're updating this document (whether you're future-Bill or
future-Claude):

- **Version note.** This document was first drafted at the close of
  the May 3 session. The MkDocs migration was complete, the Handbook
  framing was in place, the Design section had its index page and
  seven stubs. The conversation was about to move to an IDE
  workflow.
- **What to update.** Anything that changes — repository layout,
  decisions, conventions, queued work. The document is meant to
  reflect current reality, not historical reality.
- **What not to update.** The error log entries are historical record
  and shouldn't be edited away. New errors get added; old errors
  stay even after the lessons have been incorporated.
- **What to do when revisiting a decision.** Don't quietly work around
  it. Update the relevant section, with a note about why the change
  was made. Future-Claude reading the updated document then sees the
  new state; the previous state, if needed, is in git history.

---

*End of `meta/context.md`. ~7800 words.*
