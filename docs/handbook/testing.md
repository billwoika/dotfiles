# Testing

## The honest reality

Nobody likes writing tests.

This is not a controversial claim. It is an empirical observation
confirmed by every codebase with a `spec/` directory that has fewer
files than `app/`, every sprint where test coverage drops because the
feature shipped without specs, and every standup where "I still need
to add tests" is the last item mentioned.

Test-driven development sounds excellent in theory. Write the test
first. Watch it fail. Write the code to make it pass. Refactor.
Repeat. The loop is clean, the discipline is sound, and the result
is code that is tested by construction. In practice, the author of
this framework has never sustained TDD for more than a few sessions.
The honest assessment is that most engineers write the code first,
verify it works manually, and then write the tests — if the tests
get written at all.

This is not an endorsement of skipping tests. It is an acknowledgment
that testing is a discipline that resists the natural workflow of
writing code, and that pretending otherwise does not help. What helps
is understanding *why* tests exist, *what* makes a test useful, and
*how* to write tests that are worth the ceremony they impose.

## What tests are for

Tests are contract enforcers.

A unit test makes a claim: "given these inputs, this code produces
this output." When someone modifies the code — intentionally or
accidentally — and the output changes, the test fails. The failure is
a signal: the contract was broken. The developer who broke it must
now decide whether the break was intentional (update the test) or
accidental (fix the code).

This is the entire value of a test. Not coverage metrics, not green
badges in CI, not the satisfaction of watching a test suite pass. The
value is the *signal* — the automated notification that a behavioral
contract has been violated. Everything else is ceremony in service of
that signal.

A test that does not produce a useful signal when a contract is
broken is a test that consumes maintenance effort without providing
value. A test that produces a false signal — that fails when no
contract was broken — is worse: it trains the team to ignore
failures, which destroys the signal entirely.

## The tautology problem

Many tests are tautologies. They assert what was just constructed.
They verify that the code does what the code says it does, which
is not a meaningful claim:

```ruby
RSpec.describe Customer do
  it "has a name" do
    customer = Customer.new(name: "Jane Doe")
    expect(customer.name).to eq("Jane Doe")
  end

  it "has an email" do
    customer = Customer.new(email: "jane@example.com")
    expect(customer.email).to eq("jane@example.com")
  end

  it "has a status" do
    customer = Customer.new(status: :active)
    expect(customer.status).to eq(:active)
  end
end
```

These tests verify that Ruby's attribute assignment works. They will
never fail unless the attribute is removed or renamed — and if it is,
the application will also fail in ways that are immediately visible.
The test adds no signal beyond what a missing-method error would
provide.

Similarly, stubbed network calls that verify the stub's return value
are testing the test, not the code:

```ruby
RSpec.describe LoyaltyProvider do
  it "returns member data" do
    stub_request(:get, "https://api.loyalty.example.com/members/42")
      .to_return(body: { id: 42, tier: "gold" }.to_json)

    result = LoyaltyProvider.get_member(42)
    expect(result["id"]).to eq(42)
    expect(result["tier"]).to eq("gold")
  end
end
```

The test asserts that the stub returns what the stub was told to
return. If the real API changes its response format, this test
continues to pass — it is testing a fiction. The signal it produces
is "the stub works," which is not useful information.

## What makes a test useful

A useful test verifies behavior that is non-obvious, conditional, or
boundary-dependent — behavior that a future developer could break
without realizing it:

```ruby
RSpec.describe CustomerCapability do
  describe "#enrolled?" do
    it "returns true when the customer has an active enrollment override" do
      customer = create(:customer)
      create(:capability_override, customer: customer, capability: :enrollment, enabled: true)

      expect(CustomerCapability.new(customer).enrolled?).to be true
    end

    it "falls back to the tenant default when no override exists" do
      tenant = create(:tenant, enrollment_default: true)
      customer = create(:customer, tenant: tenant)

      expect(CustomerCapability.new(customer).enrolled?).to be true
    end

    it "returns false when the tenant default is false and no override exists" do
      tenant = create(:tenant, enrollment_default: false)
      customer = create(:customer, tenant: tenant)

      expect(CustomerCapability.new(customer).enrolled?).to be false
    end

    it "override takes precedence over tenant default" do
      tenant = create(:tenant, enrollment_default: true)
      customer = create(:customer, tenant: tenant)
      create(:capability_override, customer: customer, capability: :enrollment, enabled: false)

      expect(CustomerCapability.new(customer).enrolled?).to be false
    end
  end
end
```

Each test verifies a specific resolution rule in the capability
system. The rules are non-obvious: overrides take precedence over
tenant defaults, the absence of an override falls through to the
tenant default, and the tenant default can be either true or false. A
future developer who modifies the resolution logic — perhaps adding a
new precedence level or changing the fallback behavior — will break
one of these tests, and the failure will tell them exactly which
contract they violated.

## The testing hierarchy

### Unit tests

Unit tests verify the behavior of a single function or class in
isolation. They are fast, deterministic, and cheap to write and
maintain — when they test the right things.

The contract-enforcement framing makes the value clear: if this
closed implementation is unknowingly broken by a change, the unit
test should throw a flag. The key word is "unknowingly." A developer
who is deliberately changing the behavior will update the tests as
part of the change. The unit test protects against the *accidental*
behavioral change — the early return that silently excludes a case,
the conditional that was inverted, the default that was changed
without understanding the downstream impact.

The failure mode of unit tests is tautology (testing what was just
constructed) and over-mocking (replacing so many collaborators with
mocks that the test verifies the mocking framework, not the code).
The [Decoupling Patterns](design/decoupling-patterns.md) page covers
this in depth: when the in-memory substitute breaks, it signals that
the code has coupled itself to implementation details it has no
business knowing about.

### Integration tests

Integration tests verify that multiple components work together
correctly — that the service calls the repository, the repository
queries the database, and the result is what the application expects.
They are slower than unit tests, require more infrastructure (a test
database, a queue, an external service mock), and catch a category of
bugs that unit tests cannot: the interface mismatch, the serialization
error, the transaction boundary that behaves differently under
concurrent access.

Integration tests are important when the contract between components
is the thing being verified. They become noise when the contract is
already known to be broken. A failing integration test for a service
whose API is being actively rewritten is not a signal — it is a
reminder that the rewrite is not done, which the team already knows.
When a test failure becomes expected background noise, it has lost
its value as a signal and should be either fixed or explicitly
skipped with a documented reason.

### End-to-end tests

End-to-end tests verify the system from the user's perspective:
submit a form, verify the database was updated, verify the email was
sent, verify the UI shows the correct state. They are the closest
approximation to "does this actually work?" and the hardest to
maintain.

Use cases change. Infrastructure changes. The UI is redesigned. The
email provider is swapped. Each change potentially invalidates the
e2e test suite, and the tests are the last priority when shipping the
change that broke them. The result is a suite that is perpetually
catching up, perpetually flaky, and perpetually eroding the team's
confidence in test results.

The honest assessment: e2e tests are valuable and fragile. They
should exist for critical paths (signup, payment, enrollment — the
flows that produce revenue or legal liability if broken) and should
not attempt comprehensive coverage of every user interaction. A small
suite of reliable e2e tests for critical paths is worth more than a
large suite of flaky tests that the team has learned to re-run until
they pass.

## RSpec pitfalls

RSpec is an expressive testing framework with enough rope to produce
test suites that are harder to read and maintain than the code they
test. The following are the most common pitfalls.

### Context and nesting depth

RSpec's `context` blocks are meant to organize tests around
conditions. Used sparingly, they clarify intent. Nested four deep,
they become a puzzle:

```ruby
# Too deep: the reader must reconstruct the state by reading four levels
RSpec.describe EnrollmentService do
  context "when the tenant allows enrollment" do
    context "when the customer is active" do
      context "when the customer has not been enrolled before" do
        context "when the loyalty provider is available" do
          it "enrolls the customer" do
            # ...what state am I even in?
          end
        end
      end
    end
  end
end
```

By the time the reader reaches the `it` block, they must mentally
reconstruct the state from four `context` descriptions — and they
must trust that the `before` blocks at each level correctly establish
that state. Each level of nesting is a layer of indirection between
the test's setup and its assertion.

Two levels of context is a reasonable maximum. Beyond that, the
conditions should be encoded in the setup explicitly rather than
implied by nesting.

### before blocks and invisible setup

`before` blocks that modify state across multiple levels of nesting
create tests where the setup is invisible at the point of assertion:

```ruby
RSpec.describe EnrollmentService do
  let(:tenant) { create(:tenant) }
  let(:customer) { create(:customer, tenant: tenant) }

  before { allow(LoyaltyProvider).to receive(:available?).and_return(true) }

  context "when the tenant requires double opt-in" do
    before { tenant.update!(requires_double_opt_in: true) }

    it "sends a confirmation email" do
      # The reader must check two before blocks and two let declarations
      # to understand what state this test starts in
      EnrollmentService.enroll(customer)
      expect(ActionMailer::Base.deliveries.count).to eq(1)
    end
  end
end
```

The test reads as "it sends a confirmation email" but the conditions
under which it does so — the tenant's configuration, the loyalty
provider's availability, the customer's relationship to the tenant —
are scattered across `let` declarations and `before` blocks at
multiple levels. A developer debugging a failure must read the
entire file to reconstruct the state.

The alternative is explicit setup in each test:

```ruby
it "sends a confirmation email when the tenant requires double opt-in" do
  tenant = create(:tenant, requires_double_opt_in: true)
  customer = create(:customer, tenant: tenant)
  allow(LoyaltyProvider).to receive(:available?).and_return(true)

  EnrollmentService.enroll(customer)

  expect(ActionMailer::Base.deliveries.count).to eq(1)
end
```

Longer, but self-contained. Every precondition is visible at the
point of assertion. A developer reading this test does not need to
read any other test, any `before` block, or any `let` declaration
to understand what it verifies.

### let vs. create

`let` is lazily evaluated — the block executes only when the variable
is first referenced. This is a feature that frequently becomes a bug:

```ruby
RSpec.describe "enrollment notification" do
  let(:customer) { create(:customer) }
  let(:enrollment) { create(:enrollment, customer: customer) }

  it "sends a notification after enrollment" do
    # enrollment has not been created yet — let is lazy
    expect(Notification.count).to eq(1)  # fails: 0 notifications
  end
end
```

The `enrollment` is never referenced in the test, so the `let` block
never executes, the enrollment is never created, and the notification
callback never fires. The fix — referencing `enrollment` before the
assertion, or using `let!` (eager evaluation) — is mechanical, but
the failure is confusing for anyone unfamiliar with the lazy
evaluation behavior.

The guideline: use `let` for values that are referenced in the test
body. Use `let!` when the creation itself has side effects that the
test depends on. When in doubt, use `create` directly in the test —
explicit is unambiguous.

### subject

`subject` is RSpec's mechanism for defining the object under test.
It is useful when the entire `describe` block tests one object and
every `it` block asserts against it:

```ruby
RSpec.describe CustomerCapability do
  subject { described_class.new(customer) }

  let(:customer) { create(:customer) }

  it { is_expected.to be_enrolled }
  it { is_expected.not_to be_messageable }
end
```

This is clean and readable — when every test asserts against the
same subject. It breaks down when tests need different setup or
assert against different aspects:

```ruby
# subject is misleading here — only half the tests use it
subject { described_class.new(customer) }

it { is_expected.to be_enrolled }

it "logs the capability check" do
  subject.enrolled?  # calling subject for its side effect, not its value
  expect(AuditLog.last.event).to eq("capability.checked")
end
```

When `subject` is called for its side effects rather than its return
value, the abstraction is being misused. Use `subject` when the
tests are assertions about the subject's state. Use explicit method
calls when the tests are about behavior or side effects.

### Collection matchers

Strict equality on collections is fragile and often tests the wrong
property:

```ruby
# Fragile: depends on insertion order
expect(Customer.active.pluck(:id)).to eq([1, 3, 7, 12])

# Fragile: breaks if any unrelated active customer exists in the test database
expect(Customer.active.count).to eq(4)
```

The first test fails if the database returns records in a different
order — which it is free to do unless the query includes an `ORDER
BY`. The second test fails if another test in the suite creates an
active customer and database cleaning is imperfect.

Choose the matcher that tests the property you care about:

```ruby
# Order-independent membership
expect(Customer.active.pluck(:id)).to contain_exactly(1, 3, 7, 12)

# Membership without exhaustiveness
expect(Customer.active.pluck(:id)).to include(3, 7)

# Size without specific members
expect(Customer.active.count).to be >= 4

# Specific record presence
expect(Customer.active).to exist(id: 7)
```

`contain_exactly` verifies membership regardless of order.
`include` verifies that specific elements are present without
requiring that they are the *only* elements. `exist` verifies that a
record matching the criteria is present. Each matcher tests a
different property, and the right choice depends on what the test is
actually claiming.

### Sidekiq and async jobs

Tests that verify Sidekiq job behavior face a timing problem: the
job is enqueued, not executed. The test must either execute the job
inline (changing the behavior from async to sync) or assert on the
enqueue and test the job separately.

```ruby
# Testing that the job was enqueued (not that it ran)
it "enqueues a welcome email job" do
  expect {
    EnrollmentService.enroll(customer)
  }.to change(WelcomeEmailJob.jobs, :size).by(1)
end

# Testing the job's behavior separately
RSpec.describe WelcomeEmailJob do
  it "sends a welcome email to the customer" do
    WelcomeEmailJob.new.perform(customer.id)
    expect(ActionMailer::Base.deliveries.last.to).to include(customer.email)
  end
end
```

The common mistake is enabling `Sidekiq::Testing.inline!` globally,
which causes every job in the test suite to execute synchronously.
This masks timing bugs that only appear in production (where the job
runs asynchronously), changes the execution order of side effects,
and makes the test suite slower by executing every job immediately.

Use `Sidekiq::Testing.inline!` only in the specific tests that
need to verify end-to-end behavior through the job. Use
`Sidekiq::Testing.fake!` (the default) everywhere else, and test
job enqueue and job behavior separately.

### Time-dependent behavior

Features that depend on the passage of time are the testing
equivalent of a load-bearing wall — you do not appreciate how much
depends on it until you try to move it.

Promotions that expire after 30 days. Trial periods. Rate limiters.
Enrollment windows. Token expiration. Invoice generation that runs
on the first of the month. Any feature whose behavior changes based
on "now" introduces a category of test fragility that is uniquely
maddening.

The naive approach uses real time:

```ruby
it "expires the promotion after 30 days" do
  promotion = create(:promotion, starts_at: 30.days.ago)
  expect(promotion).to be_expired
end
```

This works — until it does not. If the test runs within milliseconds
of midnight, `30.days.ago` may produce a timestamp on one side of a
date boundary while `Time.current` is on the other. The test passes
nine hundred and ninety-nine times out of a thousand and fails once,
at 11:59:58 PM, when the CI server happens to run the suite at the
worst possible moment. The failure is unreproducible locally. The
engineer re-runs the build, it passes, and the flake is filed away
as "CI being weird."

These are heisentests — sometimes they pass, sometimes they do not,
and the act of investigating them often changes the conditions that
caused the failure. The most entertaining heisentests are the ones
flagged over a date boundary. Date arithmetic that does not account
for a year transition — a calculation that assumes the year is
constant, or that December is always followed by a month with a
smaller number — will pass every day of the year except December 31st
or January 1st. The bug is filed. The ticket sits in the backlog.
Nobody prioritizes it because it only failed once and the re-run
passed. Then January 1st arrives the following year, and the same
bug surfaces again — in production this time, not in a test — because
no action was taken. The ticket is still open. The engineer who filed
it may or may not still be on the team. The same failure, the same
root cause, a year of inaction between the signal and the
consequence.

The problem deepens with tests that assert on relative durations:

```ruby
it "rate-limits to one request per second" do
  service.call
  service.call
  expect(service).to be_rate_limited
end
```

Whether the second call is rate-limited depends on how much time
elapsed between the two calls. On a fast machine with no load, both
calls execute within microseconds and the rate limiter does not
trigger. On a slow CI runner under heavy load, the gap might exceed
the limit. The test is not testing the rate limiter — it is testing
the execution speed of the machine.

The fix is to control time explicitly. Ruby's `timecop` gem and
Rails' built-in `travel_to` freeze or advance the clock under test
control:

```ruby
it "expires the promotion after 30 days" do
  promotion = nil

  travel_to Time.zone.parse("2026-01-01 12:00:00") do
    promotion = create(:promotion)
  end

  travel_to Time.zone.parse("2026-01-31 12:00:01") do
    expect(promotion).to be_expired
  end
end

it "is not expired at 29 days" do
  promotion = nil

  travel_to Time.zone.parse("2026-01-01 12:00:00") do
    promotion = create(:promotion)
  end

  travel_to Time.zone.parse("2026-01-30 12:00:00") do
    expect(promotion).not_to be_expired
  end
end
```

The test controls exactly what "now" is. There is no dependency on
the clock, no sensitivity to execution speed, no midnight boundary
flakes. The assertions are deterministic: the promotion was created
at a known time, the check is performed at a known time, and the
result is the same on every machine at every hour.

The broader principle: any test that calls `Time.current`,
`Time.now`, `Date.today`, or any clock-dependent function without
controlling the clock is a test that will eventually fail for reasons
that have nothing to do with the code under test. Time-dependent
tests should either freeze the clock (for point-in-time assertions)
or advance it (for duration-dependent behavior). Never rely on real
time passing between lines of a test.

A related hazard: timezone-dependent tests. A test written by a
developer in UTC-5 that uses `Date.today` will produce different
results when the CI server runs in UTC. Use `Time.zone.parse` with
explicit timezone-aware timestamps, not `Time.now` or `Date.today`,
in any test that involves dates.

Distributed teams make this worse. When the engineering team spans
multiple timezones, the same test suite produces different results
depending on *when* and *where* it runs. An organization with
engineers in both Eastern and Pacific time — or Eastern and IST —
has a window every evening where the CI server's clock crosses a
boundary that the tests are sensitive to. At one organization,
committing to master past a certain hour Eastern time was known to
violate a dozen or so tests that would resolve themselves if the
pipeline was re-run the next morning. The team had internalized this:
"don't push after 9 PM" was tribal knowledge, passed from engineer
to engineer, never documented, never fixed. The tests were not wrong
— the date logic they covered was genuinely broken at the day
boundary. But the failure was infrequent enough that it never rose
above the noise, and the workaround (wait until morning) was cheap
enough that it displaced the fix indefinitely.

This is the heisentest at its most corrosive: a real bug, surfaced
by a real test, dismissed as flakiness because the failure is
intermittent and the workaround is easy. The test did its job — it
produced a signal. The team chose not to act on it. The bug remained
in production, not because it was unknown, but because the signal
was not trusted.

## Ceremony over pragmatism

Testing is the one area where this framework advocates for ceremony
over pragmatism. In every other section, the advice is to avoid
unnecessary abstraction, skip the pattern when the problem it solves
is not present, prefer the simpler approach until complexity
demands otherwise. Testing is the exception.

Tests need to exist. They need to be maintained. They need to
produce a signal that the team trusts. This is ceremony — it costs
time, it slows down the initial delivery of a feature, it requires
discipline to maintain when the code it covers is changing rapidly.
The ceremony is worth it because the alternative is worse.

The alternative is manual verification. It works at small scale — a
single developer, a simple application, a feature that can be
tested by clicking through the UI. It does not work at team scale,
where multiple developers modify the same code, where features
interact in ways that no single developer can trace mentally, where
a change in one module affects behavior in another module that the
author has never seen.

The test suite is as close to a certainty that a change will not
break something as an engineering team will ever get. It is not
certainty — tests can be wrong, incomplete, or testing the wrong
thing. But it is the best available approximation, and no amount of
code review, manual QA, or developer confidence substitutes for an
automated, repeatable, deterministic check that the system's
behavioral contracts still hold.

Write the tests. Maintain them. Trust the signal. It is the one
ceremony that consistently pays for itself.

## A note on coverage thresholds

Coverage tools are great. Keep the badge in the README. Measure what
is covered and what is not. Use the report to identify untested code
paths, dead branches, and modules that have never been exercised by
the test suite. Coverage data is genuinely useful as a *diagnostic
tool* — it tells you where the gaps are.

Coverage data is considerably less useful as a *gate*.

A coverage threshold — "the build fails if coverage drops below
90%" — sounds like a quality guarantee. In practice, it is a
guarantee that a developer shipping a hotfix at 4pm on a Friday will
discover that the codebase was already at 90.2% and their new file
(which they did not have time to test, because it is a hotfix)
dropped coverage to 89.9%. The build fails. The hotfix is blocked.
The developer adds a tautological test to bring the number back
above the threshold, the build passes, and the codebase now has a
test that provides no signal and exists solely to satisfy a metric.

The problem is not the threshold itself. It is the incentive
structure it creates. A threshold penalizes *adding untested code*
but does not reward *adding useful tests*. It counts lines
exercised, not contracts enforced. A test that calls a function
without asserting anything meaningful raises the coverage number.
A test that verifies a critical boundary condition but only exercises
one branch does not raise it enough. The metric optimizes for
breadth of execution, not depth of verification.

Coverage is a useful dashboard. It is a poor gate. Track it, review
it, use it to guide where to invest testing effort — but do not let
it block deployments, because the workarounds it produces are worse
than the gaps it was meant to close.

## Questions to ask

1. For each test in the suite: what contract does this test enforce?
   If the answer is "it verifies that Ruby assignment works" or "it
   checks that the stub returns what I told it to return," the test
   is not providing signal.
2. When a test fails, does the failure message tell the developer
   what contract was broken? If the developer must read the test
   source to understand the failure, the test is not communicating
   its intent.
3. How many tests in the suite are expected failures that the team
   ignores? Each one is erosion of the signal. A red test that
   everyone knows is red is worse than no test — it trains the team
   to tolerate red.
4. Are integration tests testing the contract between components, or
   are they testing the implementation of components through the
   integration? The former is valuable; the latter is a unit test
   with extra infrastructure.
5. How long does the test suite take to run? A suite that takes
   twenty minutes will not be run before every commit. A suite that
   takes two minutes will. Speed is a feature of the test suite, not
   a luxury.
6. When a new feature ships, does it include tests? If not, why not —
   and is "we'll add them later" a commitment or a fiction?
