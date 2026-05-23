# Value Types

## Problem statement

A B2C platform tracks customer status as a string. The column is
`varchar`, the API returns it as a JSON string, and the frontend
stores it as a string in state. The possible values are "pending",
"active", and "archived."

In theory.

```typescript
// In the customer service
if (customer.status === "active") {
  // ...
}

// In the admin panel, written by a different engineer
if (customer.status === "Active") {
  // ...
}

// In the reporting module, written six months later
if (customer.status === "ACTIVE") {
  // ...
}

// In a migration script, written at 2am during an incident
await db.query(`UPDATE customers SET status = 'actve' WHERE ...`)
```

Four representations of the same concept. Three capitalizations of a
value that should be a single symbol. One typo that made it to
production because nothing in the system distinguishes "actve" from
"active" — they are both strings, and strings are all equal in their
willingness to be wrong.

The admin panel check fails silently for every customer whose status
was set by the API (lowercase). The reporting module misses every
customer whose status was set by the admin panel (title case). The
migration script creates a fourth variant that no conditional anywhere
in the codebase will ever match. The customer is effectively in a
status that does not exist — not pending, not active, not archived,
but "actve," a state the system cannot interpret and no engineer will
notice until a support ticket arrives asking why a customer is
invisible.

The root cause is not carelessness. The root cause is that the system
models status as a string — an unbounded type that can hold any
sequence of characters — when the domain concept is an enumerated set
of exactly three known values. The type does not match the meaning.

## What it looks like vs. what it is

The stringly-typed status is one instance of a pervasive category of
error: **modeling a value by what it looks like rather than how it is
used.**

A phone number is composed of digits. It looks like an integer. But
nobody performs arithmetic on a phone number. Nobody adds two phone
numbers together, divides a phone number by three, or checks whether
a phone number is greater than another. A phone number is an
identifier with formatting rules (country code, area code, subscriber
number), validation constraints (length, allowed prefixes), and
display conventions (parentheses, hyphens, spaces). Treating it as an
integer strips all of this meaning. A leading zero — significant in
many international formats — disappears when parsed as a number.
Arithmetic operations that are meaningless for phone numbers become
syntactically valid. The type permits operations the domain forbids.

A customer ID is an auto-incrementing integer in the database. It
looks like a number. But with rare and exotic exceptions — internal
B-tree indexing being the canonical one — nobody performs arithmetic
on a customer ID. It is not meaningful to add customer 42 and customer
17 to get customer 59, or to ask whether customer 100 is "greater
than" customer 50 in any domain-relevant sense. The integer is a
storage representation, not a domain type. Passing it as a bare `int`
or `number` means the type system cannot distinguish a customer ID
from an order ID, a product ID, a quantity, or a line number. A
function that accepts `(customerId: number, orderId: number)` will
happily accept the arguments in the wrong order, and the compiler
will not catch it.

Currency is the most notorious example. A price looks like a decimal
number: $19.99. But floating-point arithmetic on currency produces
results that are wrong:

```typescript
const price = 19.99
const tax = price * 0.07
console.log(tax)  // 1.3993000000000002
```

The extra digits are not a display problem. They are a computational
error introduced by IEEE 754 floating-point representation, and they
compound across operations. A system that tracks revenue in
floating-point dollars will produce monthly totals that are off by
cents — undetectable in casual inspection, clearly wrong in an audit.
Modeling currency as an integer count of the smallest unit (cents,
pence, satoshis) eliminates the problem entirely: `1999` cents is
exact, `1999 * 7 / 100` is integer arithmetic with defined rounding
behavior, and the type system can enforce that currency values are
never constructed from floating-point sources.

In each case, the fix is the same: **model the value by how it is
used, not by what it looks like.** A phone number is not an integer —
it is a phone number. A customer ID is not a number — it is a
customer ID. A price is not a float — it is a quantity of cents. The
type should encode this distinction so the compiler enforces it,
rather than relying on every engineer in the codebase to remember it.

## TypeScript: the type system as contract

TypeScript was introduced to JavaScript ecosystems for precisely this
reason — to catch at compile time the category of errors that
stringly-typed, loosely-typed code produces at runtime. The type
system is a contract: it declares what values are valid, what
operations are permitted, and what shapes data must conform to. The
compiler enforces the contract on every build.

This works only when the contract is honored.

### The progression

The customer status example, evolved through increasingly rigorous
typing:

**Level 0: bare string.**

```typescript
interface Customer {
  id: number
  name: string
  status: string
}

function deactivate(customer: Customer) {
  if (customer.status === "active") {
    customer.status = "archived"
  }
}
```

The `status` field accepts any string. The compiler cannot verify that
`"active"` is a valid status value. A typo in the comparison (`"actve"`)
compiles without error. A typo in the assignment (`"archved"`)
compiles without error. The type system is present but not
participating.

**Level 1: union type.**

```typescript
type CustomerStatus = "pending" | "active" | "archived"

interface Customer {
  id: number
  name: string
  status: CustomerStatus
}

function deactivate(customer: Customer) {
  if (customer.status === "active") {
    customer.status = "archived"
  }
}
```

The `status` field now accepts exactly three values. A typo in the
assignment — `customer.status = "archved"` — is a compile-time error.
The union type is the contract: these are the valid values, and the
compiler will reject anything else.

This is the minimum viable typing for an enumerated set. It costs one
line (the type alias) and eliminates the entire category of
misspelling and invalid-value bugs. For many cases, this is
sufficient.

**Level 2: enum.**

```typescript
enum CustomerStatus {
  Pending = "pending",
  Active = "active",
  Archived = "archived",
}

interface Customer {
  id: number
  name: string
  status: CustomerStatus
}

function deactivate(customer: Customer) {
  if (customer.status === CustomerStatus.Active) {
    customer.status = CustomerStatus.Archived
  }
}
```

The enum adds two properties the union type does not have: the values
are referenced by name rather than by literal (no string comparison
anywhere in the business logic), and the enum is iterable (you can
enumerate all valid statuses for a dropdown, a validation check, or a
migration). The trade-off is verbosity — `CustomerStatus.Active`
instead of `"active"` — but the verbosity is self-documenting, and
the compiler enforces exhaustive handling in switch statements.

**Level 3: branded types.**

For values that are not enumerated but still need type distinction —
IDs, for instance — TypeScript supports a pattern called branding:

```typescript
type CustomerId = number & { readonly __brand: "CustomerId" }
type OrderId = number & { readonly __brand: "OrderId" }

function createCustomerId(id: number): CustomerId {
  return id as CustomerId
}

function createOrderId(id: number): OrderId {
  return id as OrderId
}

function getCustomer(id: CustomerId): Customer {
  // ...
}

function getOrder(id: OrderId): Order {
  // ...
}

const customerId = createCustomerId(42)
const orderId = createOrderId(17)

getCustomer(customerId)  // compiles
getCustomer(orderId)     // compile-time error: OrderId is not assignable to CustomerId
```

The brand exists only at compile time — it has no runtime
representation and no performance cost. But it prevents the class of
bug where a customer ID is accidentally passed as an order ID. The
two are both numbers at runtime, but the type system treats them as
distinct types. The constructor functions (`createCustomerId`,
`createOrderId`) are the only places where the `as` cast appears, and
they serve as documented, auditable entry points for creating typed
values from raw numbers.

### The escape hatches

Every TypeScript engineer has encountered a moment where the type
system refuses to cooperate. The data shape does not match the
interface. The third-party library's types are wrong. The API returns
something the schema does not describe. The compiler produces an
error that is technically correct but impractical to resolve in the
current sprint.

TypeScript provides escape hatches for these moments:

```typescript
const data = response.data as any
const config = JSON.parse(rawConfig) as AppConfig
// @ts-ignore — third-party types are wrong, fix after upgrade
const result = legacyLib.process(input)
```

These escape hatches exist for a reason. They are sometimes necessary.
They are never good.

`as any` tells the compiler: "stop checking this value." Every
operation on it from this point forward is unchecked. Every property
access is assumed valid. Every method call is assumed to exist. The
type system — the entire reason TypeScript exists — is suspended for
this value and everything derived from it. If the value's actual
shape does not match what the code assumes, the error surfaces at
runtime, in production, in a context the compiler was specifically
designed to prevent.

`as SomeType` (a type assertion) tells the compiler: "I know better
than you what this value is." Sometimes this is true — the engineer
has verified the shape through other means. Often it is not — the
assertion is a way to make the build succeed without resolving the
underlying type mismatch. The type system shows the value as
`SomeType` in every subsequent operation, but the runtime value has
not changed. If the assertion is wrong, the contract is broken
silently.

`@ts-ignore` tells the compiler: "skip this line entirely." The error
on the next line might be a false positive from incorrect third-party
types. It might also be a genuine type error that the engineer does
not want to deal with right now. The comment does not distinguish
between these cases, and six months later, neither will the engineer
who encounters it.

These are not style preferences. They are not "maybe not the best
practice." **They are the type-system equivalent of overriding test
failures or disabling CI pipeline checks.** The type system is a
contract that the compiler enforces on every build. Circumventing it
means the contract is no longer enforced for that value, that
function, that module. The build succeeds, but the guarantee the
build was supposed to provide — that the code conforms to its declared
types — no longer holds.

This should be understood as an emergency workaround, not a design
tool. A codebase where `as any` appears in application code (not in
type-definition shims or test fixtures) is a codebase where the type
system has holes. Each hole is a location where runtime errors can
appear that the compiler was specifically built to prevent.

### The slow erosion

The most common path to a poorly typed codebase is not a single
decision to abandon types. It is a gradual erosion where each
individual escape is justified and the aggregate is a type system that
guarantees nothing.

It starts with a type definition that is almost right:

```typescript
type CustomerStatus = "pending" | "active" | "archived"

interface Customer {
  id: number
  name: string
  status: CustomerStatus
  metadata: Record<string, unknown>
}
```

The `metadata` field is `Record<string, unknown>` because the metadata
shape varies by tenant. This is technically correct — the type system
cannot describe a shape it does not know. But every consumer of
`metadata` must now cast or narrow the value:

```typescript
const loyaltyTier = customer.metadata.loyalty_tier as number
const preferredChannel = customer.metadata.channel as string
```

Each `as` cast is a micro-escape. The consumer assumes `loyalty_tier`
exists and is a number. If the assumption is wrong — if the tenant
does not use loyalty tiers, if the field was renamed, if it is stored
as a string — the cast compiles and the error appears at runtime.

Then a utility function is written to extract metadata:

```typescript
function getMetadata<T>(customer: Customer, key: string): T {
  return customer.metadata[key] as T
}

const tier = getMetadata<number>(customer, "loyalty_tier")
```

The generic function looks type-safe — it returns `T`. But `T` is
whatever the caller says it is. The function performs no validation.
The `as T` cast is the same escape hatch wrapped in a function
signature that makes it look legitimate. The type system now reports
`tier` as `number` with full confidence, even though the underlying
value might be `undefined`, a string, or an object.

Then the pattern spreads. Engineers see `getMetadata<T>` and use it
everywhere. The metadata bag grows. Each access is a cast. The type
system reports precise types for values it has never validated. The
codebase has types, but the types are aspirational rather than
enforced.

This is why typing discipline matters most at the start. A codebase
that begins with strict types — no `any`, no unvalidated casts,
unknown data validated at the boundary and typed from that point
forward — maintains its guarantees as it grows. A codebase that
begins with loose types and "we'll tighten it up later" almost never
does, because tightening types in a large codebase means surfacing
every assumption that was hidden behind a cast, and the volume of
errors that appear is demoralizing enough to abandon the effort.

### Start strict, stay strict

The discipline is straightforward:

**Validate at the boundary, trust inside.** When data enters the
system — from an API response, a database query, user input, a
message queue — validate its shape and type it from that point
forward. Inside the boundary, the types are the source of truth. No
casts, no assertions, no `@ts-ignore`.

```typescript
function parseCustomerResponse(data: unknown): Customer {
  if (
    typeof data !== "object" || data === null ||
    !("id" in data) || typeof (data as any).id !== "number" ||
    !("status" in data) || !isCustomerStatus((data as any).status)
  ) {
    throw new ValidationError("Invalid customer data")
  }
  return data as Customer
}

function isCustomerStatus(value: unknown): value is CustomerStatus {
  return value === "pending" || value === "active" || value === "archived"
}
```

The `as` cast appears exactly once — after validation has confirmed
the shape. From this point forward, every function that receives a
`Customer` can trust the type without re-validating. The boundary
function is the single location where raw data becomes typed data,
and it is the only place where a cast is justified.

**Define what you mean.** Do not define `type CustomerStatus =
"pending" | "active" | "archived"` and then declare a field as
`status: string`. The union type exists to restrict the value space.
Widening it back to `string` discards the restriction and reintroduces
every bug the type was meant to prevent. This sounds obvious. It
happens constantly — often because an interface is shared between
typed internal code and untyped external data, and the engineer
widens the type to avoid writing a validation function.

**Make impossible states unrepresentable.** If a customer can only be
archived after being active (never directly from pending), the type
system can encode this:

```typescript
type PendingCustomer = {
  status: "pending"
  activatedAt: null
  archivedAt: null
}

type ActiveCustomer = {
  status: "active"
  activatedAt: Date
  archivedAt: null
}

type ArchivedCustomer = {
  status: "archived"
  activatedAt: Date
  archivedAt: Date
}

type Customer = PendingCustomer | ActiveCustomer | ArchivedCustomer
```

A customer with `status: "archived"` and `activatedAt: null` cannot
exist. The type system rejects it at compile time. No runtime check
is needed because the invalid state is not representable. The types
are not just labels — they encode the domain's rules about what
combinations of values are valid.

## Modeling the domain

Typing discipline is a technical skill. Knowing *which* types to
define is a domain skill.

A system that models currency as `number`, status as `string`, and
phone numbers as `string` is technically functional. The code runs.
The tests pass. The values flow through the system and produce the
correct outputs — most of the time. The failures appear at the edges:
the floating-point rounding error on a financial report, the typo in
a status comparison that silently excludes a segment of customers,
the phone number that loses its leading zero when parsed as an
integer somewhere in a data pipeline.

Fixing these failures requires understanding the domain, not the
language. The engineer who models currency as cents instead of dollars
does so because they understand that financial calculations require
exactness. The engineer who models status as an enum instead of a
string does so because they understand that the business has a finite,
known set of states with defined transitions between them. The
engineer who models a phone number as a dedicated type with validation
and formatting does so because they understand that phone numbers have
structure that matters to the business — country codes determine
routing, formatting determines readability, validation determines
whether the number is reachable.

This is where the purely technical discussion of types meets the
broader theme of the Handbook: **the difference between software that
technically works and software that produces value is the developer's
depth of understanding of the domain it serves.** A developer who
treats the codebase as a collection of strings, numbers, and booleans
to be shuffled between endpoints will produce code that works. A
developer who understands that a `CustomerStatus` is a state machine,
that a `Money` value is a quantity with currency and precision rules,
that a `PhoneNumber` is an identifier with regional formatting
conventions — that developer will produce code that encodes the
domain's rules in its types and catches violations at compile time
rather than in production.

This does not mean every developer must be a domain expert before
writing code. It means that typing discipline is the mechanism through
which domain understanding enters the codebase. When an engineer
defines a type, they are making a claim about the domain: "these are
the valid values, these are the valid operations, this is what this
concept means." If the claim is wrong — if the type is too broad
(`string` when it should be a union) or too narrow (an enum that is
missing a state the business uses) — the type system will either fail
to catch real errors or reject valid operations. Getting the types
right requires understanding the domain. And getting the types right
early — before the codebase grows around loose types — is orders of
magnitude cheaper than tightening them later.

The engineer who does this well is, in their own right, a subject
matter expert for the domain the software touches. Not necessarily an
expert in the business itself — not a loyalty program designer, not a
payments specialist, not a compliance officer — but an expert in how
the business's concepts translate into computational structures. That
translation is the core of the work.

## Composite types as domain language

Individual value types — `CustomerStatus`, `Money`, `PhoneNumber`,
`CustomerId` — are the atoms. The real power appears when they compose
into structures that reflect the domain's own vocabulary.

```typescript
type Money = {
  readonly cents: number
  readonly currency: "USD" | "EUR" | "GBP"
}

type LoyaltyTier = "bronze" | "silver" | "gold" | "platinum"

type EnrollmentRecord = {
  readonly customerId: CustomerId
  readonly enrolledAt: Date
  readonly enrolledBy: UserId
  readonly tier: LoyaltyTier
  readonly initialBalance: Money
}

type RedemptionRequest = {
  readonly customerId: CustomerId
  readonly amount: Money
  readonly source: "pos" | "online" | "mobile"
  readonly requestedAt: Date
}
```

The `EnrollmentRecord` is not a generic object with fields. It is a
domain concept with typed constituents. The `customerId` is a
`CustomerId`, not a `number` — it cannot be confused with a `UserId`
or an `OrderId`. The `initialBalance` is a `Money`, not a `number` —
it carries its currency and is represented in cents. The `tier` is a
`LoyaltyTier`, not a `string` — it is one of four known values.

A function that processes enrollment:

```typescript
function processEnrollment(record: EnrollmentRecord): void {
  // The types guarantee:
  // - customerId is a valid CustomerId, not an arbitrary number
  // - tier is one of four known values, not an arbitrary string
  // - initialBalance is Money with a known currency, not a bare number
  // - enrolledAt is a Date, not a string that might or might not parse
}
```

The function signature is a contract. It declares not just the shape
of the data but the *meaning* of each field. An engineer reading the
signature understands what `processEnrollment` expects without reading
its implementation. The types are the documentation, and unlike
comments, the compiler enforces them.

When the business adds a fifth loyalty tier — "diamond" — the change
is a single line:

```typescript
type LoyaltyTier = "bronze" | "silver" | "gold" | "platinum" | "diamond"
```

The compiler immediately identifies every location in the codebase
that handles loyalty tiers and does not account for the new value:
switch statements without a "diamond" case, UI components that map
tiers to colors, reports that aggregate by tier. Each location is a
compile-time error, not a runtime surprise. The type system converts
a business change into a checklist of code changes, exhaustively,
automatically.

This is the payoff of typing discipline applied to domain concepts.
Not just catching typos in status comparisons — that is the minimum
— but encoding the domain's vocabulary in the type system so that
business changes propagate through the codebase as compiler errors
rather than production incidents.

## Python: dataclasses and validation

!!! note "Section in progress"

    This section will cover Python's progression from bare
    dictionaries to `@dataclass` to Pydantic models. The core
    positions:

    **Both should be treated as immutable.** Value objects in the DDD
    sense — defined by their attributes rather than their identity,
    immutable once created, comparable by value rather than by
    reference — map directly to `@dataclass(frozen=True)` and
    Pydantic's `model_config = ConfigDict(frozen=True)`. Neither
    should be used as stateful instances that track internal mutation.

    **Pydantic is for boundaries. Dataclasses are for everything
    else.** Modern Python's native `@dataclass` covers the vast
    majority of value-object needs: immutability via `frozen=True`,
    structural equality, slots, type hints, and post-init validation.
    Pydantic's value is its validation and coercion engine — parsing
    untrusted external data (API payloads, configuration files, user
    input) into typed, validated structures, and secrets management
    via `SecretStr`. Inside the boundary, once data has been validated
    and typed, native dataclasses are the right tool: lighter weight,
    no schema overhead, no runtime coercion, and no dependency beyond
    the standard library.

## Questions to ask

1. How many string comparisons in the codebase check the same
   enumerated value? Each one is a location where a typo compiles
   successfully and fails silently.
2. Are IDs typed distinctly, or are they bare integers/strings that
   can be accidentally interchanged? A function that accepts
   `(customerId: number, orderId: number)` will accept the arguments
   in the wrong order without complaint.
3. How is currency represented? If any arithmetic operates on
   floating-point dollar values, the results will be wrong — not
   approximately wrong, but exactness-violating wrong in ways that
   compound across operations.
4. When the business adds a new variant (a new status, a new tier, a
   new payment method), does the compiler identify every location that
   must change? If not, the type system is not encoding the domain's
   constraints.
5. How many `as any`, `as unknown`, or `@ts-ignore` directives appear
   in application code (not type shims or test fixtures)? Each one is
   a hole in the type system's guarantees.
6. When an engineer defines a new type, does it reflect how the value
   is *used* in the domain, or how it is *stored* in the database?
   The two are often different, and the type should serve the domain.
