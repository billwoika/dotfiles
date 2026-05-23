# Design

This section is about a single underlying question, asked at multiple
scales: **what code belongs together, and what code belongs apart?**

Most of the design patterns engineers learn — factory, dependency
injection, adapter, strategy, repository — are answers to specific
versions of this question. The pattern is the tool; the underlying skill
is recognizing *which kind of separation problem* you're facing and
matching it to the right tool.

This section is organized around that meta-skill. Each page introduces a
specific separation problem with a concrete, recognizable scenario,
explains the principle that addresses it, and walks through the
pattern(s) that operationalize the principle — including, with equal
weight, when *not* to reach for them.

## The problem with treating patterns as universal goods

The way design patterns are usually taught — pattern-by-pattern, with
abstract examples — produces a particular failure mode in practice.
Engineers learn that "dependency injection is a best practice" or "the
factory pattern is the right way to construct objects," internalize this
as a rule, and start applying the patterns universally.

The result is code where every class has a corresponding factory that
does nothing the constructor wouldn't, every dependency is injected
even when there's only ever one implementation, every external
integration has a three-layer adapter when one method on the calling
class would have done. The patterns are present but the *value* the
patterns are supposed to provide isn't — because the underlying
separation problem the pattern solves wasn't actually present.

This is why the framework's position is that **patterns are tools, not
goods**. A factory is right when the problem it solves is real. A
factory is wrong when there's no separation problem and the pattern is
ceremony — overhead with no payoff. The skill the Handbook tries to
build is recognizing the difference.

## Pages

Five pages and a detour, each addressing a distinct form of the
separation question:

- **[Separation of Concerns](separation-of-concerns.md)** — the
  foundational vocabulary. What "concerns" means concretely (defined
  by change-drivers, not abstract responsibilities), how mixed
  concerns produce god classes, the cost of entangled code, and the
  equally important cost of premature separation.

- **[Locality](locality.md)** — separation in *space*. Where in the
  file tree should code live? Co-located by feature, separated by
  layer, or some hybrid? When does directory structure communicate
  the system's design, and when does it obscure it?

- **[Decoupling Patterns](decoupling-patterns.md)** — the transition
  from programs that enumerate their behaviors to systems that
  discover them. Follows a single payment-processing example through
  its full evolution: from branching to extracted functions, to class
  hierarchies, to self-registering registries and protocol-based
  dispatch. Covers factories, dependency injection, and the builder
  pattern as production architecture that enforces boundaries — with
  testability as the strongest signal that boundaries are correctly
  drawn.

- **[A Small Detour: The Metaprogramming Trap](metaprogramming-trap.md)**
  — an aside on the seduction of metaprogramming. The patterns in
  Decoupling Patterns make systems adaptive through explicit
  contracts; metaprogramming makes systems adaptive through implicit
  magic. The detour examines why the latter is almost always the wrong
  reach in application code, and why the measure of code quality is
  not cleverness but whether the team can work with it.

- **[Value Types](value-types.md)** — separation applied to *data*.
  The problem is modeling values by what they look like (strings,
  numbers, floats) rather than how they are used (statuses, IDs,
  currency). Walks through TypeScript's progression from bare strings
  to union types, enums, and branded types — with a direct treatment
  of `as any`, type assertions, and `@ts-ignore` as type-system
  violations equivalent to disabling CI checks. Covers composite
  domain types as the mechanism through which domain understanding
  enters the codebase, and makes the case that typing discipline is
  where technical craft meets subject-matter expertise.

One page from the original outline has been promoted:

- **[Platform Portability](../../framework-platform-portability.md)** —
  now positioned at the top of the Framework section, because it
  applies to every component that follows. It remains linked here as
  a worked example of Separation by Variation applied to the
  infrastructure layer.

## How to read this section

If you're encountering these patterns for the first time, the pages
read in order. Separation of Concerns establishes vocabulary; Locality
applies it to spatial organization and boundaries; Decoupling Patterns
covers the mechanical tools and the design disciplines that enforce
them; the Metaprogramming Trap is a necessary aside before continuing;
Value Types applies the thinking to data.

If you already know the patterns, jump to the relevant page directly.
Each page follows a consistent structure: a concrete problem statement,
the consequences of ignoring it, the principle and patterns that
address it, when to apply them, and — with equal weight — when not to.

## What this section is not

It's not a comprehensive treatment of design patterns. The Gang of Four
book (*Design Patterns*, Gamma et al.) and Fowler's *Patterns of
Enterprise Application Architecture* are the canonical references; this
section assumes you'll consult them when you want depth.

It's not a position on system-level architecture. Microservices, event
sourcing, CQRS, distributed system patterns — those are context-
dependent in ways the Handbook can't honestly take positions on without
a specific system in mind.

It's not a treatise. The framework's position is that patterns are tools
to be evaluated, not orthodoxies to be defended. The pages reflect that
stance: opinionated, but more interested in helping you decide than in
declaring what's correct.
