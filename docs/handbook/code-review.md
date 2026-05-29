# Code Review

## The reviewer's dilemma

A team lead is responsible for every line of code their team ships.
This is not a formal policy at most organizations — it is an
informal reality. When a production incident traces back to a
commit, the question is not just "who wrote this" but "who approved
this." The reviewer's name is on the merge. The team lead's
reputation is on the outcome.

This creates a tension that most engineering writing about code
review ignores entirely. The advice is always "trust your team" and
"don't be a bottleneck" and "focus on the big picture." The same
organizations that give this advice are also not thrilled when bugs
ship. The reviewer oscillates between two failure modes: trusting
glances that serve as a sanity check and let defects through, or
line-by-line scrutiny that catches problems but rewrites every
commit in the reviewer's image — at which point the team is not a
team but a group of typists implementing the reviewer's design.

Neither mode is sustainable. The first mode ships bugs. The second
mode ships resentment — and still ships bugs, because a reviewer
who is exhausted from rewriting everything will eventually miss the
one that matters.

The resolution is not "find the right balance." That is useless
advice — a recommendation to be perfect without instructions for how.
The resolution is to review at the right layer: design decisions
and contracts get scrutiny; implementation details get trust.

## What to review

### Contracts and boundaries

The highest-value review activity is evaluating the contracts a
change introduces or modifies. A new public method on a service
class, a new API endpoint, a new database column, a new event in
the event system — these are commitments. Once shipped, other code
will depend on them. Changing them later requires coordination,
migration, and risk. The cost of getting a contract wrong is orders
of magnitude higher than the cost of getting an implementation
detail wrong.

When reviewing a PR, the first question is: **what commitments does
this change make?** A new public interface is a commitment. A new
database migration is a commitment. A new column on a heavily-read
table is a commitment. A change to an existing API response shape is
a commitment. These deserve scrutiny — not because the author is
untrustworthy, but because commitments are expensive to reverse and
the reviewer brings a perspective the author does not have: the
perspective of someone who did not just spend three hours inside the
implementation.

```ruby
# This is a contract. Review it carefully.
class EnrollmentService
  def enroll(student:, course:, payment_method:)
    # ...
  end
end
```

The method signature — its name, its parameters, its return type —
is a commitment. Once other code calls `EnrollmentService#enroll`
with these parameters, changing the signature requires finding and
updating every caller. The implementation inside the method can be
refactored freely. The signature cannot.

### Design decisions

A PR that introduces a new pattern — a registry, a factory, an
event bus, a new layer of abstraction — deserves more review time
than a PR that uses an existing pattern. The question is not "is
this implementation correct" but "should this pattern exist here at
all?" The [Decoupling Patterns](design/decoupling-patterns.md) page
describes the progression from simple branching to registries and
dispatch tables. Each step adds power and complexity. The reviewer's
job is to ask whether the complexity is justified by the current
problem — not by a hypothetical future problem that may never
arrive.

This is the review comment that matters most and is hardest to
write: "This works, but I'm not sure we need this level of
abstraction yet. Can we start with the simpler approach and
introduce the pattern when the third case arrives?" It is hard to
write because it sounds like criticism of the author's judgment. It
is not. It is a design conversation between two engineers who see
the system from different angles.

### Knowledge gaps

Code review is the primary mechanism for distributing knowledge
across a team. A junior engineer who submits a PR with boolean
columns where a capability object belongs (the pattern the
[Separation of Concerns](design/separation-of-concerns.md) page
describes) has a knowledge gap. The reviewer who spots this has two
choices: request a change with a link to a pattern, or request a
change with an explanation of why the pattern exists and what
problem it solves.

The first approach fixes the PR. The second approach fixes the
engineer. The second approach takes longer for this PR and saves
time on every future PR from that engineer. This is the investment
that distinguishes a review practice from a gatekeeping practice.

The review comment that teaches is specific, contextual, and
non-judgmental:

> This works as written, but the boolean columns will accumulate
> callbacks as we add more policy rules. Consider extracting a
> `CustomerCapability` object that encapsulates the policy logic —
> the Separation of Concerns page in our handbook has a worked
> example. Happy to pair on this if it would help.

The review comment that polices is generic, contextless, and
implicitly judgmental:

> Don't use booleans for this. Use the strategy pattern.

The first comment explains the *why*, points to a resource, and
offers help. The second comment asserts authority without
transferring knowledge. The first comment is an investment in the
engineer. The second is a tax on the engineer's autonomy.

### What not to review

**Style.** If a formatter can enforce it, a human should not review
it. Indentation, line length, brace placement, import ordering —
these are linter concerns. A review comment about style is a review
comment that displaces a review comment about design. Configure the
formatter, enforce it in CI, and never discuss it in a PR again. The
[Code Quality](code-quality-argument.md) page makes this case at
length.

**Implementation details that are correct and clear.** The author
chose a `for` loop where the reviewer would have used `map`. The
author used a temporary variable where the reviewer would have
inlined the expression. The author wrote three lines where the
reviewer would have written one. If the code is correct, readable,
and does not violate a team convention — it is not a review finding.
It is a preference, and preferences do not belong in reviews.

This is the hardest discipline for experienced reviewers. The
instinct to say "I would have done this differently" is strong, and
the instinct is not wrong — the reviewer often *would* have done it
better. But "better" in the reviewer's style is not the same as
"better for the team." A codebase where every PR is rewritten to
match the most senior engineer's preferences is a codebase that only
one person can maintain. A codebase where multiple competent
approaches coexist is a codebase that the team owns.

**Mechanical changes.** A PR that renames a variable across forty
files, updates a dependency, or applies a migration does not need
design review. It needs a sanity check: does the rename cover all
occurrences, does the dependency bump introduce breaking changes,
does the migration have a rollback path. These are checklist items,
not conversations.

## How to give a review

### Distinguish requests from suggestions

The most common source of friction in code review is ambiguity about
whether a comment is a required change or a thought. The reviewer
writes "consider using X here" and means "this is optional." The
author reads it as "you must change this or I won't approve." The
result is either unnecessary rework (the author changes it to avoid
conflict) or unnecessary conflict (the author pushes back on what
was never a requirement).

Use explicit labels. Many teams use conventions like:

- **Blocking:** "This needs to change before merge." Reserve for
  correctness issues, contract problems, and security concerns.
- **Suggestion:** "Consider this approach. Up to you." For
  alternative implementations the author may or may not prefer.
- **Question:** "I don't understand this. Can you explain?" For
  genuine confusion, not rhetorical criticism.
- **Nit:** "Minor — take it or leave it." For the trivial things
  that are not worth a follow-up conversation.

The labels matter less than the practice: every comment should be
unambiguous about whether it blocks the merge.

### Explain the why

A review comment that says *what* to change without saying *why* is
an instruction, not a review. The author complies or resists, but
in neither case do they learn anything. The why is the part that
transfers knowledge:

> **What:** Extract this into a separate method.
>
> **Why:** This block runs inside a database transaction. If the
> external API call on line 47 times out, the transaction holds an
> open lock for the duration of the timeout. Extracting the API call
> to run before the transaction opens avoids the lock contention
> under load.

The author who reads the why understands not just this PR but every
future PR that involves transactions and external calls. The author
who reads only the what learns to extract methods when told to.

### Review the PR, not the person

The review comment "Why did you do it this way?" reads as
accusation. The review comment "What was the reasoning behind this
approach?" reads as curiosity. They ask the same question. The
second one gets a useful answer.

This is not about being nice. It is about getting information. A
defensive author explains less, pushes back more, and is less likely
to surface the context the reviewer needs to make a good judgment.
An author who feels that the review is a collaborative conversation
explains their reasoning, surfaces constraints the reviewer did not
know about, and is more likely to accept feedback that improves the
code.

The heuristic: review comments should reference the code, not the
coder. "This method has a subtle concurrency issue" rather than "you
missed a concurrency issue." "This abstraction may be premature"
rather than "you over-engineered this."

## How to receive a review

### Assume good faith

The reviewer who requests a change is not attacking the author's
competence. They are doing the job the team has asked them to do:
evaluate the change from a perspective the author cannot have.
The author has spent hours inside the implementation. The reviewer
is seeing it for the first time. The reviewer's confusion is
information — if the reviewer does not understand the code on first
read, the next engineer who encounters it in six months will not
either.

When a review comment feels wrong, the productive response is to
explain the reasoning: "I considered that approach but chose this
one because of X constraint." This gives the reviewer new
information. "I disagree" without explanation gives them nothing.

### Separate ego from code

A PR is not a painting. It is a proposal. The author proposes a
change. The reviewer evaluates it. If the evaluation finds problems,
the proposal is revised. This is the process working correctly, not
a judgment on the author's ability.

This is easier to say than to practice, and the difficulty scales
with experience. A senior engineer whose PR receives substantive
feedback feels it differently than a junior engineer — the senior
engineer has a longer track record of being right and a stronger
expectation of deference. But the review process does not defer to
seniority. It defers to the code. A correct criticism from a junior
reviewer is still correct.

### Know when to push back

Not every review comment deserves compliance. A reviewer who
requests a rewrite because they would have designed it differently
is expressing a preference, not identifying a defect. A reviewer
who requests a change that introduces a new pattern the team has not
agreed on is proposing a design decision, not correcting an error.

The author's responsibility is to distinguish between review
comments that identify genuine problems (bugs, contract violations,
security issues, maintainability concerns) and review comments that
express preferences (style, alternative approaches, different
abstractions). The first category requires action. The second
category requires a conversation — "I see a different approach here.
Let's discuss which one the team should standardize on" — not
automatic compliance.

## The review as a conversation

The best code reviews are conversations that end with both
participants knowing something they did not know before. The
reviewer learns the author's reasoning, the constraints they
navigated, the trade-offs they made. The author learns how the
change looks from outside the implementation, what assumptions are
not obvious, what parts of the system the change touches that the
author may not have considered.

The worst code reviews are transactions: the author submits code,
the reviewer stamps it or rejects it, and nobody learns anything.
This mode is efficient in the short term and corrosive in the long
term. A team that rubber-stamps PRs ships bugs. A team that
gate-keeps PRs ships resentment. A team that *discusses* PRs ships
knowledge — and the knowledge compounds in ways that the stamps and
the gates never can.

### The speed question

A review that sits for three days is not a review. It is a
bottleneck. The author has moved on to other work. The context is
stale. The feedback, when it finally arrives, requires the author to
context-switch back into code they have mentally closed. The cost is
not just the delay — it is the degraded quality of the iteration,
because the author is no longer thinking about the problem with the
same depth they had when the PR was fresh.

The goal is same-day review for most PRs. Not same-hour — reviewers
have their own work. But within the same working day. A PR submitted
in the morning should have initial feedback by end of day. A PR
submitted in the afternoon should have feedback by the following
morning. This cadence keeps the context warm and the iteration tight.

Teams that struggle with review speed typically have a structural
problem, not a discipline problem: too few reviewers, too many PRs,
or no clear ownership of review responsibility. The fix is
structural — review rotation, smaller PRs, clear assignment — not
exhortation to "review faster."

### The size question

A 2,000-line PR does not get reviewed. It gets skimmed, approved,
and hoped for the best. The reviewer cannot hold 2,000 lines of
change in their head, cannot evaluate the design decisions across
that span, and cannot provide meaningful feedback on the
interactions between changes that are separated by hundreds of lines
of diff.

The discipline is small PRs. Not arbitrarily small — a PR should be
a coherent unit of change. But "coherent unit" does not mean "entire
feature." A feature that touches the data layer, the application
layer, and the presentation layer can be three PRs: the migration
and model changes, the service logic, and the UI. Each is
reviewable. The aggregate is not.

The objection is always "but splitting PRs is overhead." It is. The
overhead is less than the cost of a 2,000-line PR that ships a bug
because the reviewer could not meaningfully evaluate it. Small PRs
are faster to review, easier to revert, and simpler to bisect when
something breaks. The overhead is an investment in review quality.

## The leadership problem

Code review is the point where many technically skilled engineers
first encounter a truth about leadership: the skills that earned the
promotion are not the skills the role requires.

The engineer who was promoted to team lead was promoted because they
are technically excellent. They write clean code, catch edge cases,
think carefully about design, and hold themselves to a high standard.
These are the qualities the organization valued enough to reward
with authority. The problem is that every one of these qualities, if
applied directly to reviewing other people's code, produces the
rewrite failure mode described below.

The technically excellent engineer reviews a PR and sees three
things they would have done differently. Their instinct — the same
instinct that made them excellent — is to request changes. The code
would be better their way. They are probably right. But "better" in
the reviewer's style and "better for the team" are not the same
thing, and the gap between them is the gap between being a strong
individual contributor and being a strong leader.

The transition requires a specific skill that technical work does
not develop: the ability to distinguish between "this is wrong" and
"this is not how I would have done it." The first is a review
finding. The second is a preference — and acting on it teaches the
team that their judgment is not trusted. An engineer whose every PR
is rewritten stops making design decisions. They write what they
think the reviewer wants, or they write the minimum and let the
reviewer fill in the rest. Either way, the team lead has created a
team that cannot function without them — the opposite of the goal.

The hardest version of this transition is learning to let code ship
that you would have written differently but that is correct, clear,
and maintainable. This feels like lowering your standards. It is
not. It is recognizing that the team's standard is not the lead's
personal standard — it is the standard the team can collectively
sustain. A team that ships code at a level every member can maintain
is more resilient than a team that ships code at a level only the
lead can maintain.

None of this is taught. Engineering curricula do not cover it.
Technical interviews do not evaluate it. The engineer who becomes a
team lead is expected to develop these skills on the fly, usually by
making the mistakes described in this page and learning from the
fallout. The best thing the framework can offer is naming the
problem explicitly: the reviewer's dilemma is not a personal failing.
It is a structural consequence of promoting people for skills that
are necessary but not sufficient for the role they are promoted
into.

### When trust breaks down

Everything above assumes a baseline of trust — that the team is
competent, that review is about improving good work, and that the
lead's job is to resist the urge to rewrite. But sometimes the
trust is not there, and the lead knows it. There is a team member
whose PRs consistently require heavy revision. Whose code
introduces bugs that the reviewer catches more often than not.
Whose design decisions do not improve with feedback. The lead finds
themselves reviewing this person's work line by line, not because of
a control problem but because experience has shown that the
alternative is shipping defects.

This is uncomfortable to name, but it must be named because the
failure to address it poisons the review practice for the entire
team. The lead who micromanages one engineer's PRs burns review
time that should be spent on the rest of the team. The rest of the
team notices the uneven scrutiny and draws conclusions — either that
the lead plays favorites (lighter review for some, heavier for
others) or that the lead's review standards are arbitrary. The
engineer being micromanaged either becomes defensive and adversarial
or becomes passive and stops exercising independent judgment — both
of which make the problem worse.

The first honest question is whether the problem is a knowledge gap
or a capability gap. These require different responses.

**A knowledge gap is addressable.** The engineer does not know the
patterns, the codebase conventions, or the domain well enough to
make sound design decisions. This is the situation the knowledge
gaps section above describes — the review comment that teaches, the
explanation that transfers understanding, the pairing session that
accelerates learning. A knowledge gap is normal for any engineer
who is new to a team, a domain, or a level of responsibility. The
lead's job is to invest in closing it: more detailed review
comments, more pairing, explicit mentorship on the areas where the
gap is widest. The investment has a timeline — if the gap is
closing, the investment is working.

**A capability gap is a management problem, not a review problem.**
If the engineer has received consistent feedback, explicit
mentorship, and reasonable time to improve — and the quality of
their work has not changed — the lead is facing a performance
issue, not a review issue. No amount of thorough code review will
fix it. The review process is absorbing the cost of a problem that
belongs in a one-on-one, a performance improvement plan, or a
conversation with the lead's own manager about team composition.

The mistake most leads make is using code review as the venue for
managing performance. The PR becomes the recurring confrontation:
heavy feedback, requested changes, re-review, more changes. The
engineer feels attacked. The lead feels exhausted. The code
improves incrementally per PR but the underlying pattern does not
change. This is not code review — it is performance management
conducted through the wrong channel.

The discipline is to separate the two. Review the code as code.
Address the pattern as a management concern. "This PR needs these
changes" is a review conversation. "We've had this same pattern of
issues across the last several PRs, and I want to talk about what
support would help" is a management conversation. The first happens
in the PR. The second happens in a one-on-one. Mixing them makes
both worse.

This is another skill that technical work does not develop. The
lead who was promoted for writing excellent code must now make
judgments about people — their trajectory, their capacity, their
fit for the role — and have conversations that are uncomfortable
by nature. The only advice the framework can offer is: have the
conversation early. Every week spent managing a capability gap
through code review is a week of accumulated frustration on both
sides that makes the eventual conversation harder.

## When this goes wrong

Code review is a practice with failure modes on every side:

- **The rubber stamp.** LGTM with no comments. The reviewer glances
  at the diff, sees nothing obviously broken, and approves. This is
  not review — it is the appearance of review. It satisfies the
  branch protection rule without providing any of the value the rule
  was meant to ensure. The rubber stamp is the most common review
  failure, and it is invisible in metrics because the PR was
  "reviewed" and "approved."

- **The rewrite.** The reviewer would have implemented it
  differently and requests changes until the PR matches their
  approach. This produces correct code in the reviewer's style and a
  team that stops trying. If every PR is rewritten to match one
  engineer's preferences, the team learns that their own judgment is
  not valued — and they stop exercising it. The reviewer becomes the
  single point of failure they were trying to prevent.

- **The nitpick avalanche.** Twelve comments about variable naming,
  whitespace, and import ordering. Zero comments about the database
  query that will scan every row in the table. The reviewer has
  spent their attention budget on trivia and has nothing left for
  substance. The author receives twelve pieces of feedback, none of
  which matter, and concludes that code review is performative.

- **The stale PR.** Nobody reviews it. It sits for days. The author
  pings. The reviewer apologizes, skims it quickly, and approves —
  the rubber stamp by another name, with the added cost of blocking
  the author for the intervening days.

- **The adversarial review.** The reviewer uses the PR as a venue
  for a design disagreement that should have been settled before the
  code was written. The author implemented an approach the team
  discussed. The reviewer disagrees with the approach and uses the
  review to re-litigate. The PR becomes a proxy war. The code is
  collateral damage.

Each of these is a symptom of a missing agreement about what code
review is for. If the team has not explicitly agreed on the purpose
and scope of review — what is in scope, what is out of scope, what
blocks a merge and what does not — each reviewer invents their own
standard, and the author cannot predict which standard will apply to
their next PR.

## Questions to ask

1. For the last ten PRs the team merged: how many review comments
   were about design decisions, and how many were about style or
   preferences? If the ratio favors style, the review practice is
   spending its attention on the wrong layer.
2. What is the team's average time from PR submission to first
   review comment? If it is measured in days, the review practice
   is a bottleneck, not a quality gate.
3. Can a new team member read the review history and learn how the
   team makes design decisions? If the reviews are rubber stamps or
   nitpick lists, the answer is no — and the team's institutional
   knowledge lives only in the heads of senior engineers.
4. When was the last time a review comment taught the author
   something they did not already know? If the answer is "I can't
   remember," the review practice has become gatekeeping.
5. When was the last time a reviewer learned something from an
   author's explanation during review? If review only flows in one
   direction — reviewer to author — it is not a conversation. It is
   an inspection.
6. Does the team have an explicit, shared understanding of what
   blocks a merge and what does not? If not, every review is a
   negotiation — and negotiations are slower, more stressful, and
   less consistent than agreements.
