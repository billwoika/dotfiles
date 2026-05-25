# Tactical Posture

## Think globally, act locally

The phrase has problematic origins and a well-earned reputation for
fecklessness in its original environmental context. As a strategy for
working in a codebase, it is surprisingly precise.

Every engineer who has worked in a system of any size has experienced
the moment: a seemingly minor change — an early return, a new
conditional branch, a default parameter — produces a failure that
surfaces days or weeks later, in a part of the system that the author
never touched and may never have seen. The change was small. The
failure was not.

The instinct is to blame the failure on inadequate testing, missing
documentation, or poor architecture. Sometimes those are contributing
factors. But the deeper cause is simpler: the engineer who made the
change understood the *local* context (the function, the module, the
immediate call site) but not the *global* context (the system's
operating behavior, the downstream consumers, the assumptions that
other components make about this component's output). The change was
locally correct and globally destabilizing.

This is the tactical posture: **understand the global context before
making the local change.** Not because the global context is always
relevant — often it is not. But because you cannot know whether it is
relevant until you have looked.

## The propagation problem

Code propagates. This is its most underappreciated property.

A function is called from one place when it is written. Six months
later it is called from four places, because it did what other code
needed. Each caller makes assumptions about the function's behavior:
its return type, its side effects, its error handling, its
performance characteristics. The assumptions are rarely documented
because the function's contract was never explicitly defined — it
just did what it did, and the callers relied on what they observed.

When an engineer modifies that function — adds an early return for a
new edge case, changes the error from an exception to a null return,
adds a logging side effect that subtly changes the timing — the
modification is tested against the caller the engineer knows about.
The other three callers are not tested, because the engineer does not
know they exist. The modification is compatible with the known caller
and incompatible with one of the unknown callers, and the
incompatibility does not surface as a test failure or a crash. It
surfaces as a subtle behavioral change: a report that now excludes
certain records, a queue that processes items in a slightly different
order, a cache that invalidates a few milliseconds later than it
used to.

The behavioral change is not noticed immediately. It is noticed when
someone files a support ticket three weeks later saying the monthly
numbers look wrong, and the investigation traces back through the
reporting pipeline, through the data aggregation service, through the
queue consumer, to the function that now returns early for a case it
used to process. The commit that introduced the early return is six
hundred commits ago. The engineer who wrote it has moved on to
another project.

This is the propagation problem. Code does not exist in isolation.
Every function, every class, every module is embedded in a web of
consumers, assumptions, and implicit contracts. A change to any node
in that web propagates through the connections — not immediately, not
visibly, and not in ways that the author can anticipate by looking
only at the local context.

## The virality of code

The propagation problem is compounded by a property that is easy to
observe and difficult to internalize: **once code is released, it is
extraordinarily difficult to retract.**

A feature that was built as a one-off proof of concept — "let's see
if this approach works, we'll clean it up later" — ships to
production. It is rarely used. It is not documented. It is not
maintained. It exists in the codebase as an inert artifact that
nobody thinks about.

Then someone discovers it. A new feature needs something similar, and
the proof of concept almost does what is needed. The new feature
builds on top of it — imports its helpers, follows its patterns,
depends on its behavior. The proof of concept is no longer inert. It
is load-bearing infrastructure that was never designed to be
load-bearing, never tested for the contexts it is now used in, and
never reviewed for the assumptions it encodes.

Then the proof of concept's behavior becomes a problem. It handles an
edge case incorrectly — not incorrectly for its original one-off
purpose, but incorrectly for the three features now built on top of
it. Fixing the edge case breaks the features. Leaving the edge case
breaks new requirements. Replacing the proof of concept requires
understanding and rewriting the three features that depend on it.

The proof of concept was released as a minor, low-risk addition. Its
cost was measured in the hours it took to write. Its actual cost — now
— is measured in the weeks required to disentangle it from the system
that grew around it. And the disentanglement will itself introduce
new risks, because the system has adapted to the proof of concept's
behavior, including its bugs.

This pattern is not exceptional. It is the default outcome for code
that is released without consideration for how it will propagate. The
one-off becomes a dependency. The hack becomes a pattern. The
temporary solution becomes permanent infrastructure. Each step is
individually rational — someone needed something, the existing code
almost did it, extending it was cheaper than rewriting it. The
aggregate is a system whose behavior depends on artifacts that were
never intended to be permanent, never designed for the load they now
carry, and never reviewed by the team that now depends on them.

## The one-liner illusion

"It's just a one-liner" is a claim about the *textual* size of a
change. It says nothing about the *behavioral* size — the difference
in the system's operating behavior before and after the change.

An early return added to a function is one line. If the function is
called in a pipeline that expects it to always produce output, the
early return silently removes records from the pipeline. The
behavioral delta is not one line — it is every downstream process
that now operates on incomplete data.

A new `if` branch is two lines. If the branch introduces a code path
that bypasses a validation step, the behavioral delta is every
request that now reaches the system without validation. The two lines
of code are two lines of risk that the previous system did not have.

A new subclass is a file. If the subclass is registered in a dispatch
table that other modules iterate, the behavioral delta is every
module that now encounters a type it was not designed to handle. The
file is not the change — the change is the system's response to a new
participant in a protocol that was designed for a fixed set of
participants.

The measure of a change is not its size in lines or its semantic
delta in the immediate module. The measure is the difference in the
system's operating behavior. A one-line change that alters the
behavior of a function called in twelve places has twelve potential
impact sites. A five-hundred-line change that adds a self-contained
module with no external callers has zero. The first is riskier than
the second by every measure except line count.

"Just a one-liner" is a claim that can only be legitimately made by
someone who thoroughly understands not just the function being
modified, but every caller, every downstream consumer, every implicit
contract, and every assumption that other components make about this
function's behavior. For the engineer who has done that analysis, the
claim is honest. For the engineer who has not, it is a statement
about the size of the diff, not the size of the risk.

## The refactoring trap

The opposite failure mode is equally dangerous: the engineer who
understands the global context *too well* and attempts to fix
everything at once.

The impulse is familiar. You are asked to fix a bug in a function.
You open the function and discover that it is poorly structured — the
naming is inconsistent, the error handling is incomplete, the
function does three things that should be three functions. You also
notice that the module the function lives in has the same problems.
And the module next to it. And the service that calls both.

The responsible thing to do, your instincts say, is to fix the
structural problems while you are here. Refactor the function.
Rename the variables. Extract the helpers. Clean up the module. Fix
the service's interface. Ship a clean, well-structured change that
addresses the bug and leaves the code better than you found it.

The problem is scope. The refactoring that started as a bug fix now
touches forty files across three modules. The diff is a thousand
lines. The reviewers cannot separate the bug fix from the cleanup.
The tests pass, but the behavioral delta of a thousand-line change
across three modules is far larger than the behavioral delta of the
original bug fix — and the refactoring may have introduced its own
behavioral changes that are invisible in the diff but visible in
production.

The tactical posture for refactoring is not "never refactor." It is:
**scope the change to what is needed, ship it, and come back for the
cleanup.** The bug fix is one commit, one PR, reviewable and
revertable in isolation. The refactoring is a separate effort with
its own review, its own testing, and its own risk assessment. The two
do not ship together because their risk profiles are different: the
bug fix is high confidence, low risk. The refactoring is lower
confidence, higher risk. Bundling them makes the high-confidence
change inherit the risk of the low-confidence change.

This discipline is hard. The messy code is right there. Fixing it
feels responsible. Leaving it feels negligent. But the engineer who
ships a clean, minimal bug fix and files a ticket for the refactoring
has made the system more stable than the engineer who ships a
combined bug-fix-and-refactoring that nobody can confidently review.

A confession: this is advice the author is still learning to follow
reliably. The impulse to demarcate a clean boundary around a larger
refactoring — to isolate the change from the ecosystem at large by
fixing everything within the boundary — is strong, and the line
between "responsible cleanup" and "scope creep" is genuinely
ambiguous in the moment. This framework does not come from a
position of having solved the problem. It comes from having made the
mistake enough times to recognize the pattern and articulate it
honestly. The discipline described here is aspirational for the
author too.

## Beyond the code

The global context is not the codebase. It is the system — and the
system extends beyond the code.

The system includes the infrastructure the code runs on. A change
that increases memory usage by 10% in a function called once per
request may be invisible in a development environment with 16GB of
RAM and catastrophic in a production container with a 256MB memory
limit. A change that adds a database query to a hot path may be
undetectable with ten test records and a production outage with ten
million.

The system includes the business vertical. A change to how enrollment
dates are calculated is not a technical question — it is a business
question about when customers become eligible for benefits, how
revenue is recognized, and what the contractual obligations say. The
engineer who changes the calculation without understanding the
business context may produce code that is technically correct and
commercially wrong.

The system includes the users and the community. An API change that
renames a field is a one-liner in the codebase and a breaking change
for every integration partner who depends on the field name. A
behavioral change in a library is a one-liner in the library and a
debugging session for every downstream consumer who relied on the
previous behavior.

## The strategic scope

The impulse to paper over symptoms instead of investigating causes is
not unique to engineers writing code. It afflicts everyone in the
decision chain: product owners, managers, architects, and executives.
And the closer a person is to the people who care most about the
outcome — the customers, the stakeholders, the partners — the easier
it becomes to lose the forest for the trees.

A product owner reports that an integration is passing the opposite
boolean value than expected. Customers who should be enrolled are
showing as not enrolled. The PO needs it fixed now — customers are
affected, support tickets are piling up, and the partner is asking
questions.

The careless fix is a bang operator:

```ruby
enrolled = !integration_response.enrollment_status
```

The value was wrong, now it is right. The ticket is closed. The PO
is satisfied. The fix ships in twenty minutes.

Except the root cause was never that the values were backwards. The
root cause was a race condition: two webhook callbacks from the
partner arrive within milliseconds of each other, the second
overwrites the first, and the final state depends on which callback
the queue processes last. The bang operator fixes the symptom for
customers who receive one callback. It makes the problem *worse* for
customers who receive two, because now the correct value is negated.
The PO files another ticket. Another engineer adds a conditional:
"negate the value unless the customer was updated in the last five
seconds." The conditional fixes the two-callback case and breaks the
single-callback case for customers in a specific timezone where the
five-second window straddles a date boundary.

This is the pendulum swing — not an overreaction toward dramatic
rewrites, but a series of band-aid fixes, each addressing one
specific error case, each papering over the underlying problem, each
introducing new edge cases that will require their own band-aids.
The codebase accumulates anti-fixes: negations, special-case
conditionals, timing windows, deduplication hacks. Each one was a
rational response to a specific symptom. The aggregate is a system
whose behavior is defined by its workarounds rather than its design.

A well-measured, thorough refactor to address the root cause — the
race condition, the missing idempotency guarantee, the absence of a
deduplication layer — would be an excellent outcome. It would take
longer than the bang operator. It would require understanding the
partner's webhook behavior, the queue's ordering guarantees, and the
data model's concurrency characteristics. It is the kind of work that
a PO under pressure from affected customers is least inclined to
authorize, because the customer's pain is immediate and the
refactor's benefit is deferred.

This is where engineers must be one of the final checks on the
pendulum. The PO is closest to the customer's pain and farthest from
the codebase's stability. The engineer is closest to the codebase's
stability and farthest from the customer's pain. The PO sees the
symptom and needs it resolved. The engineer sees the cause and knows
that resolving the symptom without addressing the cause guarantees a
recurrence — and that each recurrence will be harder to diagnose
because the codebase now contains layers of anti-fixes that obscure
the original behavior.

The tactical posture here is not to refuse the quick fix. It is to
ship the quick fix *and* insist on the follow-up. Fix the immediate
symptom so customers are unblocked. Then investigate the root cause,
scope the real fix, and make the case for it — with specificity, with
evidence, with a clear articulation of what happens if the band-aids
continue to accumulate. The engineer who does this is not being
difficult. They are protecting the system from the compounding cost
of deferred understanding.

This is what separates an engineer from a linter. A linter can tell
you that a function is too long, a variable is unused, a type is
mismatched. It cannot tell you that the function's behavior is
depended on by a partner integration, that the variable was left
unused because the feature it served is being relaunched next
quarter, that the type mismatch is intentional because the upstream
service sends inconsistent types and the coercion is a deliberate
workaround. The linter operates on the text of the code. The
engineer operates on the meaning of the system.

## The posture

Tactical posture is not a process or a checklist. It is a habit of
mind:

**Before changing code, understand who depends on it.** Not just the
immediate callers, but the callers' callers. Not just the module, but
the services that consume the module's output. `grep`, `git log`, and
the dependency graph are tools. Using them before writing code is not
slowness — it is due diligence.

**Before adding code, consider how it will propagate.** Every
function you write will be called from places you did not anticipate.
Every class you define will be subclassed or composed in ways you did
not design for. Every API you expose will be consumed by clients you
have not met. Write code as though someone will depend on its
behavior, because they will.

**Before shipping, ask what the behavioral delta is.** Not the diff —
the behavioral delta. What does the system do differently after this
change than it did before? If you cannot state the behavioral delta
in a sentence, you do not understand the change well enough to ship
it.

**Scope changes to what is needed.** Fix the bug. Ship it. Come back
for the cleanup. The most common source of production incidents from
"safe" changes is bundled scope — the bug fix that also refactors,
the feature that also cleans up tech debt, the migration that also
updates the schema. Each addition multiplies the risk. Keep the scope
minimal and the intention clear.

**Understand the superstructure.** The code serves a business. The
business serves customers. The customers have expectations that are
not documented in the codebase. Technical prowess without
understanding the superstructure — the business rules, the partner
contracts, the user expectations, the regulatory constraints — is the
ability to change code without the judgment to know what the change
means. That is the domain of linters, not engineers.

## Questions to ask

1. Before making a change: who calls this code, and what do they
   assume about its behavior? If you do not know, find out before
   writing.
2. Before adding a feature: if this proof of concept becomes
   permanent (and it will), is the design sound enough to support
   that? If not, either invest in the design now or make the
   temporary nature explicit and enforceable.
3. Before shipping: can you state in one sentence what the system
   does differently after this change? If not, the change is larger
   or more complex than you think.
4. Before bundling: does this change contain exactly one intention? If
   it contains a bug fix and a refactoring, separate them. Each
   intention should be independently reviewable and revertable.
5. Before optimizing: do you understand the business context of the
   code you are changing? A technically correct change that violates a
   business rule is a bug, not an optimization.
