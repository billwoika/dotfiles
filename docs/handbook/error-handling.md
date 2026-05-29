# Error Handling

## The hierarchy of signals

Software systems produce signals constantly. Log entries, metrics,
health checks, user feedback, performance traces — all of them carry
information about the system's behavior. Errors and exceptions sit
at the top of this hierarchy. They are the loudest signal, the most
urgent, and the most likely to indicate that something has gone wrong
in a way that matters. Every other signal can wait. Errors cannot.

The discipline of error handling is not about writing `try/catch`
blocks. It is about designing systems that surface problems quickly,
present them appropriately to the audience that needs to act, and
maintain the signal-to-noise ratio that makes the surfacing useful
over time. Most codebases treat error handling as an afterthought —
something bolted on after the happy path works. The result is systems
that swallow errors silently, present stack traces to users, or
generate so much noise that the real failures are invisible.

## Catch quickly, present appropriately

The first principle is speed: errors should be caught as close to
their source as possible. A failed database query should not
propagate through three layers of abstraction before something
notices. A malformed API response should not be parsed, transformed,
and rendered before the system discovers it was garbage. The sooner
the error is caught, the more context is available for diagnosis,
and the fewer downstream systems are contaminated by bad state.

The second principle is audience: the response to an error depends
on who needs to know about it.

**The user** needs to know whether they can continue. If the error
is blocking — the payment failed, the form submission was rejected,
the resource does not exist — tell them clearly, in language they
understand, with a path forward. "Something went wrong" is not a
path forward. "Your payment could not be processed. Please verify
your card details or contact support at support@zftadvancements.com"
is. If the error is not blocking — a recommendation engine timed
out, a non-critical sidebar failed to load, analytics failed to
record — the user should not see it at all. Absorb it, fall back to
a reasonable default, and notify the engineering team internally.

**The engineering team** needs to know what happened, why, and how
to find it again. This is the two-audience pattern the
[Logging](logging.md) page describes: the user gets a reference ID
and a human sentence. The logs get the stack trace, the request
context, the input that triggered the failure, and the reference ID
that ties the two together. The user should never see a stack trace.
The engineer should never have to reproduce a user's steps to find
one.

```ruby
class PaymentService
  def process(payment)
    result = gateway.charge(payment)
    unless result.success?
      reference = ErrorTracker.capture(
        event: Events::PAYMENT_FAILED,
        context: { payment_id: payment.id, gateway_response: result.code }
      )
      raise PaymentError.new(
        user_message: "Your payment could not be processed. Reference: #{reference}",
        internal_message: "Gateway returned #{result.code} for payment #{payment.id}"
      )
    end
    result
  end
end
```

```python
class PaymentService:
    def process(self, payment: Payment) -> ChargeResult:
        result = self.gateway.charge(payment)
        if not result.success:
            reference = error_tracker.capture(
                event=Event.PAYMENT_FAILED,
                context={"payment_id": payment.id, "gateway_response": result.code},
            )
            raise PaymentError(
                user_message=f"Your payment could not be processed. Reference: {reference}",
                internal_message=f"Gateway returned {result.code} for payment {payment.id}",
            )
        return result
```

The pattern is simple: every error that reaches a user carries a
reference ID. Every error that reaches the logs carries the full
diagnostic context. The reference ID is the bridge. A user who
contacts support with "Reference: ERR-a84f2c" gives the support
engineer a direct lookup into the log stream. No reproduction
needed, no "can you describe what you were doing," no guesswork.

## Blocking vs non-blocking

Not every error deserves the user's attention. The distinction
between blocking and non-blocking errors is one of the most
consequential design decisions in a system, and most teams make it
implicitly rather than deliberately.

**Blocking errors** prevent the user from completing their intended
action. The payment cannot be processed. The form data is invalid.
The requested resource does not exist. The user's session has
expired. These require a visible response: a clear message
explaining what happened, what the user can do about it, and — when
the problem is on the system's side rather than the user's — an
explicit invitation to contact support. The user cannot proceed
without intervention, so the system must tell them that honestly.

```typescript
// Blocking: the user cannot continue without resolution
function submitEnrollment(data: EnrollmentData): EnrollmentResult {
  const validation = validate(data);
  if (!validation.success) {
    return {
      success: false,
      message: "Some required fields need attention.",
      fields: validation.errors,
    };
  }

  try {
    return enrollmentService.submit(data);
  } catch (error) {
    const reference = errorTracker.capture(Event.EnrollmentFailed, {
      data,
      error,
    });
    return {
      success: false,
      message: `We couldn't complete your enrollment. Please contact support with reference ${reference}.`,
    };
  }
}
```

**Non-blocking errors** affect a secondary function that the user
did not directly request. The recommendation sidebar failed to load.
The analytics event failed to record. A background sync timed out.
These should be invisible to the user and visible to the engineering
team. The system absorbs the failure, falls back to a reasonable
default (an empty sidebar, a skipped analytics event, a retry
scheduled for later), and emits an internal alert.

```python
def load_dashboard(user: User) -> Dashboard:
    dashboard = Dashboard(user=user)

    try:
        dashboard.recommendations = recommendation_service.fetch(user)
    except ServiceError as e:
        error_tracker.capture(
            event=Event.RECOMMENDATION_FETCH_FAILED,
            context={"user_id": user.id, "error": str(e)},
            severity=Severity.WARNING,
        )
        dashboard.recommendations = []

    return dashboard
```

### Deferred-critical errors

The blocking/non-blocking distinction assumes the severity of an
error is knowable at the moment it occurs. For synchronous
request-response flows, this is usually true: the payment failed,
the user cannot proceed, the error is blocking. But many systems
include asynchronous workflows where the user's action succeeds
from their perspective — the order is placed, the confirmation
email arrives — and a downstream process fails silently in a
background job minutes or hours later.

Consider a fulfillment workflow. The user places an order. The
order service validates payment, confirms the order, and enqueues a
job to reserve inventory with the fulfillment vendor. The user sees
"Order confirmed" and moves on. The background job fires, calls the
vendor's API, and receives an error: the item is out of stock.

This error is not blocking from the user's perspective — they have
already left. It is not a noisy signal to be triaged at leisure. It
is critical. The business has confirmed an order it cannot fulfill.
Every minute the error sits unaddressed is a minute closer to a
customer expecting a delivery that will not arrive.

The mistake is classifying this as a non-blocking error because the
user session is no longer active. The user's presence is not the
measure of severity — the business consequence is. An out-of-stock
fulfillment failure is as critical as a payment failure, even though
it surfaces asynchronously and there is no user staring at a screen
waiting for a response.

```python
class FulfillmentJob:
    def perform(self, order_id: str) -> None:
        order = order_repository.find(order_id)
        try:
            result = fulfillment_vendor.reserve(order)
        except VendorStockError as e:
            error_tracker.capture(
                event=Event.FULFILLMENT_STOCK_FAILURE,
                context={
                    "order_id": order.id,
                    "customer_id": order.customer_id,
                    "vendor_sku": e.sku,
                },
                severity=Severity.CRITICAL,
            )
            order.mark_fulfillment_failed(reason="vendor_out_of_stock")
            notification_service.alert_operations(order)
            return

        order.mark_reserved(vendor_reference=result.reference)
```

The disciplines that prevent deferred-critical errors from being
treated as noise:

**Classify by business consequence, not by user presence.** An
error in a background job that affects a confirmed order, a
financial transaction, or a contractual obligation is critical
regardless of whether a user is waiting for the response. The
severity classification belongs to the business impact, not to the
technical context in which the error surfaces.

**Escalate to a human, not just a dashboard.** A critical
asynchronous error cannot wait for someone to check the error
dashboard during business hours. It requires active notification —
a page, an alert in an operations channel, a ticket auto-created
in the queue. The error tracking system's dashboard is where
engineers investigate. The notification is what tells them to
investigate now.

**Make the state visible.** The order that failed fulfillment must
be in a state that the operations team can query, filter, and act
on. A log entry is not sufficient. The order itself must carry the
failure — a status, a reason, a timestamp — so that the team can
answer "how many orders are currently in a failed fulfillment
state" without searching logs.

The broader point: the blocking/non-blocking model is useful for
synchronous flows but incomplete for systems with asynchronous
processing. Any workflow where the user receives a success response
before all downstream effects have completed is a workflow that can
produce deferred-critical errors. The system design must account for
this explicitly — not by treating every async error as critical
(that produces the alert fatigue the next section describes), but by
classifying each async failure path by what happens to the business
if it goes unaddressed.

## Fail fast vs graceful degradation

These are not competing philosophies. They are strategies for
different contexts, and the discipline is knowing which context
applies.

**Fail fast** is correct when the error indicates corrupted state,
invalid assumptions, or a condition that will produce worse failures
downstream if the system continues. A database migration that
encounters an unexpected schema state should abort, not attempt to
continue. A payment processor that receives an unrecognized response
code should halt and alert, not guess what the code means and
proceed. A configuration loader that cannot find a required value
should crash at startup, not silently use a default that will
produce incorrect behavior for hours before anyone notices.

The fail-fast instinct is especially important during initialization.
A system that validates its configuration, its database connections,
its external service credentials, and its required environment
variables at startup — and refuses to start if any are missing or
invalid — is a system that fails loudly and immediately. A system
that defers these checks until the first request hits the invalid
path is a system that starts successfully, runs for hours, and then
fails in production under load at 2am when the on-call engineer
discovers that an environment variable was never set.

```python
@dataclass(frozen=True)
class AppConfig:
    database_url: str
    redis_url: str
    payment_gateway_key: str
    encryption_key: str

    def __post_init__(self) -> None:
        missing = [
            name
            for name in ["database_url", "redis_url", "payment_gateway_key", "encryption_key"]
            if not getattr(self, name)
        ]
        if missing:
            raise StartupError(
                f"Missing required configuration: {', '.join(missing)}. "
                f"The application cannot start without these values."
            )
```

The fail-fast instinct is most important — and most often violated —
when data integrity is at stake. An error that prevents a write is
recoverable. An error that corrupts a write may not be. A process
that encounters an unexpected state mid-transaction and continues
anyway — writing partial data, overwriting good data with bad,
committing a half-finished mutation — has converted a recoverable
error into a data-recovery problem. The error was fixable. The
corrupted data may not be.

This is where fail-fast stops being an engineering preference and
becomes a survival discipline: it is always better to throw an error
than to write bad data. A failed transaction can be retried. A
corrupted record may require manual intervention, customer
communication, or — in the worst case — may go undetected until its
effects propagate into reports, invoices, or downstream systems that
trusted the data to be correct.

```ruby
class InventoryAdjustment
  def apply(warehouse:, sku:, quantity:)
    ActiveRecord::Base.transaction do
      item = InventoryItem.lock.find_by!(warehouse:, sku:)

      new_quantity = item.quantity + quantity
      if new_quantity.negative?
        raise InventoryError, "Adjustment would produce negative stock " \
          "(current: #{item.quantity}, adjustment: #{quantity})"
      end

      item.update!(quantity: new_quantity)

      AuditLog.create!(
        event: Events::INVENTORY_ADJUSTED,
        item_id: item.id,
        previous_quantity: item.quantity - quantity,
        new_quantity: new_quantity,
        adjustment: quantity,
        adjusted_by: Current.user&.id
      )
    end
  end
end
```

The transaction is the error boundary. If the audit log fails to
write, the inventory adjustment rolls back — no silent partial
mutation. If the quantity would go negative, the process raises
rather than clamping to zero and writing a lie. The audit log
records the before-and-after state so that if something *does* go
wrong later, the recovery path has the data it needs to reconstruct
what happened.

That last point deserves emphasis: **the error handling enclosure
should record enough activity that recovery is possible.** When a
process fails, the question the team asks is "what state were we in,
what were we trying to do, and what actually happened?" If the
error handler captures only "an error occurred," the team is
reconstructing state from inference and log timestamps. If the error
handler captures the inputs, the intended operation, and the state
at the point of failure, the team has everything they need to
remediate — whether that means retrying the operation, reverting to
a known-good state, or manually correcting the affected records.

```python
class LedgerService:
    def post_entry(self, entry: LedgerEntry) -> None:
        snapshot = self._capture_pre_state(entry.account_id)
        try:
            with self.db.transaction():
                self._validate_balance(entry)
                self._write_entry(entry)
                self._update_running_balance(entry)
        except Exception as e:
            error_tracker.capture(
                event=Event.LEDGER_POST_FAILED,
                context={
                    "entry": entry.to_dict(),
                    "pre_state": snapshot,
                    "error": str(e),
                },
                severity=Severity.CRITICAL,
            )
            raise
```

The `snapshot` captured before the transaction attempt is the
recovery artifact. If the transaction fails, the error tracker has
the entry that was attempted *and* the account state before the
attempt. Recovery does not require guesswork.

**Graceful degradation** is correct when the error affects a
non-critical subsystem and the primary function can continue without
it. The recommendation engine is down, but the enrollment flow
works. The analytics pipeline is backed up, but the user-facing API
is unaffected. A third-party integration has failed, but the
first-party fallback can serve the same data at lower quality.

The key distinction: fail fast when the error compromises the
system's primary function or data integrity. Degrade gracefully when
the error affects a secondary function and the primary function
remains sound. A payment system should fail fast on a charge
failure. It should degrade gracefully on a loyalty-point
calculation failure.

## The exception vs return-value debate

Different languages make different choices about how errors are
represented, and those choices shape how engineers think about error
handling.

**Exception-based languages** (Ruby, Python, Java, C#) use
exceptions as the primary error-signaling mechanism. The happy path
is the default. Errors interrupt it by unwinding the call stack
until something catches them. This model is expressive — the happy
path reads cleanly without error-checking clutter — but it has a
cost: exceptions are invisible in the function signature. A caller
cannot know, without reading the implementation, what exceptions a
function might raise. The call stack between the throw and the catch
can be arbitrarily deep, and any layer in between can be affected by
the unwinding without knowing it.

```ruby
# The caller has no idea this can raise three different exceptions
def process_enrollment(student, course)
  validate_eligibility!(student, course)    # raises IneligibleError
  reserve_seat!(course)                     # raises CapacityError
  charge_tuition!(student, course.tuition)  # raises PaymentError
  Enrollment.create!(student:, course:)
end
```

**Return-value languages** (Go, Rust) make errors explicit in the
return type. Every function that can fail says so in its signature.
The caller must handle the error — the compiler enforces it. This
model is verbose — every call site has error-handling boilerplate —
but it makes the error paths visible and forces the caller to make a
conscious decision about each one.

```go
func processEnrollment(student Student, course Course) (*Enrollment, error) {
    if err := validateEligibility(student, course); err != nil {
        return nil, fmt.Errorf("eligibility check: %w", err)
    }
    if err := reserveSeat(course); err != nil {
        return nil, fmt.Errorf("seat reservation: %w", err)
    }
    if err := chargeTuition(student, course.Tuition); err != nil {
        return nil, fmt.Errorf("tuition charge: %w", err)
    }
    return createEnrollment(student, course)
}
```

Neither model is superior. The exception model trades visibility for
expressiveness. The return-value model trades expressiveness for
visibility. The framework's position is pragmatic: use the model
your language provides, but understand its failure modes.

In exception-based languages, the failure mode is unhandled
exceptions — errors that propagate to the top of the stack and
produce a 500 response or an unhandled-exception crash. The
discipline is **enumerated exception types** (the pattern the
[Logging](logging.md) page describes) and **explicit catch
boundaries** — specific points in the call stack where errors are
caught, classified, and either handled or re-raised with context.

In return-value languages, the failure mode is ignored errors — the
`if err != nil { return err }` pattern that propagates errors
without adding context, or worse, the `_ = someFn()` pattern that
discards them entirely. The discipline is **error wrapping** — every
layer that propagates an error adds context about what it was doing
when the error occurred.

## Error boundaries

An error boundary is a point in the call stack where errors are
caught, classified, and transformed into an appropriate response.
Not every layer should catch errors. Not every layer should
propagate them. The design question is: where in the architecture
should errors be handled?

The answer depends on the layer (see
[The Layers](layers.md)):

**Infrastructure layer.** Errors here are environmental: network
timeouts, disk failures, connection pool exhaustion. These should be
caught at the boundary between infrastructure and the layer above
it, retried where idempotent, and escalated with context when
retries are exhausted. The application layer should not know that a
database query timed out — it should know that the data it requested
is unavailable.

**Data layer.** Errors here are constraint violations, missing
records, schema mismatches. These should be caught and translated
into domain-meaningful errors. `RecordNotFound` is better than
`PG::NoDataFound`. `DuplicateEnrollment` is better than
`ActiveRecord::RecordNotUnique`. The translation adds meaning and
decouples the caller from the storage implementation.

**Application layer.** This is where business rule violations
surface: the student is ineligible, the course is full, the payment
was declined. These are not infrastructure errors — they are
expected outcomes that the system must handle as part of its normal
operation. The application layer classifies them and decides the
response: retry, fall back, or escalate to the presentation layer.

**Presentation layer.** This is the outermost boundary — the last
chance to catch anything that escaped the layers below. The
presentation layer's job is to ensure that no raw exception, no
stack trace, and no internal detail reaches the user. Everything
that arrives here is transformed into a user-appropriate response:
an HTTP status code, an error message, a redirect, a reference ID.

```ruby
# Presentation layer: the outermost error boundary
class EnrollmentsController < ApplicationController
  def create
    enrollment = EnrollmentService.new.process(
      student: current_user,
      course: Course.find(params[:course_id])
    )
    redirect_to enrollment, notice: "Enrollment confirmed."
  rescue IneligibleError => e
    flash.now[:alert] = e.user_message
    render :new, status: :unprocessable_entity
  rescue CapacityError
    flash.now[:alert] = "This course is currently full. You have been added to the waitlist."
    render :new, status: :unprocessable_entity
  rescue PaymentError => e
    flash.now[:alert] = e.user_message
    render :new, status: :payment_required
  rescue StandardError => e
    reference = ErrorTracker.capture(event: Events::ENROLLMENT_UNEXPECTED, error: e)
    flash.now[:alert] = "Something went wrong. Please contact support with reference #{reference}."
    render :new, status: :internal_server_error
  end
end
```

The `StandardError` catch at the bottom is the safety net — the
[Logging](logging.md) page's "catch-all as last resort." It should
exist, it should capture full context, and it should almost never
fire. If it fires regularly, the error boundaries in the layers
below are not doing their job.

## Alert fatigue

The most dangerous failure in error handling is not a crash. It is
a signal that nobody reads.

Every error tracking system follows the same lifecycle. In the
beginning, the team configures alerts for every exception. The
dashboard is clean. Every error is investigated. The system works
as intended. Over time, known issues accumulate. A third-party API
returns intermittent 503s. A background job occasionally times out
under load. A deprecated endpoint logs warnings for clients that
have not migrated. Each of these is acknowledged, understood, and
left unresolved — either because the fix is not worth the effort or
because the cause is external. The alerts continue. The dashboard
fills with known noise. The team stops looking.

This is not a hypothetical. It is the normal trajectory of every
error tracking system that does not have active noise management as
a discipline.

The cost is not just wasted attention. It is missed signals.

A third-party vendor — a reluctant partner from engineering's
perspective — provided a service that the system consumed as a
fallback. When their service failed, the system placed a key in the
cache to suppress that route for 24 hours and fell back to the
first-party implementation. The error was logged. It was one error
among many — a single line in a dashboard full of known, tolerated
noise. Nobody investigated because there was nothing to distinguish
it from the dozens of other known non-issues that fired daily.

This pattern continued for months. The vendor's service failed every
day — exactly once, before the cache key suppressed further
attempts. The daily error was invisible not because it was hidden
but because it was indistinguishable from the noise floor. When the
pattern was finally discovered — through log analysis, not through
the alert system — the root cause was straightforward: the vendor
had failed to renew their SSL certificates. Their service had been
broken for months. The cache-based fallback had masked a complete
service failure, and the alert system had masked the cache-based
fallback, and the result was a third-party integration that existed
on paper and in contracts but had not functioned in over a quarter.

The lesson is not "investigate every alert." That is not sustainable.
The lesson is that alert fatigue has compounding costs, and those
costs are invisible until the failure they mask becomes visible
through some other channel. The disciplines that prevent it:

**Resolve or silence.** Every known non-issue in the error dashboard
must be either fixed or explicitly silenced with a documented
rationale. "We know about this and it's fine" is acceptable — but
only if it is recorded, reviewed periodically, and carries a
suppression rule so it does not contribute to noise. An error that
is known, tolerated, and still firing is an error that makes the
next unknown error harder to see.

**Budget your noise floor.** Set a threshold for the number of
tolerated errors per day, per service. When the count exceeds the
budget, something has changed — either a new error is firing or a
known error has increased in frequency. Both are worth
investigating. The budget forces the team to treat the noise floor
as a resource that must be managed, not an inevitability to be
endured.

**Review suppression rules.** A suppression rule that was appropriate
six months ago may be masking a problem that has changed character.
The vendor whose SSL certificates lapsed was suppressed because
"intermittent 503s from this vendor are expected." The suppression
was correct when it was written. It was catastrophically wrong six
months later when the intermittent 503s became a permanent failure.
Suppression rules need expiration dates or periodic review — the
same discipline the
[Technical Debt](technical-debt.md) page describes for deliberate
debt.

**Measure the cost of your error tracking.** Alert fatigue is not
just an attention problem — it is a resource problem. Error tracking
and logging platforms charge by volume. An organization that
generates thousands of known, tolerated, uninvestigated errors per
day is paying real money to store signals that nobody reads. The
cost is easy to calculate and hard to justify. "We spend $X per
month on error tracking, and 90% of the volume is known noise that
has not been investigated in six months" is a business case for
noise reduction that even a non-technical stakeholder can evaluate.

## The swallowed error

The worst error-handling pattern is the one that looks like error
handling but is not:

```ruby
# This is not error handling. This is error hiding.
def fetch_recommendations(user)
  recommendation_service.fetch(user)
rescue => e
  Rails.logger.error(e.message)
  []
end
```

```python
# This is not error handling. This is error hiding.
def fetch_recommendations(user: User) -> list[Recommendation]:
    try:
        return recommendation_service.fetch(user)
    except Exception as e:
        logger.error(e)
        return []
```

The pattern looks responsible — it catches the error, it logs it, it
returns a fallback. But it catches *everything*, logs *nothing
useful* (no context, no event type, no severity classification), and
returns a value that is indistinguishable from "there are no
recommendations." The caller cannot tell whether recommendations
were empty or whether the service is down. The log entry has no
structure, no reference ID, and no connection to the user or request
that triggered it. The fallback is silent — the user sees an empty
sidebar and assumes there is nothing to see.

Compare:

```ruby
def fetch_recommendations(user)
  recommendation_service.fetch(user)
rescue ServiceUnavailableError => e
  ErrorTracker.capture(
    event: Events::RECOMMENDATION_FETCH_FAILED,
    context: { user_id: user.id, service: "recommendation", error: e.message },
    severity: :warning
  )
  []
rescue => e
  ErrorTracker.capture(
    event: Events::RECOMMENDATION_UNEXPECTED,
    context: { user_id: user.id, error: e.class.name, message: e.message },
    severity: :error
  )
  []
end
```

The fallback is the same — an empty array. The difference is that
the first version hides errors and the second version handles them.
The second version distinguishes expected failures (service
unavailable) from unexpected ones (anything else). It captures
structured context. It classifies severity. It uses enumerated
events. The engineering team can filter the dashboard for
`RECOMMENDATION_UNEXPECTED` errors and know immediately that
something has changed — because that event should rarely fire, and
when it does, it means the error is not the known service-
unavailability pattern.

## When this goes wrong

Error handling is a design decision with the same trade-offs as any
other:

- **Over-catching** produces silent failures. A `rescue => e` or
  `except Exception` at every call site means errors are absorbed
  before they can propagate to the boundary that should handle them.
  The system appears healthy while its subsystems fail silently.

- **Under-catching** produces user-facing stack traces. An
  application with no error boundaries in the presentation layer
  will eventually show a user a raw exception — the default behavior
  of most web frameworks when no handler is configured. This is not
  just a poor user experience; it is an information disclosure
  vulnerability.

- **Catching at the wrong layer** produces errors that cannot be
  handled meaningfully. The data layer catching a business-rule
  violation cannot decide whether to show the user a form error or
  redirect to a different page — that is the presentation layer's
  job. The infrastructure layer catching a payment failure cannot
  decide whether to retry or refund — that is the application
  layer's job.

- **Treating all errors as equal** produces alert fatigue. A warning
  and a critical error require different responses. A known
  intermittent failure and an unknown new failure require different
  attention. Without severity classification and enumerated event
  types, the error dashboard becomes a wall of undifferentiated noise
  — and the SSL certificate failure hides in plain sight for months.

## Questions to ask

1. For every `try/catch` or `rescue` block in the codebase: does the
   catch clause add context, or does it just log and swallow? If the
   latter, it is error hiding, not error handling.
2. Can a user ever see a stack trace, a raw exception class name, or
   an internal error message? If so, the presentation layer's error
   boundary is incomplete.
3. What is the noise floor of the error dashboard? How many errors
   per day are known, tolerated, and uninvestigated? That number is
   the measure of how many unknown errors can hide undetected.
4. When was the last time a suppression rule was reviewed? If the
   answer is "never," the suppression rules are a liability, not a
   tool.
5. Does the system validate its configuration at startup, or does it
   discover missing values at runtime? Every runtime discovery is a
   potential 2am incident that could have been a failed deployment.
6. For every graceful degradation path: does the fallback produce a
   value that is distinguishable from the normal case? If an empty
   array means both "no data" and "service down," the system cannot
   tell the difference — and neither can the team.
