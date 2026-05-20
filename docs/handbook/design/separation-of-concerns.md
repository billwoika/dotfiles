# Separation of Concerns

## Problem statement

A B2C platform has a `Customer` model. In the beginning it is clean:
a name, an email, a tenant reference, an external ID, a `created_at`
timestamp. The model is the principal value object for the system —
every feature touches it, every team queries it, every report
aggregates it.

The first feature request adds a boolean: `is_enrolled`. A customer
is either enrolled in the loyalty program or not. Simple. The second
adds `can_send_messages`. The third adds `receives_promotions`. Each
one is a column, a toggle in the admin panel, and a conditional in
the relevant feature code. Manageable.

Then the platform grows.

Tenant-level configuration enters the picture — the platform serves
multiple brands, each with their own rules about which capabilities
customers get by default. The booleans are no longer "on or off";
they are "on or off unless the tenant default says otherwise unless
the customer has an explicit override." The admin panel adds the
override toggles. The public API adds them. The customer-facing app
adds some but not all of them. Three surfaces can now modify the same
state with different validation rules and different audit
expectations.

Then per-tenant customization deepens. Enterprise tenants want
messaging opt-in to require double confirmation. Other tenants want
enrollment to be automatic on first purchase. The booleans that
started as columns on `Customer` now need context: *which* tenant's
rules apply, *which* surface set the value, *whether* the customer
confirmed, and *when*. But the model still stores them as flat columns
because that is how they were born.

Then the callbacks arrive.

```ruby
class Customer < ApplicationRecord
  before_save :enforce_tenant_defaults, if: :tenant_id_changed?
  before_save :sync_messaging_provider, if: :can_send_messages_changed?
  after_save :notify_enrollment_service, if: :is_enrolled_changed?
  after_save :update_promotion_preferences, if: :receives_promotions_changed?
  after_save :audit_log_changes
  after_save :bust_eligibility_cache
  after_save :sync_to_crm, unless: :skip_crm_sync
  after_commit :enqueue_welcome_sequence, if: :just_enrolled?

  attr_accessor :skip_crm_sync
  attr_accessor :skip_messaging_sync
  attr_accessor :provisioned_by_migration
end
```

Each callback was added to solve a real problem. Each `attr_accessor`
flag was added because some code path needed to save the customer
without triggering some subset of side effects. The flags accumulate.
The conditional logic fans out. A senior engineer can trace the
execution path for a given save — they know which callbacks fire,
which flags suppress which side effects, which order the `before_save`
and `after_save` hooks execute in. A frontline support engineer
cannot. When a customer's `can_send_messages` flag is `false` and the
customer says they opted in, the support engineer cannot answer "why
is it off?" without escalating — because the answer might be the
tenant default, an explicit override from the admin panel, a failed
callback that silently rolled back, a migration that set
`skip_messaging_sync` and inadvertently skipped the provisioning
step, or a race condition between the API and the customer-facing app.

The team responds predictably. New models are added to mediate:
`CustomerCapabilityOverride`, `TenantDefault`,
`CapabilityAuditLog`. Services are created to standardize the
mutation paths: `CustomerEnrollmentService`,
`MessagingProvisioningService`, `TenantPolicyEnforcementService`.
Each service calls the others. The callback chain calls the services.
The services call back into the model. The dependency graph becomes
circular, and the team draws a diagram on a whiteboard that nobody
updates after the first week.

Then a seemingly reasonable architectural decision makes it worse.

The platform integrates with external systems — a POS, a loyalty
aggregator, a third-party messaging gateway. Each system has its own
identifier for the customer. A new model is introduced:
`ExternalIdentifier`, tracking the source system, the external ID,
and the state of that integration (active, pending, disconnected).
The customer's capabilities now depend not just on tenant
configuration and overrides, but on the *state of their external
integrations*: a customer can only send messages if their messaging
gateway identifier is active; they are only enrolled if their loyalty
aggregator record is confirmed.

On its face, this looks like the correct move — extracting the
external integration state into its own model, giving it a proper
lifecycle, separating it from the customer record. But in practice it
has replicated the original problem in multiplicity. The
`ExternalIdentifier` model now accumulates its own boolean flags
(`is_synced`, `opt_in_confirmed`, `provider_active`), its own
callbacks (`after_save :recalculate_customer_capabilities`), and its
own `attr_accessor` suppression flags (`skip_capability_refresh`).
The customer's resolved capabilities are now a function of:

1. The tenant defaults
2. The customer's explicit overrides
3. The state of N external identifiers, each with their own lifecycle

The computation fans out. A change to an `ExternalIdentifier` record
triggers a recalculation of customer capabilities, which triggers CRM
sync callbacks, which check the external identifier states, which may
themselves be mid-update. The circular dependency that existed within
the `Customer` model now spans multiple models — harder to see,
harder to trace, and producing the same class of failures: support
cannot answer "why is this off?" without an engineer tracing the
computation across three tables and two callback chains.

The proxy model did not solve the separation problem. It distributed
it across a wider surface area while preserving the fundamental
mistake: **policy is still stored as state that must be synchronized,
rather than computed from the current context at decision time.**

**The root cause is not complexity. The root cause is that the system
is tracking policy in instance state — and adding more models to
store intermediate policy state does not fix this; it compounds it.**
Whether a customer can send messages is a *policy decision* — it
depends on the tenant configuration, the customer's explicit opt-in
status, the confirmation state, and the current state of the relevant
external integration. Storing the resolved answer as a boolean column
anywhere — whether on the customer record or on a proxy model —
conflates the decision with the data. Every mutation surface must now
re-implement the decision logic, every callback must account for every
context, and every new capability flag or integration source repeats
the entire cycle.

## What's wrong

The `Customer` model has become a god object — not because it is
large (though it is) but because it is the meeting point for concerns
that have no business being entangled:

**Identity** (who is this customer — name, email, tenant, external ID)
is entangled with **policy** (what can this customer do given their
tenant's rules, explicit overrides, and confirmation state) is
entangled with **side effects** (what happens when a value changes:
CRM sync, messaging provider provisioning, enrollment workflows) is
entangled with **presentation** (which surfaces expose which controls
with which validation rules).

Each of these concerns changes for different reasons, at different
times, driven by different stakeholders:

- Policy changes when the product team redesigns tenant capabilities
  or a new partner integration requires different opt-in flows.
- Side effects change when infrastructure migrates (new CRM, new
  messaging provider, new queue backend).
- Presentation changes when the support team needs a new admin view or
  the customer-facing app adds a self-service capability.
- Identity rarely changes at all.

When all four live in the same model, a change to any one requires
understanding — and risking — the others. The callback chain is the
most visible symptom: it exists because the model is doing too many
things, and each thing needs to react to changes made by the other
things.

## The principle

**Separate the thing from the policy about the thing.** The customer
record should store identity and state — facts about the customer
that are true regardless of what the system does with them. What the
customer *can do* is a policy question that should be answered by a
separate concern, queried at decision time, informed by whatever
context is relevant (tier, overrides, tenant, time), and never cached
as a column on the customer record.

This is Separation of Concerns in its most concrete form: the
customer model has accumulated concerns that belong to different parts
of the system, and the fix is not more callbacks or more services on
top of the existing structure — it is moving the concerns to where
they belong.

## What separation looks like

The following is illustrative, not prescriptive — the specific class
names and interfaces depend on the application. The structural
principle is what matters.

**Customer stores identity:**

```ruby
class Customer < ApplicationRecord
  belongs_to :tenant
  has_many :capability_overrides

  # No callbacks. No policy. No side effects.
  # This model is a record of who the customer is:
  # name, email, tenant, external_id, created_at.
end
```

**Policy is a separate query:**

```ruby
class CustomerCapability
  def initialize(customer)
    @customer = customer
    @tenant = customer.tenant
    @overrides = customer.capability_overrides
    @integrations = customer.external_identifiers
  end

  def enrolled?
    resolve(:enrollment)
  end

  def can_send_messages?
    resolve(:messaging)
  end

  def receives_promotions?
    resolve(:promotions)
  end

  private

  def resolve(capability)
    return false unless integration_ready?(capability)

    override = @overrides.find_by(capability: capability)
    return override.enabled if override

    TenantDefault.enabled?(@tenant, capability)
  end

  def integration_ready?(capability)
    required_source = CAPABILITY_SOURCES[capability]
    return true unless required_source

    integration = @integrations.find_by(source: required_source)
    integration&.active?
  end

  CAPABILITY_SOURCES = {
    messaging: :messaging_gateway,
    enrollment: :loyalty_aggregator
  }.freeze
end
```

The capability is computed at decision time from the current state of
the tenant configuration, the customer's explicit overrides, and the
live state of the relevant external integration. Nothing is cached as
a column. Nothing triggers a recalculation callback. When support asks
"why can't this customer send messages?", the answer is traceable
without escalation: is the messaging gateway integration active? Does
the tenant allow messaging? Is there an override? Each question
points to a single source of truth that can be inspected directly.

**Side effects are explicit operations, not model hooks:**

```ruby
class CustomerEnroller
  def enroll(customer)
    customer.capability_overrides.upsert_capability(:enrollment, true)
    CrmSync.push(customer)
    MessagingProvider.provision(customer)
    WelcomeSequence.enqueue(customer)
    AuditLog.record(:customer_enrolled, customer)
  end
end
```

Each mutation path calls exactly the side effects it intends. There
are no `skip_crm_sync` flags because no global callback chain exists
to suppress. A migration that updates customer records does not
trigger messaging provisioning because it does not call
`CustomerEnroller` — it writes to the overrides table directly, and
the model has no callbacks to surprise it.

## The deeper lesson

The `Customer` example is a specific instance of a general failure
pattern: **using instance state to encode policy decisions that should
be computed.** The boolean columns are not data — they are cached
answers to questions that depend on context the column cannot capture.
Every time the context changes (tenant reconfiguration, new partner
rules, updated opt-in requirements), the cached answers are wrong and
the system must be re-synchronized — if anyone realizes they are
stale at all.

This pattern appears everywhere:

- A `User` model with `is_admin`, `can_manage_billing`,
  `can_view_reports` columns that should be derived from role
  assignments.
- An `Order` model with `requires_approval` that should be computed
  from the order amount, the customer's credit terms, and the
  approver's delegation rules.
- A `Member` model with `is_enrolled`, `loyalty_tier` columns that
  should be resolved from the tenant's program configuration and the
  member's transaction history.

In each case, the column represents a decision that was made at write
time and frozen. The system evolves, the decision logic changes, and
the frozen answer diverges from what the current logic would produce.
The fix is always the same: **separate the data from the decision,
and compute the decision at query time from the current context.**

## When separation is the wrong reach

**Genuinely static flags.** Some booleans on a model really are simple
state with no policy dimension. A `Customer` with `email_verified:
true` is recording a fact — the customer confirmed their email
address. It is not context-dependent, it does not vary by tenant, and
it is set once. Do not build a `VerificationPolicy` class for a
column that is never re-evaluated.

**Premature extraction.** A model with three callbacks that all fire
on every save, with no conditional logic and no suppression flags, is
not yet a god object. It is a model that does a few things on save.
Extract when the conditional complexity arrives, not before.

**Performance-critical hot paths.** See the next section — this
objection is common enough and important enough to warrant its own
treatment.

## The memoization argument

The strongest criticism of "compute policy at query time" is
performance. The argument: at scale, the computation is expensive.
A customer capability check that joins tenant defaults, explicit
overrides, and external integration states is three queries (or a
complex join) on every request. Multiply by thousands of customers
per second and the database becomes the bottleneck. Memoized state
— a pre-computed, cached answer stored as a column or in Redis — is
the proven solution. Every large system does it. The page's advice to
"compute at decision time" is a luxury that works at startup scale
and breaks at real scale.

This criticism is correct about the problem and wrong about the
conclusion.

### Where the criticism is right

Computing policy from live state on every request is genuinely
expensive at scale. A `CustomerCapability` object that queries three
tables on every `can_send_messages?` call does not survive a hot path
that evaluates it 10,000 times per second. Caching the resolved
answer — in memory, in Redis, in a denormalized column — is a
legitimate and often necessary optimization.

The page does not argue against caching. It argues against **starting
with the cache as the source of truth.**

### Where it goes wrong

The difference between a cache and a column is invalidation
discipline. A cache has an explicit TTL or an explicit invalidation
event. A column does not — it persists until something writes a new
value, and nothing in the schema tells you when that should happen or
what computation produced the current value.

The systems that get into trouble are not the ones that cache a
computed result. They are the ones where:

1. **The cache becomes the authority.** The column is the thing the
   application reads, and the computation that should produce it is
   spread across callbacks, services, and migration scripts that may
   or may not run in the right order. Nobody can point to a single
   function that answers "given the current state, what should this
   value be?" because that function was never written — the column
   *is* the answer, maintained by a distributed, implicit process.

2. **Invalidation is implicit.** The column is "refreshed" by
   callbacks that fire on save events across multiple models. If any
   model saves without triggering its callback (a direct SQL update,
   a bulk migration, a service that sets `skip_capability_refresh`),
   the cached value is stale and nobody knows. The system has no way
   to detect or recover from this state because there is no canonical
   computation to compare against.

3. **The cache outlives its context.** A value computed under one set
   of tenant rules persists after the rules change. The tenant
   reconfigures messaging permissions, but existing customers retain
   stale `can_send_messages` values until something triggers a
   recalculation — which may never happen for inactive customers,
   producing a permanent inconsistency between what the rules say and
   what the data shows.

### The correct architecture

The separated model and the cache are not in tension. They are
layers:

```
1. The canonical computation (CustomerCapability)
   - The single function that answers "given current state, what
     should this value be?"
   - Always correct. Possibly slow.

2. The cache (Redis, denormalized column, materialized view)
   - A memoized snapshot of the computation's output.
   - Fast. Possibly stale.

3. The invalidation contract
   - When the inputs change (tenant config, override, integration
     state), the cache is invalidated.
   - The computation re-runs and the cache is refreshed.
   - If the cache is ever suspect, the computation is the fallback.
```

The critical property: **the computation exists independently of the
cache.** You can delete every cached value in the system and
recompute them from the canonical function. You can run the canonical
function against a customer record and compare it to the cached value
to detect drift. You can change the policy logic in one place and
know that the next invalidation cycle will propagate it everywhere.

None of this is possible when the column *is* the answer and the
computation is distributed across callbacks. That is not caching — it
is state management without a source of truth.

### The heuristic

Start with the computation. Measure. When measurement shows that
the computation is too expensive for the hot path, add a cache in
front of it — with an explicit invalidation contract and the ability
to recompute from scratch. The cache is an optimization over a
correct system, not a substitute for one.

The systems that fail at scale are not the ones that cache too little.
They are the ones that cache without a canonical computation to
invalidate against — because when the cache is wrong (and it will
eventually be wrong), there is no way to make it right except by
reading the code, tracing the callbacks, and hoping you found all the
mutation paths. That is the position the `Customer` model is in. The
column is the cache, but there is no function to recompute it from,
and no contract that says when it should be refreshed.

### When static values are required

There is one category where the "compute at decision time" model does
not apply: **regulatory requirements that mandate a frozen,
point-in-time record.**

Financial services, healthcare, and certain consumer privacy
regulations require that the system produce the exact value that was
in effect at a specific moment — not the value that the current rules
would compute. A TCPA opt-in timestamp, a GDPR consent record, an
FDA audit trail, a SOX-relevant approval state — these are not policy
decisions to be recomputed. They are legal artifacts that must be
immutable once recorded.

In these cases, the static column is not a cache of a computed
result. It is the record itself, and recomputing it would be a
compliance violation. The distinction is important:

- **A column that says "this customer can send messages" is policy.**
  It should be computed from current rules.
- **A column that says "this customer consented to receive messages at
  2026-03-15T14:22:07Z via the mobile app, consent version 2.1" is a
  regulatory record.** It should never be recomputed or overwritten.

The two can coexist cleanly. The consent record is a fact — it lives
on a dedicated consent or audit log as immutable state. That log is
the compliance source of truth. It can — and for audit purposes
should — include the computed capability state at the time of the
event: "at the moment this customer consented, the resolved
capability was X, computed from tenant config Y and override Z." This
snapshot serves compliance without polluting the live model. The
capability decision reads the consent record as one of its inputs,
alongside tenant configuration and integration state. The consent
record answers "did they consent?"; the capability computation
answers "given that they consented, and given the current tenant
rules, can they send messages right now?"

Conflating the two — storing "can_send_messages: true" and treating
it as both the regulatory proof of consent and the live capability
flag — is how systems end up in the worst position: unable to
recompute because the column is legally significant, but also unable
to trust it as a capability decision because the rules have changed
since it was written.

## Questions to ask

1. Is this column storing a fact about the entity, or a decision that
   depends on context? If context-dependent, it is policy and should
   be computed.
2. How many `attr_accessor` flags exist to suppress side effects
   during saves? Each one is evidence that the callback chain has
   become unmanageable.
3. Can a frontline support engineer trace why a value is what it is
   without escalating to a senior engineer? If not, the decision logic
   is buried in code paths that should be explicit and queryable.
4. How many surfaces can mutate this state? If more than one, do they
   all apply the same validation and trigger the same side effects? If
   not, the model is mediating concerns that belong to the mutation
   paths, not to the model itself.
5. When the business changes the rules (new tier, new override
   structure), how many files change? If the answer is "the model,
   three services, two controllers, and the admin panel," the policy
   is scattered rather than separated.
