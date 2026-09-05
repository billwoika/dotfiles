# Technical Debt

## The definition problem

Technical debt is a bit like the legal definition of obscenity — you
know it when you see it. The term is one of the most overloaded in
the industry. It is used to mean "code I didn't write," "code I wrote
last week that I'd write differently today," "a decision that was
correct at the time and is now costing us," and "code that another
engineer on the team dislikes." These are not the same thing, and
treating them as the same thing makes the term useless for the
conversation it was coined to enable.

Ward Cunningham's original metaphor was financial: debt is a
deliberate trade-off where you borrow against the future to ship in
the present, knowing that the interest payments will come due. The
metaphor is useful precisely because it implies intentionality,
awareness, and an obligation to repay. What the industry has done
with the term — applying it to every form of code dissatisfaction —
has diluted it to the point where "tech debt" in a planning meeting
can mean anything from "this will cost us $200K in engineer-hours if
we don't address it this quarter" to "I would have used a different
design pattern."

The distinction matters because the response to each is different.
Actual debt requires a business decision about when to repay it.
Entropy requires ongoing maintenance discipline. Ignorance requires
training and code review. Disagreement requires nothing — it is not
a problem, it is a preference.

## Three forms of technical debt

### Deliberate debt

A conscious trade-off made with understanding of the consequences.
The team knows the implementation will not scale, will not handle
edge cases, or will not meet the long-term architectural vision —
and ships it anyway because the business need is immediate and the
cost of doing it right exceeds the cost of doing it now and fixing
it later.

This is debt in the financial sense. It has a principal (the
difference between what was built and what should have been built),
an interest rate (the ongoing cost of working around the limitation),
and a repayment plan (the work required to replace the shortcut with
the proper implementation). When a team says "we'll build the
enrollment flow with hard-coded tenant logic for launch and
generalize it in Q2," they are taking on deliberate debt with a
stated repayment timeline.

Deliberate debt is not inherently bad. It is a tool. Startups that
refuse to take on any technical debt ship nothing. The danger is not
the debt itself — it is failing to track it, failing to communicate
it, and failing to repay it. The "we'll fix it in Q2" promise that
becomes Q3, then Q4, then "we've always done it this way" is
deliberate debt that has been defaulted on. The interest compounds:
every new feature must work around the hard-coded tenant logic, every
new engineer must learn why it is hard-coded, and every quarter the
cost of generalization grows because the system has adapted to the
shortcut.

The discipline for deliberate debt is documentation and
accountability. When the debt is taken on, record it: what was the
trade-off, what is the expected cost of repayment, what is the
trigger or timeline for repayment. When the trigger arrives, honor
it. A team that takes on deliberate debt with explicit tracking and
follows through on repayment is using debt as a tool. A team that
takes on deliberate debt and never tracks or repays it is not
managing debt — it is accumulating liabilities.

### Entropy

Code that was well-designed when written and has degraded through
accumulated changes, shifting requirements, and partial refactors.
Nobody made a decision to create the problem. The codebase aged.

Entropy is the most common form of technical debt and the hardest to
attribute to any single cause. A module that was clean and
well-bounded when it served one feature now serves four, with
conditional logic added by four different engineers over two years.
Each addition was reasonable in isolation. The aggregate is a module
that does too many things, with unclear boundaries and tangled
dependencies — the same pattern the
[Separation of Concerns](design/separation-of-concerns.md) page
describes, but arrived at through accretion rather than poor initial
design.

Entropy is not a failure of the original design. It is a natural
consequence of software that is actively used and modified. The only
codebase that does not accumulate entropy is a codebase that nobody
changes — and a codebase that nobody changes is a codebase that
serves no evolving need.

The response to entropy is not a rewrite. It is ongoing maintenance
— the same discipline the [Locality](design/locality.md) page
describes: right-size files, delete dead code, keep atomic units
atomic, use source control as a safety net. Entropy is managed by
continuous small improvements, not by periodic heroic cleanups. The
team that refactors one module per sprint accumulates less entropy
than the team that plans a "tech debt sprint" once a quarter and
never gets to it because the quarter's feature work always takes
priority.

### Ignorance

Code that was poorly designed from the start because the engineer
did not know better. Not a trade-off, not a gradual degradation — a
skill gap that produced an implementation the engineer would not
have chosen with more experience.

This is uncomfortable to name but important to distinguish from the
other forms. A junior engineer who stores policy as boolean columns
on a model (the pattern the Separation of Concerns page describes)
is not making a trade-off. They do not know that a
`CustomerCapability` query object is an option. The resulting
technical debt is real — the boolean columns will accumulate
callbacks, the callbacks will accumulate suppression flags, the
system will become harder to reason about — but the cause is not a
business decision or the passage of time. The cause is a gap in the
engineer's understanding of the available tools.

The response to ignorance-driven debt is not blame. It is training,
mentorship, and code review. The junior engineer who learns about
capability objects from a code review is less likely to introduce the
same debt in the next feature. The organization that invests in
engineering growth reduces the rate at which ignorance-driven debt
enters the codebase. The organization that does not invests in
repeated remediation instead — fixing the same patterns over and
over as new engineers make the same mistakes.

### What is not technical debt

A senior engineer who looks at a module and says "I would have used
the strategy pattern instead of a case statement" is expressing a
design preference, not identifying technical debt. If the case
statement works, is readable, handles all current cases, and is not a
source of bugs or maintenance friction — it is not debt. It is a
different choice. The strategy pattern might be better in some
abstract sense, but "better" is not a business case, and refactoring
working code to match a personal preference is not debt repayment —
it is gold-plating.

This distinction matters because "tech debt" has become the
socially acceptable way for engineers to request time for work they
find interesting. Rewriting a working system in a newer framework is
not debt repayment. Introducing a design pattern to code that does
not need it is not debt repayment. Refactoring code that the engineer
did not write into a style the engineer prefers is not debt
repayment. These may be legitimate engineering activities in some
contexts, but calling them "tech debt" misuses the term and erodes
the team's credibility when actual debt needs to be addressed.

When everything is tech debt, nothing is. The term retains its power
only when it is reserved for the three forms described above: a
deliberate trade-off that needs repayment, entropy that needs ongoing
maintenance, or an ignorance gap that produced a real structural
problem.

## Making the case

Engineers identify technical debt. Product owners and managers
authorize the time to address it. This division means that the
engineer who sees the debt must be able to articulate its cost in
terms that the business cares about — not in terms of code elegance,
architectural purity, or engineering satisfaction.

This is where many engineers struggle, and honestly. Stepping outside
the technical domain to make a business argument is uncomfortable.
The engineer's instinct is to say "this code is bad and needs to be
fixed," which is a technical judgment that communicates nothing about
business impact. The product owner hears "the engineer wants to
spend two weeks on something that produces no features," and the
answer is predictably no.

The case for addressing technical debt must be made in the language
of the business:

**Cost of delay.** "Every new feature that touches the enrollment
flow takes 40% longer than it should because the tenant logic is
hard-coded and every change requires understanding all the
workarounds. We have three enrollment features planned for Q3. If
we generalize the tenant logic now (two weeks), the three features
ship in six weeks instead of nine. If we don't, the four features
planned for Q4 will be even slower."

**Risk.** "The enrollment flow has no test coverage for the
hard-coded tenant paths. We've had two production incidents this
quarter from changes that broke a tenant-specific workaround. Each
incident took a senior engineer four hours to diagnose and fix.
Generalizing the logic and adding test coverage reduces the
probability of future incidents."

**Opportunity cost.** "The current enrollment flow cannot support
the multi-region expansion planned for Q4 because tenant logic is
hard-coded to assume a single region. We can either generalize it
now as a planned two-week project, or discover in Q4 that the
expansion requires a four-week rewrite under deadline pressure."

Each of these frames the debt in terms the business already
understands: time, money, risk, and opportunity. The code is not
"bad" — it is *costing the business measurable resources* and *the
cost is increasing over time*. This is the language that gets work
prioritized.

### The spreadsheet test

A useful heuristic: if the technical debt cannot be described in a
line item on a spreadsheet — with an estimated cost, an estimated
benefit, and a timeline — it is probably not debt. It is a
preference, a cleanup, or a wish. Debt has a principal and an
interest rate. If neither can be estimated, even roughly, the
argument is not ready to be made.

This does not mean the estimate must be precise. "This will save
approximately 20 engineer-hours per quarter" is sufficient. "This
will make the code better" is not. The spreadsheet test forces the
engineer to quantify — and if the quantification reveals that the
cost is negligible, that is useful information too. Not all debt is
worth repaying. Some debt has a low interest rate and a high
repayment cost, and the rational decision is to let it ride.

## Living with debt

Not all technical debt should be repaid. This is the part of the
metaphor that engineers resist most, because the instinct is to fix
everything — the same impulse the
[Tactical Posture](tactical-posture.md) page describes in the
refactoring trap.

Some debt has a low interest rate. The hard-coded tenant logic works.
It is ugly, it is a known liability, and every new engineer asks
"why is this hard-coded?" But if the enrollment flow changes once a
quarter, the cost of working around the hard-coding is two extra
hours per quarter. The cost of generalizing it is two weeks. The
break-even point is five years. The rational decision is to document
the debt, accept the quarterly cost, and spend the two weeks on
something that produces more value.

Some debt is in code that is being replaced. Investing two weeks in
cleaning up a module that will be deprecated in Q4 is not debt
repayment — it is waste. The debt's interest stops accruing when the
module is retired. Spending effort on it now reduces the budget
available for the replacement.

Some debt is structural and cannot be repaid incrementally. A
database schema that was designed around one access pattern and now
serves twelve is not fixable with a series of small refactors. It
requires a migration — a planned, coordinated effort with its own
risk assessment, backward compatibility strategy, and rollback plan.
The decision to undertake a migration is a business decision, not an
engineering one, and it should be made with the same rigor as any
other investment: what does it cost, what does it produce, and what
is the alternative?

The discipline is not "repay all debt." The discipline is "know what
debt exists, know what it costs, and make conscious decisions about
what to repay, what to tolerate, and what to let expire." A team
that tracks its debt and makes explicit decisions about it is in a
fundamentally different position from a team that accumulates debt
without awareness and discovers it during an incident.

### The interest rate is not constant

The "let it ride" arithmetic above assumes the interest rate is
fixed: two hours per quarter now, two hours per quarter in three
years. Some debt does not behave that way. Its interest rate is a
function of something that grows — row count, traffic, tenants,
integrations — and a cost that was negligible at launch becomes
ruinous at scale without anyone changing a line of code.

An example. PostgreSQL's autovacuum decides when to clean up a
table's dead rows using a scale factor: by default it waits until
dead tuples exceed 20% of the table (plus a fixed threshold of 50)
before vacuuming. RDS inherits this default. A team running a
transactional workload on RDS PostgreSQL never looked at it, because
there was no reason to. At ten thousand rows, autovacuum fired after
two thousand dead tuples — many times a day. The tables were clean,
the planner statistics were fresh, and the default was, at that
size, correct.

The tables grew. Hundreds of thousands of rows, then millions, then
approaching billions. The threshold grew with them: 20% of a billion
rows is two hundred million dead tuples that must accumulate before
autovacuum runs at all. Functionally, autovacuum stopped running on
the tables that needed it most. Dead rows piled up in the heap and
in every index. The visibility map went stale, so index-only scans
fell back to heap fetches. Statistics — governed by a sibling scale
factor of 10% — aged the same way, and the planner started choosing
plans for a table that no longer existed. Queries that had been fast
got slower, then slower again, on a curve steeper than the growth in
data that was supposedly the explanation.

Nobody noticed why, because nothing had changed. No deploy, no
migration, no configuration edit. The dashboards showed rising
latency against rising row counts, and "the tables are bigger" is a
satisfying enough story that nobody looked further for a long time.
The debt was not on any inventory. It had never been taken on — it
came in the box.

When the cause was finally found, repayment was harder than it would
have been at any earlier point. The first vacuum of a table carrying
hundreds of millions of dead tuples runs for hours, throttled by
autovacuum's cost-based delay, and occupies one of a small fixed pool
of workers while every other table waits. Plain `VACUUM` marks space
reusable but does not return it; the bloat that had accumulated
stayed until a `VACUUM FULL` (which takes an exclusive lock) or
`pg_repack` — an operation with its own maintenance window and risk
assessment. Indexes needed rebuilding. And the correct fix — per-table
storage parameters that replace the percentage with a fixed
threshold, so a billion-row table vacuums after a hundred thousand
dead tuples rather than two hundred million — had to be calibrated
table by table under production pressure rather than as a routine
tuning pass.

```sql
ALTER TABLE enrollments SET (
  autovacuum_vacuum_scale_factor  = 0,
  autovacuum_vacuum_threshold     = 100000,
  autovacuum_analyze_scale_factor = 0,
  autovacuum_analyze_threshold    = 50000
);
```

The lesson is not "tune autovacuum" — though do. The lesson is about
the taxonomy. This debt was not deliberate; nobody chose it. It was
not entropy in the code; the code was unchanged. It was closest to
ignorance — the team did not know the parameter existed — except
that the default was *right* when the system was small, so there was
no mistake for code review to catch. It was a default whose interest
rate was indexed to scale, and the only defense against that class
of debt is periodic inspection of things that appear to be working.
Every managed service ships with defaults calibrated for the median
customer at signup. A system that outgrows the median has outgrown
the defaults, whether or not anyone has looked.

## Questions to ask

1. Is this technical debt, or is it a design preference? If the code
   works, is maintainable, and is not a source of bugs or friction,
   it is not debt — it is a different choice.
2. Can the cost of this debt be estimated in engineer-hours, incident
   frequency, or delayed features? If not, the argument for
   addressing it is not ready.
3. Is this debt deliberate, entropic, or ignorance-driven? The
   response to each is different: track and repay, maintain
   continuously, or train and review.
4. What is the interest rate? Does this debt cost the team every
   sprint, once a quarter, or only during a specific type of change?
   Low-interest debt may not be worth repaying.
5. Is the code that carries this debt being replaced? If so,
   investing in cleanup is waste. Document it, accept it, and spend
   the effort on the replacement.
6. When was this debt last discussed? If nobody has evaluated it in
   six months, the team does not know whether it is still relevant,
   whether the cost has changed, or whether the repayment plan is
   still appropriate.
7. Does the interest rate scale with something? A cost that is
   proportional to row count, traffic, or tenant count is not a
   fixed quarterly expense — it is a curve. Debt that is cheap to
   carry today may be unpayable at ten times the data, and defaults
   nobody chose are the most likely place for this debt to hide.
