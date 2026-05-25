# Philosophy

The Framework section of this site covers configuration: shell,
toolchain, git, secrets, networking, IDE setup. Concrete
recommendations bound to specific artifacts in the dotfiles. "Use
mise. Configure git this way. Run lefthook for pre-commit hooks."

This section is different. It covers **positions** — opinionated
arguments about how to write and structure code, how to work in
teams, and how to make engineering decisions where reasonable people
disagree. The content here is rigorous but contestable. Every stance
acknowledges where it is wrong or where the counter-position has
merit.

The distinction matters: Framework pages tell you what to do.
Philosophy pages tell you how to think about decisions a linter
cannot make for you.

## Audience

Engineers at all levels:

- A junior engineer who hasn't seen the patterns named, doesn't yet
  have intuition for when each one applies, and needs enough scaffolding
  that each page is useful in isolation.
- An intermediate engineer who knows the pattern names but has applied
  them indiscriminately, and would benefit from explicit framing of when
  *not* to reach for them.
- A senior engineer who knows the patterns cold, has applied them across
  many contexts, and is reading to find out whether the framework's
  positions add anything to what they already know.

Every page tries to serve all three. That's a demanding writing target;
some pages do it better than others. The shared discipline is:

- **Concrete problem statements.** Every concept is introduced via a
  specific, recognizable problem, not as an abstract principle. Engineers
  recognize the problem from their own work; the page then explains how
  to think about it.
- **Specificity over generality.** "Use this pattern when the dependency
  has more than one implementation selected at runtime by configuration"
  is a real claim. "Use this pattern for flexibility" is not.
- **Equal weight on when *not* to apply.** Knowing when a pattern is the
  wrong reach is at least as important as knowing when it's the right
  one. Pages give both treatments roughly equal space.
- **Realistic examples in the framework's languages.** Ruby and Python
  primarily, with Node where it illustrates a pattern better. No
  pseudocode, no contrived `Square extends Shape` examples.

## Pages

- **[Tactical Posture](tactical-posture.md)** — how to approach a
  codebase: understanding the global context before making local changes,
  the propagation problem (code spreads and its damage compounds
  silently), the one-liner illusion, the refactoring trap, and why
  understanding the superstructure — the business, the users, the
  contracts — is what separates engineers from linters.

- **[The Layers](layers.md)** — an illustrative five-layer model
  (infrastructure, data, application logic, presentation, observability)
  for thinking about software systems. Covers dependency direction,
  blast radius, the data layer's coupling to infrastructure, and the
  industry's flattening of layers through managed services and
  database-as-API products.

- **[Design Principles](design/index.md)** — the framework's position
  that patterns are tools, not goods, and the meta-skill of recognizing
  which kind of separation problem you are facing.

- **[Separation of Concerns](design/separation-of-concerns.md)** — the
  foundational vocabulary. What "concerns" means concretely, how mixed
  concerns produce god classes, and the equally important cost of
  premature separation.

- **[Locality](design/locality.md)** — separation in space. File
  organization strategies, boundaries and contracts, encapsulation as
  an entailed consequence, and boundary violations in Rails.

- **[Decoupling Patterns](design/decoupling-patterns.md)** — the
  transition from programs that enumerate their behaviors to systems
  that discover them. Registries, factories, dependency injection, and
  the builder pattern as production architecture — with testability as
  the strongest signal that boundaries are correctly drawn.

- **[A Small Detour: The Metaprogramming Trap](design/metaprogramming-trap.md)**
  — the seduction of metaprogramming, why implicit magic is almost
  always the wrong reach in application code, and why the measure of
  code quality is not cleverness but whether the team can work with it.

- **[Value Types](design/value-types.md)** — modeling values by how
  they are used rather than what they look like. TypeScript's type system
  as a contract, escape hatches as type-system violations, and domain
  expertise as the foundation of typing discipline.

- **[The Case for Code Quality](code-quality-argument.md)** — why
  automated formatting, linting, and static type checking are worth the
  friction they impose.

- **[Logging](logging.md)** — structured logging as the only reliable
  form of operational output. Twelve-factor log management, trace ID
  generation, enumerated events, PII redaction, distributed tracing
  via OpenTelemetry, and vendor lock-in.

- **[Testing](testing.md)** — an honest treatment of testing as
  ceremony worth maintaining. Tests as contract enforcers, the
  tautology problem, the testing hierarchy, RSpec pitfalls, coverage
  thresholds, and time-dependent heisentests.

- **[Git Conventions](git-conventions.md)** — commit message style, PR
  conventions, branching strategy, code review etiquette, and mistake
  recovery.

## What's deliberately not here

This section takes positions, but it's not a treatise. A few things
that fall outside its scope:

- **Comprehensive teaching of any pattern.** The pages assume you've
  encountered the patterns in some form, even casually. They're about
  evaluation and application, not first-encounter introduction. Where a
  pattern is genuinely obscure, the page links to a recommended primary
  source.
- **System-level architectural guidance.** Microservices vs monolith,
  event sourcing, CQRS, distributed-system patterns — these are
  context-dependent in ways that cannot be honestly argued without a
  specific system in mind.
- **Language-specific tutorials.** The patterns translate across
  languages but the implementations differ; the pages give illustrative
  examples but don't try to cover every language's idiomatic
  implementation of every pattern.
- **Code style.** Naming conventions, line lengths, indentation —
  formatters and linters handle these. This section is about decisions
  a linter can't make for you.

## Relationship to the Framework

The two sections are complementary:

- **Framework** is *concrete and bound to artifacts*. Pages map to
  specific files in the dotfiles or specific configuration in
  projects. The advice is "do this." Engineers act on it directly.
- **Philosophy** is *opinionated and bound to judgment*. Pages take
  positions on questions where reasonable engineers disagree. The
  advice is "here's how to think about this and what the framework
  recommends." Engineers apply it via decisions in their own code.

A reader looking up "how do I configure my zsh prompt" goes to
Framework. A reader thinking through "should I introduce a factory
here, or is it overkill?" goes to Philosophy.
