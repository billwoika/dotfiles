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

## Forms of separation

The pages in this section each address a specific kind of separation:

- **[Separation of Concerns](separation-of-concerns.md)** — the
  foundational vocabulary. What "concerns" means concretely, how mixed
  concerns produce god classes, and the cost of code where unrelated
  things are entangled.

- **[Locality](locality.md)** — separation in *space*. Where in the
  file tree should code live? Co-located by feature, separated by
  layer, or some hybrid? When does directory structure communicate
  the system's design, and when does it obscure it?

- **[Separation by Lifecycle](separation-by-lifecycle.md)** —
  separation between *constructing* an object and *using* it. The
  problem statement is constructors that do too much; the
  operationalizing pattern is factories.

- **[Separation by Dependency](separation-by-dependency.md)** —
  separation between code and the things it depends on. The problem
  statement is hardcoded collaborators that make code untestable in
  isolation; the operationalizing pattern is dependency injection.

- **[Separation by Boundary](separation-by-boundary.md)** —
  separation between the domain you control and the external world
  you don't. The problem statement is business logic entangled with
  third-party APIs; the operationalizing pattern is the adapter.

- **[Separation by Variation](separation-by-variation.md)** —
  separation between code that's stable and code that varies. The
  problem statement is switch statements that grow forever; the
  operationalizing patterns include strategy and the factory's
  variant-selection role.

- **[Value Types](value-types.md)** — a more specific case of the
  above, applied to data. The problem statement is stringly-typed
  code where a string can mean five different things depending on
  context; the operationalizing concepts include constants, enums,
  and value objects.

## How to read this section

If you're encountering these patterns for the first time, the pages
read in order. Earlier pages establish vocabulary and habits of mind
that later pages build on.

If you already know the patterns and are looking for the framework's
position on a specific one, jump to the relevant page directly. Each
page is structured the same way:

1. **Problem statement.** A specific, recognizable scenario from real
   codebases.
2. **What's wrong.** Concrete consequences, not abstract principles.
3. **The principle.** Stated in terms of separation.
4. **The pattern(s) that operationalize the principle.** With realistic
   examples in Ruby or Python.
5. **When this is the right reach.** Specific situations.
6. **When this is the wrong reach.** Equally specific.
7. **Common antipatterns.** Named failure modes.
8. **Questions to ask before reaching for it.** A short evaluation
   checklist.

The structure is repetitive across pages because the discipline is
repetitive: every separation decision benefits from the same set of
questions, asked with reference to the specific situation.

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
