# Logging

## The state of most application logs

Open the log output of a production application for the first time.
In many codebases, what you find is this:

```
Processing request...
user found
DEBUG: got here
[2026-05-22 14:33:07] something happened
Error: undefined
checking permissions
result: true
starting sync
sync done
```

None of these lines answer a question an operator would ask during an
incident. Which request? Which user? What happened? What was
undefined? Which permissions? True for what? Sync of what, triggered
by whom, taking how long?

These are `console.log` statements and `print` calls left behind by
developers during local debugging, promoted to production without
revision. Each one made sense at the time — the developer was tracing
a specific code path, confirming a value, verifying that execution
reached a certain point. In the developer's terminal, with the
context of the code open in their editor, the output was useful.

In a production log stream aggregating output from forty containers,
interleaved with output from twelve services, queried by an on-call
engineer at 3am who did not write the code — these lines are noise.
They consume storage, pollute search results, and communicate nothing
actionable.

This is not a minor style concern. It reflects how seriously a team
takes the operational surface of their software. Ad hoc log
statements are the equivalent of leaving `TODO: fix this later`
comments scattered through production code — except that TODOs are
only visible to developers reading the source, while log output is
visible to everyone who operates the system. If the logs look like
scratch notes from a debugging session, that is what operators will
conclude about the engineering team's attention to detail.

## Structured logging

The alternative is structured logging: every log entry is a
machine-parseable record with named fields, consistent formatting,
and enough context to answer operational questions without access to
the source code.

The same events, structured:

```json
{"timestamp": "2026-05-22T14:33:07.042Z", "level": "info", "event": "request.received", "method": "POST", "path": "/api/v1/enrollments", "request_id": "a1b2c3d4", "tenant_id": "zftadvancements"}
{"timestamp": "2026-05-22T14:33:07.048Z", "level": "info", "event": "customer.found", "customer_id": 4821, "request_id": "a1b2c3d4"}
{"timestamp": "2026-05-22T14:33:07.051Z", "level": "info", "event": "authorization.checked", "customer_id": 4821, "permission": "enrollment.create", "result": "granted", "request_id": "a1b2c3d4"}
{"timestamp": "2026-05-22T14:33:07.089Z", "level": "info", "event": "enrollment.completed", "customer_id": 4821, "duration_ms": 47, "request_id": "a1b2c3d4"}
```

Every line is a self-contained record. Every record has a timestamp,
a severity level, and an event name. Every record carries the
`request_id` that correlates it with every other record from the same
request. The fields are named, typed, and queryable.

An operator investigating a failed enrollment can query:

```
event:enrollment.* AND customer_id:4821 AND timestamp:[2026-05-22T14:00:00 TO 2026-05-22T15:00:00]
```

This query returns exactly the records relevant to the investigation,
across every service that participated in the request, in
chronological order. The `request_id` correlates the enrollment event
with the authorization check, the customer lookup, and the original
HTTP request — even if they occurred in different services.

None of this is possible when the logs are unstructured strings. You
cannot query `console.log("user found")` for a specific user. You
cannot correlate `print("sync done")` with the request that triggered
it. You cannot aggregate `puts "something happened"` into a metric.
The information was never recorded — only a human-readable fragment
was emitted, and the context that would make it useful was in the
developer's head at the time they wrote the statement.

### What structured logging requires

The discipline is straightforward but must be adopted consistently:

**Every log entry is JSON** (or another structured format — logfmt is
a reasonable alternative). Never a bare string. Never a string with
interpolated values that must be parsed with regex to extract fields.

```python
# Wrong: unstructured, unparseable
logger.info(f"Enrolled customer {customer_id} in {duration}ms")

# Right: structured, queryable
logger.info("enrollment.completed", extra={
    "customer_id": customer_id,
    "duration_ms": duration,
    "tenant_id": tenant_id,
})
```

```ruby
# Wrong
Rails.logger.info "Processing payment for order #{order.id}"

# Right
Rails.logger.info({
  event: "payment.processing",
  order_id: order.id,
  amount_cents: order.total_cents,
  method: payment_method,
  request_id: Current.request_id,
}.to_json)
```

```typescript
// Wrong
console.log(`User ${userId} logged in`)

// Right
logger.info({
  event: "user.authenticated",
  userId,
  method: "oauth",
  provider: "google",
  requestId: ctx.requestId,
})
```

**Every entry has a severity level.** `debug`, `info`, `warn`,
`error` — used consistently and meaningfully. `info` is for events
that operators should see during normal operation. `warn` is for
conditions that are not failures but may indicate degradation. `error`
is for failures that require attention. `debug` is for detail that is
useful during development and noisy in production. The level is a
filter, and if everything is `info`, the filter is useless.

**Every entry carries correlation context.** A `request_id` at
minimum. In distributed systems, a `trace_id` and `span_id` that
follow the request across service boundaries. Without correlation
context, a log stream from multiple concurrent requests is an
unsortable pile of interleaved events.

### Generating trace IDs

Correlation context only works if the identifiers are generated
consistently and carry enough information to be useful in a query.
Two approaches serve different needs.

**UUID generation** is the simplest and most common. A UUID v4 is
globally unique, requires no coordination between services, and can
be generated at the edge (the API gateway, the load balancer, the
first service to receive the request) and propagated through headers:

```python
import uuid

request_id = str(uuid.uuid4())
# "a3f1b8c2-7d4e-4a91-b6f0-9c2e8d1a5f73"
```

UUIDs are opaque — they carry no semantic content. This is a feature
when the only requirement is uniqueness and correlation. It is a
limitation when the identifier itself should communicate context.

**Namespaced deterministic IDs** encode context into the identifier.
A deterministic hash derived from known inputs — service name,
timestamp, entity ID — produces an ID that is both unique and
informative:

```python
import hashlib
import time

def trace_id(namespace: str, entity_id: str, timestamp: float | None = None) -> str:
    ts = timestamp or time.time()
    raw = f"{namespace}:{entity_id}:{ts}"
    return f"{namespace}-{hashlib.sha256(raw.encode()).hexdigest()[:12]}"

trace_id("enrollment", "customer-4821")
# "enrollment-a7c3f1b8d2e4"

trace_id("payment", "order-9917")
# "payment-3e8b1c7f9a02"
```

The namespace prefix makes the ID self-documenting in a log stream.
An operator scanning raw logs can see at a glance that
`enrollment-a7c3f1b8d2e4` is an enrollment flow and
`payment-3e8b1c7f9a02` is a payment flow — without querying for the
ID to find its first event. The deterministic hash means the same
inputs produce the same ID, which is useful for idempotency checks
and deduplication.

**Hierarchical correlation** extends this pattern across nested
operations. A request enters the system with a `request_id`. That
request triggers an enrollment, which gets its own `trace_id`. The
enrollment triggers a payment, which gets its own. Each child
carries its parent's ID:

```json
{"event": "request.received", "request_id": "req-a3f1b8c2", "path": "/api/v1/enrollments"}
{"event": "enrollment.started", "request_id": "req-a3f1b8c2", "trace_id": "enrollment-a7c3f1b8d2e4", "customer_id": 4821}
{"event": "payment.initiated", "request_id": "req-a3f1b8c2", "trace_id": "payment-3e8b1c7f9a02", "parent_trace_id": "enrollment-a7c3f1b8d2e4", "order_id": 9917}
{"event": "payment.completed", "request_id": "req-a3f1b8c2", "trace_id": "payment-3e8b1c7f9a02", "duration_ms": 230}
{"event": "enrollment.completed", "request_id": "req-a3f1b8c2", "trace_id": "enrollment-a7c3f1b8d2e4", "duration_ms": 412}
```

The `request_id` correlates everything from the same HTTP request.
The `trace_id` correlates everything from a specific logical
operation within that request. The `parent_trace_id` establishes
causality. An operator can query at any level: all events for the
request, all events for the enrollment, all events for the payment
— and follow the chain from any starting point.

This is the structured logging equivalent of a distributed trace.
OpenTelemetry formalizes this pattern with `trace_id` and `span_id`
fields, but the principle is the same whether the IDs are generated
by an OTel SDK or by application code: every event carries enough
context to be correlated with its siblings, its parent, and its
children.

**Event names follow a convention.** `resource.action` is common:
`customer.created`, `payment.failed`, `enrollment.completed`. The
convention makes events discoverable — an operator who has never seen
the codebase can guess that enrollment events are named
`enrollment.*` and query for them.

### The Rails multiline problem

Some frameworks emit logs that are structured in concept but
unstructured in practice. Rails' default request logging is the
canonical example:

```
Started POST "/api/v1/enrollments" for 10.0.0.1 at 2026-05-22 14:33:07 -0400
Processing by Api::V1::EnrollmentsController#create as JSON
  Parameters: {"customer_id"=>"4821"}
  Customer Load (0.4ms)  SELECT "customers".* FROM "customers" WHERE "customers"."id" = $1 LIMIT $2  [["id", 4821], ["LIMIT", 1]]
  TRANSACTION (0.1ms)  BEGIN
  Enrollment Create (0.3ms)  INSERT INTO "enrollments" ("customer_id", "created_at") VALUES ($1, $2) RETURNING "id"  [["customer_id", 4821], ["created_at", "2026-05-22 18:33:07.089"]]
  TRANSACTION (0.2ms)  COMMIT
Completed 201 Created in 47ms (Views: 0.1ms | ActiveRecord: 1.0ms | Allocations: 2847)
```

Seven lines for one request. Each line has different formatting. The
timing information is split across multiple lines. The SQL queries
are logged as raw strings with interpolated parameters. In a log
aggregator, these seven lines are seven independent records with no
guaranteed ordering and no shared identifier. Correlating them
requires matching on timestamp proximity and hoping that no other
request interleaved.

The difference between this and a single structured JSON line is the
difference between a clean query and hours of wasted time.
`lograge`, `semantic_logger`, or a custom log subscriber can replace
the default output with structured JSON — one line per request, all
fields named, all values queryable. This is one of the highest-value
changes a Rails application can make, and it requires no
architectural redesign — just a configuration change and a
commitment to structured output.

## Twelve-factor logging

The [Twelve-Factor App](https://12factor.net/logs) methodology takes
a clear position on logging: **an application should never concern
itself with routing or storage of its log stream.** The application
writes structured events to stdout. Everything else — collection,
routing, aggregation, storage, alerting — is the responsibility of
the deployment infrastructure.

This is a separation of concerns applied to observability. The
application knows *what* happened. The infrastructure knows *where
the logs should go*. Mixing these responsibilities produces
applications that open log files, manage rotation, configure network
transport to a log aggregator, handle connection failures to the
logging backend, and retry failed log deliveries — all of which is
infrastructure work embedded in application code.

```python
import structlog
import sys

structlog.configure(
    processors=[
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
)

logger = structlog.get_logger()
logger.info("enrollment.completed", customer_id=4821, duration_ms=47)
```

The application emits a JSON line to stdout. It does not know whether
stdout is connected to a terminal, a file, a container runtime's log
driver, a Fluentd sidecar, or `/dev/null`. It does not care. The
infrastructure — Kubernetes, Docker Compose, systemd, a PaaS — is
responsible for capturing stdout and routing it to the appropriate
sink: CloudWatch, Datadog, Elasticsearch, Loki, a local file during
development.

This separation keeps the application code clean. No log file paths
in configuration. No log rotation logic. No conditional formatting
(JSON in production, pretty-print in development — the infrastructure
handles this, not the application). No retry logic for failed log
delivery. The application's only logging responsibility is to emit
well-structured events to stdout.

## When stdout is not enough

The twelve-factor model covers logging — the record of what happened.
It does not cover the full observability picture. Modern distributed
systems require three pillars of observability: logs, metrics, and
traces. Logs record events. Metrics measure aggregates (request rate,
error rate, latency percentiles). Traces follow a single request
across service boundaries, recording the timing and outcome of each
hop.

Metrics and traces require instrumentation that goes beyond writing
to stdout. A distributed trace needs context propagation — a trace ID
and span ID that are passed in HTTP headers from service to service,
injected into every log entry, and reported to a tracing backend that
assembles the spans into a complete request timeline.

Platforms like New Relic, Datadog, Dynatrace, Honeycomb, and Grafana
Tempo provide this instrumentation, but they require more than an
initializer and captured stdout. They need enclosing blocks or
explicit invocations in the application code:

```python
from opentelemetry import trace

tracer = trace.get_tracer("enrollment-service")

def enroll_customer(customer_id, tenant_id):
    with tracer.start_as_current_span("enroll_customer") as span:
        span.set_attribute("customer.id", customer_id)
        span.set_attribute("tenant.id", tenant_id)

        customer = customer_repo.find(customer_id)

        with tracer.start_as_current_span("check_eligibility"):
            eligible = eligibility_service.check(customer)

        if not eligible:
            span.set_attribute("enrollment.result", "ineligible")
            return

        with tracer.start_as_current_span("create_enrollment"):
            enrollment = enrollment_repo.create(customer_id)

        span.set_attribute("enrollment.result", "success")
        span.set_attribute("enrollment.id", enrollment.id)
        return enrollment
```

This is code in the application — not just configuration, not just an
initializer. The tracing spans define the boundaries of logical
operations, carry domain-specific attributes, and produce the data
that a tracing backend needs to build a request waterfall. This level
of instrumentation cannot be achieved by capturing stdout alone.

The trade-off is worth it when it is needed. Distributed tracing
across a microservices architecture is the difference between "the
request was slow" and "the request was slow because the eligibility
check took 800ms because the database connection pool was saturated
in the eligibility service." That specificity is what lets an on-call
engineer resolve an incident in minutes rather than hours.

## Vendor lock-in and open protocols

The trade-off comes with a cost: instrumentation code that uses a
vendor-specific SDK couples the application to that vendor. Migrating
from New Relic to Datadog, or from Datadog to Grafana, means finding
and replacing every instrumentation call in the codebase — a project
that ranges from tedious to prohibitive depending on how deeply the
SDK is embedded.

**OpenTelemetry** (OTel) exists to eliminate this coupling. OTel is
an open, vendor-neutral standard for instrumentation — traces,
metrics, and logs. The application instruments with OTel's API. The
OTel SDK and Collector handle export to whatever backend is
configured: New Relic, Datadog, Jaeger, Prometheus, Grafana Tempo,
or any combination. Switching backends is a configuration change, not
a code change.

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)
```

The application code — the `tracer.start_as_current_span` calls, the
attribute setting, the context propagation — is identical regardless
of the backend. The exporter is a configuration detail. If the
organization migrates from one APM vendor to another, the
instrumentation code does not change. Only the exporter configuration
changes.

The recommendation is direct: **if you must mix telemetry and
tracing code into the application itself, keep it to open protocols
whenever possible.** OTel is the de facto standard. Vendor-specific
SDKs should be the exception — used only when the vendor provides
capability that OTel does not yet support, and isolated behind an
adapter so the vendor dependency does not spread through the
codebase.

!!! warning "On vendor SDKs in general"

    This applies beyond observability. Vendor SDKs — for payment
    providers, CRMs, messaging platforms, cloud services — are
    rarely maintained with the same rigor as the vendor's API
    itself. The API is the product; the SDK is a convenience wrapper
    that may lag behind API changes by months or years, accumulate
    unpatched dependencies, or silently drop support for your
    language version.

    Maintain your own API clients. A thin HTTP wrapper around a
    well-documented REST API is less code than you think, gives you
    full control over retry logic, timeout behavior, and error
    handling, and does not depend on a third party to keep their
    PyPI or npm package current. The SDK is a convenience until the
    day it becomes a constraint — and that day arrives with no
    warning, usually during an incident when you discover the SDK
    does not expose the endpoint you need or silently swallows an
    error you need to handle.

## Error logging: two audiences, two messages

Errors have two consumers with fundamentally different needs. The
user needs to know what happened in terms they can act on. The
engineering team needs to know what happened in terms they can
diagnose. These are almost never the same message, and conflating
them fails both audiences.

The user who sees this has gained nothing:

```
Error: NullReferenceException at CustomerService.cs:247
  in ResolveCapability(Customer customer, String capability)
  at EnrollmentController.cs:89
  at System.Runtime...
```

The stack trace is meaningless to a non-engineer. Worse, it exposes
internal class names, file paths, and line numbers — information that
is useful to an attacker mapping the application's internals and
useless to a customer trying to complete a purchase. The user needed:
"We could not complete your enrollment. Please try again, or contact
support with reference ID a1b2c3d4."

The engineer who sees this in the logs has gained nothing either:

```json
{"level": "error", "event": "enrollment.failed", "message": "Something went wrong"}
```

The event name is right. The level is right. But the diagnostic
context — which customer, which tenant, what the input was, what the
underlying exception was, which dependency failed — is absent. The
engineer must now reproduce the error locally, check the database for
recent enrollment attempts, and guess at the conditions that produced
the failure. The log entry needed:

```json
{"level": "error", "event": "enrollment.failed", "customer_id": 4821, "tenant_id": "zftadvancements", "error_class": "NullReferenceException", "error_message": "capability was nil for source :messaging", "source_file": "customer_service.rb", "source_line": 247, "request_id": "a1b2c3d4", "stack_trace": "CustomerService#resolve_capability:247\nEnrollmentController#create:89\n..."}
```

The principle is a boundary: **the user sees a clean, actionable
message with a reference ID. The logs capture the full diagnostic
context — exception class, message, stack trace, input values,
correlation IDs, and any state that contributed to the failure.** The
reference ID is the bridge: the user reports it to support, and the
engineer queries the logs for that ID to get the complete picture.

```python
import structlog
import uuid

logger = structlog.get_logger()

def enroll_customer(customer_id, tenant_id):
    try:
        result = enrollment_service.execute(customer_id, tenant_id)
        return {"status": "success", "enrollment_id": result.id}

    except Exception as exc:
        reference_id = str(uuid.uuid4())[:8]

        logger.error(
            "enrollment.failed",
            customer_id=customer_id,
            tenant_id=tenant_id,
            error_class=type(exc).__name__,
            error_message=str(exc),
            reference_id=reference_id,
            exc_info=True,
        )

        return {
            "status": "error",
            "message": "We could not complete your enrollment. "
                       "Please try again or contact support.",
            "reference_id": reference_id,
        }
```

The user response contains no diagnostic information — no exception
class, no internal message, no stack trace. The log entry contains
all of it, keyed to the same `reference_id` the user received. The
two records serve their respective audiences without compromising
either: the user is not confused by implementation details, and the
engineer is not left guessing at the cause.

This boundary applies at every layer. API responses should return
HTTP status codes and user-facing messages, not serialized exceptions.
Frontend error boundaries should display recovery instructions, not
JavaScript stack traces. Background job failures should log the full
context and report a clean status to whatever dashboard monitors them.
The internal diagnostic record and the external user-facing message
are two separate concerns, and they belong on opposite sides of a
boundary — exactly the same principle the Design section applies to
every other form of separation.

## Predefined events and enumerated exceptions

The structured logging examples throughout this page use event names
like `enrollment.completed` and `payment.failed`. These names are not
invented at the call site. They are drawn from a predefined set of
known events — an enumerated vocabulary that the team defines,
documents, and queries against. The same principle applies to
exceptions and error types: the set of things that can go wrong in a
system is largely known, and each known failure should have a named,
typed representation.

### Why enumeration matters

A codebase where event names are invented ad hoc at each log call
site has the same problem as a codebase where status values are bare
strings — the vocabulary is unbounded, inconsistent, and impossible
to query reliably. One engineer logs `enrollment.failed`, another
logs `enrollment_error`, a third logs `enroll.fail`. All three mean
the same thing. A dashboard counting enrollment failures misses two
of the three.

Predefined event types eliminate this:

```python
from enum import StrEnum


class Event(StrEnum):
    REQUEST_RECEIVED = "request.received"
    ENROLLMENT_STARTED = "enrollment.started"
    ENROLLMENT_COMPLETED = "enrollment.completed"
    ENROLLMENT_FAILED = "enrollment.failed"
    PAYMENT_INITIATED = "payment.initiated"
    PAYMENT_COMPLETED = "payment.completed"
    PAYMENT_FAILED = "payment.failed"
    CUSTOMER_CREATED = "customer.created"
    CUSTOMER_UPDATED = "customer.updated"


logger.info(Event.ENROLLMENT_COMPLETED, customer_id=4821, duration_ms=47)
```

The event vocabulary is centralized, greppable, and enforced by the
type system. An engineer cannot invent a new event name at a call
site — they add it to the enum, which makes the addition visible in
code review and discoverable by anyone building a dashboard or alert.
If the enum does not have an event for what just happened, that is a
signal: either the event should be added (a deliberate, reviewed
decision) or it does not warrant a log entry.

### Enumerated exceptions

The same discipline applies to exceptions. Most systems have a
finite, known set of failure modes: validation failures, resource not
found, permission denied, external service unavailable, rate limited,
conflict, timeout. Each of these should be a named exception class,
not a generic `Exception` or `RuntimeError` with a message string:

```python
class EnrollmentError(Exception):
    pass

class CustomerNotFound(EnrollmentError):
    def __init__(self, customer_id: int):
        self.customer_id = customer_id
        super().__init__(f"Customer {customer_id} not found")

class CustomerNotEligible(EnrollmentError):
    def __init__(self, customer_id: int, reason: str):
        self.customer_id = customer_id
        self.reason = reason
        super().__init__(f"Customer {customer_id} not eligible: {reason}")

class ProviderUnavailable(EnrollmentError):
    def __init__(self, provider: str):
        self.provider = provider
        super().__init__(f"Provider {provider} is unavailable")
```

Each exception carries structured context — the customer ID, the
reason, the provider name — that is available to the error handler
without parsing a message string. Each exception has a name that
communicates the failure mode. Each exception can be caught
selectively:

```python
def enroll_customer(customer_id, tenant_id):
    try:
        result = enrollment_service.execute(customer_id, tenant_id)
        logger.info(Event.ENROLLMENT_COMPLETED, customer_id=customer_id)
        return {"status": "success", "enrollment_id": result.id}

    except CustomerNotFound as exc:
        logger.warn(Event.ENROLLMENT_FAILED, customer_id=exc.customer_id,
                     reason="not_found")
        return {"status": "error", "message": "Customer not found"}

    except CustomerNotEligible as exc:
        logger.warn(Event.ENROLLMENT_FAILED, customer_id=exc.customer_id,
                     reason=exc.reason)
        return {"status": "error", "message": "Customer is not eligible for enrollment"}

    except ProviderUnavailable as exc:
        logger.error(Event.ENROLLMENT_FAILED, provider=exc.provider,
                      reason="provider_unavailable")
        return {"status": "error", "message": "Service temporarily unavailable. Please try again."}

    except Exception as exc:
        reference_id = str(uuid.uuid4())[:8]
        logger.error(Event.ENROLLMENT_FAILED, error_class=type(exc).__name__,
                      error_message=str(exc), reference_id=reference_id,
                      reason="unexpected", exc_info=True)
        return {"status": "error", "message": "An unexpected error occurred.",
                "reference_id": reference_id}
```

Each known failure mode has its own handler with an appropriate
severity level (`warn` for expected failures like ineligibility,
`error` for infrastructure failures like provider unavailability),
a structured reason field, and a user-facing message calibrated to
the situation. The engineer who reads the log can immediately
distinguish a customer who was not eligible (a normal business
outcome, logged as a warning) from a provider outage (an
infrastructure problem, logged as an error).

The bare `except Exception` at the bottom is the catch-all. It
exists because unexpected failures do happen — a `None` where a
value was expected, a network timeout not covered by the provider
exception, a library raising something unforeseen. The catch-all
ensures the application does not crash and the user receives a
graceful response.

But the catch-all should be a last resort, not the default. A
codebase where most error handling is `except Exception` with a
generic message is a codebase that has not enumerated its failure
modes. Every error that lands in the catch-all is an event the team
did not anticipate — which means it is also an event the team cannot
specifically handle, specifically log, specifically alert on, or
specifically recover from. When a new failure mode is discovered in
the catch-all (a `ProviderTimeout` appearing in the logs with
`reason: unexpected`), the correct response is to define a named
exception for it, add a specific handler, and move it out of the
catch-all. Over time, the catch-all should handle less and less as
the known failure modes are enumerated and addressed. If it is
handling more, the team is not learning from its errors.

## PII and sensitive data in logs

Structured logging makes it easy to include rich context in every
event. That same capability makes it easy to leak credentials,
customer data, and personally identifiable information into log
storage that may be retained for months, replicated across regions,
and accessible to a broader set of engineers and systems than the
production database itself.

The tension is real. Too much redaction and the logs lose the context
that makes them useful — an error log that says `customer_id:
[REDACTED]` cannot be correlated with anything. Too little and the
logs become a compliance liability — an event that includes
`email: jane.doe@example.com` and
`phone: +1-555-867-5309` has replicated PII into a system that may
not have the same access controls, retention policies, or audit
requirements as the primary data store.

### What never belongs in a log

Some values should never appear in log output under any
circumstances:

- **Credentials.** Passwords, API keys, tokens, secrets, session IDs.
  If a log entry contains a bearer token or a database password, the
  log stream is now a credential store with no access control and no
  rotation policy.
- **Full payment instruments.** Credit card numbers, bank account
  numbers, CVVs. PCI DSS explicitly prohibits logging these values.
  A masked suffix (`card_last_four: "4242"`) is sufficient for
  correlation.
- **Authentication artifacts.** Password hashes, MFA codes, recovery
  keys, OAuth authorization codes. These are single-use or
  security-critical values that gain nothing from being logged and
  create risk by existing outside their intended context.

These are not judgment calls. They are non-negotiable exclusions that
should be enforced by the logging infrastructure itself — a
processor or filter that strips known sensitive fields before the
event reaches stdout:

```python
REDACTED_FIELDS = {"password", "token", "secret", "api_key",
                   "card_number", "cvv", "ssn", "authorization"}

def redact_sensitive(logger, method_name, event_dict):
    for key in list(event_dict.keys()):
        if any(sensitive in key.lower() for sensitive in REDACTED_FIELDS):
            event_dict[key] = "[REDACTED]"
    return event_dict

structlog.configure(
    processors=[
        redact_sensitive,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
)
```

The redaction processor runs before the renderer. If an engineer
accidentally passes `api_key=some_secret` to a log call, the
processor catches it. This is defense in depth — the engineer should
not pass the value in the first place, but the infrastructure
prevents it from reaching the log stream regardless.

### What requires judgment

Between the clearly safe (customer ID, request ID, event name) and
the clearly prohibited (passwords, card numbers) is a category that
requires context-dependent decisions:

**Email addresses.** An email is PII. It is also the primary
identifier many support teams use to look up a customer. Logging a
full email address makes support workflows faster. Redacting it
forces support to cross-reference a customer ID against the database
for every lookup. The decision depends on the log storage's access
controls and the regulatory environment. GDPR-subject systems should
generally avoid logging full email addresses; internal systems with
restricted log access may reasonably include them.

**IP addresses.** An IP address is PII under GDPR. It is also
essential for diagnosing network issues, rate-limiting violations,
and abuse patterns. Hashing or truncating (`192.168.x.x`) preserves
some diagnostic value while reducing the PII exposure.

**Names and addresses.** Almost never necessary in application logs.
A customer ID is sufficient for correlation; the name and address can
be resolved from the database when needed. Logging them creates PII
in a system where it does not need to exist.

**Request bodies.** API request payloads often contain a mix of safe
and sensitive fields. Logging the full body is tempting for
debugging and dangerous for compliance. A field-level allowlist —
log only specific, known-safe fields from the payload — is safer
than a denylist that must be updated every time a new sensitive field
is added.

### The heuristic

**Log identifiers, not identity.** A `customer_id` correlates a log
event with a customer record. An email, a name, and a phone number
replicate identity into the log stream. The identifier is sufficient
for every operational workflow: the engineer queries by customer ID,
the support agent looks up the customer in the admin panel, the
compliance team audits by ID in the primary database. The identity
is redundant in the log and creates liability by existing there.

**Enforce at the infrastructure level, not by convention.** A team
policy that says "do not log PII" will be violated — not maliciously,
but because an engineer debugging a production issue will add a
temporary log line with the customer's email to trace a specific
case, and the line will never be removed. A redaction processor in
the logging pipeline is more reliable than a convention that depends
on every engineer remembering the rule under pressure.

**Audit your log output.** Periodically query the log stream for
patterns that look like PII — email-shaped strings, phone-number
patterns, values in fields named `email`, `phone`, `address`, `ssn`.
What you find will likely be surprising. The audit is the feedback
loop that turns the redaction policy from aspirational to enforced.

## The logging hierarchy

Putting the pieces together, the observability stack has a clear
hierarchy of responsibilities:

**The application emits structured events to stdout.** Every log
entry is a self-contained JSON record with named fields, a severity
level, and correlation context. The application does not know or care
where the events go. This is non-negotiable — it is the baseline that
makes everything else possible.

**The infrastructure routes and stores the events.** Container
runtimes, log drivers, sidecar collectors, cloud-native log services
— these capture stdout and deliver it to the appropriate sink. The
routing is configured in the deployment infrastructure, not in the
application code.

**Distributed tracing instruments the request path.** When the system
is distributed — multiple services, asynchronous processing, external
API calls — tracing spans in the application code provide the
causality and timing data that logs alone cannot. Use OpenTelemetry.
Isolate any vendor-specific code behind adapters.

**Metrics aggregate for alerting and trending.** Request rates, error
rates, latency percentiles, queue depths — these are derived from
structured log events or emitted as dedicated metrics via OTel. They
drive dashboards and alerts. They do not replace logs; they
complement them.

Each layer has its own concern, its own rate of change, and its own
team ownership. The application team owns the events. The platform
team owns the routing. The observability team (or the same team
wearing a different hat) owns the tracing configuration and
dashboards. Mixing these responsibilities — application code that
manages log files, routing logic embedded in the service, alerting
rules hard-coded in the application — produces the same entanglement
the Design section documents in other contexts.

## Questions to ask

1. Open a random service's log output. Can an operator who has never
   seen the codebase identify what happened, to which entity, in
   response to which request? If not, the logs are developer notes,
   not operational records.
2. Are log entries structured (JSON, logfmt) or bare strings? If bare
   strings, they cannot be queried, aggregated, or correlated — they
   are write-only data.
3. Does every log entry carry a correlation ID (`request_id`,
   `trace_id`) that links it to related entries across services? If
   not, the log stream is unsortable during concurrent load.
4. Does the application manage log files, rotation, or transport? If
   so, it is doing infrastructure work that belongs in the deployment
   layer.
5. Is instrumentation code vendor-specific or OTel-based? If
   vendor-specific, what is the migration cost when the contract
   renews and the organization wants to evaluate alternatives?
6. How many `console.log`, `print`, or `puts` statements exist in
   production code? Each one is an unstructured, uncorrelated,
   unlabeled event that provides no operational value and dilutes the
   signal of the structured events around it.
