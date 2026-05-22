# Locality

## Problem statement

A Vue 3 platform has grown to thirty-odd features. The team adopted
feature-sliced design early — each feature lives in its own directory,
co-locating components, composables, types, and API calls:

```
src/
  features/
    loyalty-enrollment/
      LoyaltyEnrollmentForm.vue
      useLoyaltyEnrollment.ts
      loyaltyEnrollmentApi.ts
      types.ts
    messaging/
      MessagingInbox.vue
      MessageComposer.vue
      useMessaging.ts
      messagingApi.ts
      types.ts
    campaign-builder/
      CampaignBuilder.vue
      CampaignPreview.vue
      useCampaignBuilder.ts
      campaignApi.ts
      types.ts
      formatters.ts
```

The rationale is sound: everything related to loyalty enrollment lives
in one place. An engineer working on enrollment does not need to hunt
through a global `composables/` directory or a shared `types/`
folder. Open the feature directory, and the relevant code is right
there.

This works well for the first year.

Then a product requirement appears: the campaign builder needs to show
a preview of the loyalty enrollment widget, because campaigns can
include enrollment prompts. An engineer on the campaign team needs the
enrollment form component and its composable. Two paths present
themselves:

**Path one: import across slices.**

```typescript
// src/features/campaign-builder/CampaignPreview.vue
import LoyaltyEnrollmentForm from '../loyalty-enrollment/LoyaltyEnrollmentForm.vue'
import { useLoyaltyEnrollment } from '../loyalty-enrollment/useLoyaltyEnrollment'
```

This creates a hard dependency between two features that are otherwise
unrelated. The campaign builder now breaks if loyalty enrollment
refactors its internal composable. The import path reaches into
another feature's internals — there is no contract, no interface, no
indication in the loyalty enrollment directory that external consumers
exist. When the enrollment team renames `useLoyaltyEnrollment` to
`useEnrollmentFlow`, the campaign builder breaks silently (or loudly,
if the team is lucky enough to have caught the import in a build step).

Six months later, nine features import from loyalty enrollment's
internals. Nobody planned this. The feature directory that was
supposed to be a self-contained unit is now load-bearing
infrastructure with no API surface, no versioning, and no visibility
into who depends on what.

**Path two: copy and diverge.**

The engineer, aware that cross-slice imports are messy, copies the
enrollment form and composable into the campaign builder directory:

```
src/
  features/
    campaign-builder/
      CampaignPreview.vue
      CampaignEnrollmentForm.vue    # copied from loyalty-enrollment
      useCampaignEnrollment.ts      # copied, renamed
      ...
    loyalty-enrollment/
      LoyaltyEnrollmentForm.vue     # original
      useLoyaltyEnrollment.ts       # original
      ...
```

The copies are identical at first. A week later, the enrollment team
fixes a validation bug in `useLoyaltyEnrollment`. The fix does not
reach `useCampaignEnrollment` — nobody knows it exists. A month later,
the campaign team adds a feature flag to their copy. Now the two
implementations diverge in behavior but share a name concept, and a
QA engineer files a bug: "enrollment form behaves differently inside
campaigns."

The team discovers there are four copies of the enrollment composable
across different feature directories, each with subtly different
behavior, none aware of the others.

Neither path was malicious. Both were reasonable responses to a
structural constraint: co-location works brilliantly until something
is needed by more than one feature, and the file organization provides
no legitimate place for shared code to live. More precisely: the file
organization provides no *boundaries* — no definition of what is
internal to a feature and what is part of its public contract — and
so the team has no way to share code without violating boundaries that
were never drawn.

## What's wrong

The problem is not co-location itself. Grouping related code together
is a reasonable default. The problem is that feature-sliced design, as
commonly practiced, offers no answer to the question: **where does
code go when it outgrows its original feature?**

Every codebase has code at three levels of scope:

1. **Feature-private.** Used by one feature only. A composable that
   manages the internal state of a single form. A type definition
   consumed by one component.

2. **Shared.** Used by multiple features but specific to this
   application. A date formatter tuned to the platform's conventions.
   A notification composable that wraps the application's toast system.
   A customer type definition that multiple features reference.

3. **Infrastructure.** Generic utilities with no application-specific
   knowledge. HTTP clients, retry logic, validation helpers, logging
   wrappers.

Feature-sliced design handles level 1 well. Everything is local, easy
to find, easy to change. But it provides no structural home for levels
2 and 3. When code migrates from level 1 to level 2 — when a second
feature needs something that was private to the first — the engineer
faces the two bad choices described above: import across slices
(coupling) or copy (divergence).

The deeper issue is that the file tree is making a promise it cannot
keep. Feature-sliced design implies that each feature directory is
self-contained — a bounded module with no external dependencies except
the framework itself. But real applications are not composed of
isolated features. Features share domain concepts, display components,
API contracts, and formatting logic. A file structure that has no
place for shared code does not prevent sharing — it just makes sharing
invisible and uncontrolled. The feature directories have no boundaries
and no contracts. Everything is internal, so nothing is safe to depend
on, and yet everything gets depended on anyway.

## Predictable hierarchy

The alternative is a file organization with a conventional, universal
answer to "where does shared code go?" — a hierarchy that the entire
team knows, follows, and can navigate without asking.

The specific hierarchy matters less than its properties:

1. **Every piece of code has exactly one correct location.** An
   engineer should be able to answer "where does this belong?" without
   consulting a teammate or checking precedent.

2. **Shared code has a legitimate home.** When a composable outgrows
   its feature, there is a defined place to promote it to — not a
   judgment call, not a new directory invented for the occasion, but an
   existing, well-known layer.

3. **The hierarchy is universally adopted.** The worst outcome is a
   file structure that half the team follows and half ignores. A
   mediocre convention that everyone uses beats an elegant one that
   three engineers enforce and seven work around.

Several established approaches satisfy these properties. They differ
in terminology and emphasis, but they share the structural insight
that code at different levels of scope should live at different levels
of the hierarchy.

### Layered architecture

The simplest and most common form: separate directories by role.

```
src/
  components/          # UI components, shared across features
    enrollment/
      EnrollmentForm.vue
      EnrollmentFormField.vue
    messaging/
      MessageComposer.vue
      MessageThread.vue
    common/
      DataTable.vue
      Modal.vue
      Toast.vue
  composables/         # shared composables
    useEnrollment.ts
    useMessaging.ts
    useToast.ts
  services/            # API calls and business logic
    enrollmentService.ts
    messagingService.ts
    campaignService.ts
  types/               # shared type definitions
    customer.ts
    campaign.ts
    enrollment.ts
  utils/               # infrastructure-level utilities
    formatDate.ts
    httpClient.ts
    retry.ts
  views/               # page-level components (route targets)
    LoyaltyDashboard.vue
    CampaignEditor.vue
    MessagingCenter.vue
```

A component is in `components/`. A composable is in `composables/`. A
type is in `types/`. There is never ambiguity about where to put
something or where to find it. When the enrollment composable is
needed by campaigns, it is already in `composables/` — no cross-slice
import, no copy, no promotion ceremony.

The criticism of layered architecture is valid: it separates code by
technical role rather than by domain concept, which means understanding
a feature requires visiting multiple directories. This is a real cost.
But it is a cost paid at read time — you navigate across directories
to understand a feature — in exchange for a benefit at write time: you
never create invisible coupling, you never duplicate shared code, and
you never face the "where does this go?" question.

### Hexagonal architecture

Also called ports and adapters. The core idea: the application's
business logic lives at the center, with no dependencies on external
systems. External systems (databases, APIs, message queues, UI
frameworks) connect through defined ports — interfaces that the core
declares and the external systems implement.

```
src/
  core/                  # business logic, no framework imports
    domain/
      Customer.ts
      Campaign.ts
      EnrollmentPolicy.ts
    ports/
      CustomerRepository.ts    # interface
      MessagingGateway.ts      # interface
      CampaignStore.ts         # interface
    services/
      EnrollmentService.ts     # uses ports, not implementations
      CampaignService.ts
  adapters/              # implementations of ports
    api/
      HttpCustomerRepository.ts
      HttpMessagingGateway.ts
    store/
      PiniaCampaignStore.ts
  ui/                    # Vue components, composables
    components/
      EnrollmentForm.vue
      CampaignBuilder.vue
    composables/
      useEnrollment.ts   # calls core services
      useCampaign.ts
```

The locality question has a clear answer at every level. Domain logic
is in `core/domain/`. Interfaces to the outside world are in
`core/ports/`. Implementations of those interfaces are in `adapters/`.
UI is in `ui/`. When an engineer asks "where does the enrollment
policy live?", the answer is always `core/domain/`. When they ask
"where is the API implementation?", the answer is always `adapters/`.

The value of hexagonal architecture is not the port/adapter pattern
itself — it is the strict dependency rule. Code in `core/` never
imports from `adapters/` or `ui/`. Dependencies point inward. This
means the business logic is testable without a database, without an
HTTP client, without Vue. The file structure enforces this rule
visually: if you see an import from `adapters/` inside `core/`, it is
wrong, and it is obvious.

The cost is real: for a small application, this is ceremony. A CRUD
form that reads from an API and writes back does not benefit from an
abstracted port for the HTTP client. Hexagonal architecture pays off
when the business logic is complex enough that isolating it from
infrastructure genuinely simplifies reasoning — not before.

### Domain-Driven Design

DDD organizes code around bounded contexts — coherent areas of the
domain that have their own language, their own models, and their own
rules. Each bounded context is a self-contained unit with explicit
contracts at its boundaries.

```
src/
  domains/
    enrollment/
      model/
        EnrollmentPolicy.ts
        EnrollmentStatus.ts
      services/
        EnrollmentService.ts
      api/
        enrollmentApi.ts
      ui/
        EnrollmentForm.vue
        useEnrollment.ts
    messaging/
      model/
        Conversation.ts
        Message.ts
      services/
        MessagingService.ts
      api/
        messagingApi.ts
      ui/
        MessageComposer.vue
        useMessaging.ts
    shared/              # shared kernel
      types/
        Customer.ts
        Tenant.ts
      ui/
        DataTable.vue
        Modal.vue
      utils/
        formatDate.ts
```

This looks superficially similar to feature-sliced design — code is
grouped by domain concept. The critical difference is the `shared/`
directory (the "shared kernel" in DDD terminology): a named,
explicit, team-owned location for code that crosses domain
boundaries. When `Customer.ts` is needed by both enrollment and
messaging, it lives in `shared/types/` — not in one domain's
internals, imported by the other.

DDD also provides clear rules about cross-domain interaction. Domains
do not import each other's internals. If enrollment needs to know
about messaging state, it goes through a defined contract — an event,
a service interface, a shared type — not a direct import of
`messaging/model/Conversation.ts`. These rules are harder to enforce
than layered architecture's simpler convention, but they preserve
domain cohesion at scale.

The cost: DDD's conceptual overhead is significant. Bounded contexts,
aggregates, domain events, anti-corruption layers — the vocabulary is
large and the judgment calls are hard. For a team that does not have a
complex domain model (most CRUD-heavy frontend applications), DDD adds
organizational cost without commensurate benefit. It is the right tool
for systems where the domain itself is the hard part — where business
rules are complex, where different parts of the system genuinely use
different vocabularies for overlapping concepts.

## What the strategies share

The three approaches differ in emphasis and vocabulary, but they agree
on the structural properties that matter:

1. **Shared code has a defined home.** Layered architecture puts it in
   role-based directories. Hexagonal puts domain logic in `core/` and
   shared UI in `ui/`. DDD puts it in the shared kernel. The specific
   answer varies; the existence of an answer does not.

2. **Dependencies have direction.** Layered architecture is loose
   about this; hexagonal is strict (dependencies point inward); DDD
   enforces boundaries between domains. All three make cross-module
   coupling visible and intentional rather than accidental.

3. **Location is deterministic.** Given a piece of code and a
   description of what it does, the file structure tells you where it
   belongs. Two engineers, asked independently, should give the same
   answer.

4. **Boundaries are explicit and contracts are defined.** Every
   strategy draws a line between what is internal to a module and what
   is exposed to the rest of the system. Layered architecture does it
   implicitly through directory role. Hexagonal does it through ports.
   DDD does it through bounded context boundaries and the shared
   kernel. The mechanism varies, but the principle is constant: each
   unit of code has an inside and an outside, and the outside interacts
   only through the contract.

Feature-sliced design fails not because co-location is wrong, but
because it provides none of these properties for code that crosses
feature boundaries. The co-location is local optimization that
produces a global problem: shared code with no home, dependencies with
no direction, location that is a judgment call rather than a
convention, and boundaries that were never drawn.

## The discipline argument

All of this assumes the file structure is maintained. An impeccable
hexagonal architecture where half the team puts API calls in `core/`
because they are in a hurry is not hexagonal architecture — it is a
layered codebase with misleading directory names.

This leads to a practical observation that is easy to miss in the
pattern discussion: **a team with basic discipline will succeed with
almost any reasonable file organization strategy, and a team without
it will fail with all of them.**

The baseline discipline is not exotic:

**Right-size your files.** A 2,000-line component or a 40-method
service class is a problem in any file structure. When a file grows
past the point where its purpose can be stated in a sentence, split
it. The specific threshold does not matter; the habit of splitting
does.

**Name things so the file tree is self-documenting.** A directory
listing should tell an unfamiliar engineer what lives where without
opening files. `useEnrollmentValidation.ts` communicates more than
`helpers.ts`. `CustomerRepository.ts` communicates more than
`data.ts`. Naming is the cheapest form of documentation and the one
most likely to stay current.

**Delete dead code.** Commented-out blocks, unused imports, functions
retained "in case we need them later" — these are noise that
accumulates into confusion. Source control is the archive. If the code
is not called, remove it. If it is needed again, `git log` will find
it.

**Keep atomic units atomic.** One concept per file. One responsibility
per module. When a utility file grows to contain twelve unrelated
helper functions, the file structure is no longer communicating
anything — it is a junk drawer with a label.

**Use source control as your safety net.** Engineers hoard code —
commented-out alternatives, unused feature flags, defensive copies of
functions they are refactoring — because deleting feels risky. Source
control eliminates this risk entirely. Every deleted line is
recoverable. Every previous version is inspectable. Leaning on this
fact is what makes aggressive cleanup safe.

A team that does these things consistently will be productive in a
layered architecture, a hexagonal architecture, a DDD structure, or
even a feature-sliced design where cross-slice imports are managed
through explicit re-exports. A team that does not will accumulate
2,000-line god components, `helpers.ts` files with thirty unrelated
functions, and dead code that nobody is sure is dead — regardless of
the directory structure printed on the whiteboard.

This is not an argument against having a strategy. It is an argument
that the strategy is necessary but not sufficient. The file tree is a
set of conventions. Conventions require enforcement — through code
review, through linting rules where possible, through team norms.
The hierarchy provides the answer to "where does this go?" The
discipline provides the answer to "will we actually put it there?"

## When co-location is right

Co-location is not the mistake. Unprincipled co-location is the
mistake. There are contexts where grouping by feature is the correct
choice:

**Small applications.** A project with five components and three
composables does not benefit from a four-layer hierarchy. Put
everything in a flat structure, revisit when it grows. The threshold
where structure pays for itself is higher than most teams think.

**Genuinely independent features.** A plugin system where each plugin
is truly self-contained — no shared state, no shared components, no
cross-plugin imports — is well served by co-location. The key word is
"truly": if plugins share a theme system, a notification mechanism, or
a data layer, they are not independent, and the shared code needs a
home outside the plugin directories.

**Prototyping.** When the goal is to validate an idea quickly and the
code will be rewritten or discarded, organizational strategy is
overhead. Co-locate everything, move fast, impose structure when the
prototype graduates to production code.

**Monorepo packages.** In a monorepo where each package is published
independently with its own `package.json`, co-location within
packages is natural — the package boundary *is* the hierarchy. Shared
code lives in a shared package with explicit versioning. The
monorepo structure provides what feature-sliced design lacks: a
real module system with real dependency declarations.

## Boundaries and contracts

Everything above — the file structure strategies, the discipline
habits, the co-location trade-offs — is in service of a deeper skill
that separates competent engineering from excellent engineering:
**knowing where to draw boundaries and what contracts to enforce at
them.**

A boundary is a decision about what is inside a unit and what is
outside it. A contract is the agreement about how the outside
interacts with the inside. The unit can be a function, a module, a
service, a package, a deployment — the scale changes, the principle
does not. Inside the boundary, the code maintains its own coherence:
its own invariants, its own data structures, its own internal
organization. Outside the boundary, everything is an abstraction —
a function signature, a type definition, an API schema, an event
payload. The consumer does not know or care how the internals work.
It cares only that the contract holds.

This is the actual lesson of every file organization strategy
discussed on this page. Layered architecture works because the layers
are boundaries — components do not reach into services' internals,
services do not reach into the data layer's internals. Hexagonal
architecture works because the ports are contracts — the core declares
what it needs, and the adapters fulfill it. DDD works because the
bounded contexts are boundaries with explicit contracts at every
crossing point. Feature-sliced design fails because there are no
boundaries at all — everything is internal, everything is reachable,
and the "contract" between features is whatever import path someone
happened to write.

### Where boundaries go wrong

Most serious defects at scale trace back to one of three boundary
failures:

**Boundaries in the wrong place.** A boundary drawn at the wrong
level of abstraction creates friction everywhere. A service that
wraps a single database table and exposes every column as an
individual getter is not a useful boundary — it is a pass-through
that adds indirection without abstraction. A module that bundles
unrelated functionality behind one interface forces consumers to
depend on things they do not use. The boundary should be drawn where
the system's natural seams are — where change on one side does not
require change on the other. Finding those seams requires
understanding the execution flow and the real-world usage patterns,
not just the class diagram.

**Missing boundaries.** Code that has never been segmented at all —
a 3,000-line service that handles authentication, authorization, user
management, and audit logging with no internal structure. The absence
of a boundary means every change risks every behavior. No part of the
code can be reasoned about independently because no part has been
defined as independent. This is the state that most god objects are in
when the team finally notices: not that the boundaries were drawn
wrong, but that they were never drawn.

**Broken contracts.** Two modules that agreed on an interface and then
drifted. A service that returns a different shape than its consumers
expect. A function that silently changes its error-reporting behavior.
A module that starts writing to state that its contract says is
read-only. The boundary still exists on paper — the interface file is
still there, the type definition has not changed — but the actual
behavior no longer matches. This is the most dangerous failure mode
because it is invisible until it produces a defect in production, and
the defect is often far from the broken contract in both code and
time.

### Why there are no universal rules

There is no formula for where to draw boundaries. The right boundary
depends on the domain, the team, the scale, the rate of change, and
the specific trade-offs the system faces. A boundary that is correct
for a team of five shipping a monolith is wrong for a team of fifty
operating a distributed system. A boundary that is correct today may
be wrong in six months when the product pivots.

What exists instead of rules are strategies learned through practice:

- **Draw boundaries where change is independent.** If two pieces of
  code change for different reasons, at different times, driven by
  different stakeholders, they belong on opposite sides of a boundary.
  This is Separation of Concerns applied to spatial organization.

- **Draw contracts at trust boundaries.** Where data enters your
  module from outside — user input, API responses, event payloads,
  function arguments from code you do not control — validate it.
  Inside the boundary, trust your own invariants. This avoids the
  defensive programming trap of validating everything everywhere.

- **Let the system tell you where the seams are.** The files that
  change together in version control are probably inside the same
  boundary. The files that change independently are probably on
  opposite sides of one. The import that keeps breaking when
  someone refactors is probably crossing a boundary that should have
  a contract. Real usage patterns reveal structure that design
  documents miss.

- **Prefer explicit contracts over implicit ones.** An `index.ts`
  that re-exports the module's public API is an explicit contract — it
  declares what is stable. A bare directory where every file is
  importable is an implicit contract — everything is public, nothing
  is stable. The explicit version costs one file; the implicit version
  costs ongoing maintenance of every import path in every consumer.

### The system-level view

If atomic containers maintain internal coherence — each module's
internals are consistent, well-named, right-sized, and free of dead
code — and every part of the system fulfills its boundary contracts —
the interfaces hold, the types match, the behaviors are as documented
— then the system works. Not because the organizational strategy is
perfect, but because the contracts are honored and the boundaries are
in the right places.

The serious problems at scale — the ones that produce production
outages, data corruption, and multi-week debugging efforts — are
almost always boundary and contract failures. A misplaced `if`
statement inside a well-bounded module is a bug; a broken contract
between two modules is an architectural defect. Unit tests exist
to catch the first kind. Boundaries and contracts exist to prevent
the second kind from being possible.

This is why the choice between layered architecture, hexagonal
architecture, and DDD matters less than the discussion often implies.
Each strategy is a different answer to "where do the boundaries go?"
and "what do the contracts look like?" The strategies provide
vocabulary and starting positions. The actual skill is recognizing,
in a specific codebase with specific pressures, where the seams are
and what promises need to be made across them. That skill is not
teachable through rules. It is developed through practice, through
getting it wrong and paying the cost, through studying systems that
got it right and understanding why.

### Encapsulation as entailed consequence

If the preceding assertions are accepted — that boundaries should be
drawn at natural seams, that contracts should be explicit, that each
module should maintain internal coherence — then encapsulation is not
an additional principle to argue for. It is an inescapable consequence
of those principles taken seriously.

Encapsulation means that only the interface is exposed. The internal
implementation — the data structures, the algorithms, the helper
functions, the state management — is private to the boundary. The
module's consumers interact with the contract and nothing else. This
is least privilege applied to code architecture: a consumer is given
access to exactly what it needs (the interface) and nothing more (the
internals).

The stability advantage is direct. If only interfaces are exposed,
then internal implementations can be updated, refactored, rewritten,
or optimized within their own boundaries without risk to consumers.
The contract holds; the internals change freely. A module can replace
its database query with a cache lookup, rewrite a recursive algorithm
as an iterative one, swap a dependency for a faster alternative — none
of this is visible to the outside, none of it breaks callers, none of
it requires coordinated changes across the codebase.

The moment a design pushes you to pry open the internals of a
self-contained module — to reach past its interface and depend on how
it works rather than what it promises — you are introducing coupling
where none should exist. This is not a judgment call. It is not a
trade-off to be evaluated. If the boundary was correctly drawn and the
contract is sufficient, reaching past it is always wrong. If the
contract is *not* sufficient — if a consumer genuinely needs something
the interface does not provide — the correct response is to extend the
contract, not to bypass it.

This distinction is what makes encapsulation violations qualitatively
different from other design decisions. Most of the guidance on this
page involves trade-offs: co-location vs. hierarchy, layered vs.
hexagonal, when to extract vs. when to inline. Reasonable engineers
disagree, and the right answer depends on context. Encapsulation is
not in this category. If the premises hold — boundaries exist,
contracts are defined, modules maintain internal coherence — then the
advantages of encapsulation are not a position to be argued. They are
a certainty that follows from the premises. And the pitfalls of
violating encapsulation — invisible coupling, fragile dependencies,
implementations that cannot change without coordinated rewrites — are
not risks to be weighed. They are consequences that are guaranteed to
arrive.

## Boundary violations in practice

Rails is instructive here because its conventions actively shape where
code lands — and the three most common boundary violations in Rails
codebases are direct consequences of the framework's opinions being
taken as complete architectural guidance rather than starting
positions.

### The fat model

The community mantra "fat model, skinny controller" was a correction
to an earlier anti-pattern (business logic in controllers) that
overcorrected into a different failure mode. The advice to move logic
into the model was sound. The failure was treating the model as the
*only* alternative.

```ruby
class Customer < ApplicationRecord
  belongs_to :tenant
  has_many :orders
  has_many :loyalty_transactions
  has_many :messages
  has_many :external_identifiers

  scope :active, -> { where(deactivated_at: nil) }
  scope :enrolled, -> { where(enrolled: true) }
  scope :messageable, -> { joins(:external_identifiers).where(external_identifiers: { source: :messaging, active: true }) }

  validates :email, presence: true, uniqueness: { scope: :tenant_id }
  validates :phone, phone_format: true, if: :phone_changed?

  before_save :normalize_phone
  before_save :enforce_tenant_messaging_rules
  after_save :sync_to_crm, if: :saved_change_to_email?
  after_save :recalculate_loyalty_tier, if: :tier_relevant_change?
  after_commit :enqueue_welcome_sequence, if: :just_enrolled?

  def display_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  def eligible_for_promotion?(promotion)
    return false unless enrolled?
    return false if promotion.tier_restricted? && loyalty_tier < promotion.minimum_tier
    return false if promotion.channel == :sms && !messageable?
    !promotion.redeemed_by?(self)
  end

  def loyalty_tier
    LoyaltyTierCalculator.new(self).current_tier
  end

  def messageable?
    external_identifiers.active.where(source: :messaging).exists?
  end

  def enroll!(enrolled_by:)
    update!(enrolled: true, enrolled_at: Time.current, enrolled_by: enrolled_by)
  end

  def deactivate!(reason:)
    update!(deactivated_at: Time.current, deactivation_reason: reason)
    orders.pending.each(&:cancel!)
    CrmSync.push_deactivation(self)
  end

  private

  def normalize_phone
    self.phone = PhoneNormalizer.normalize(phone) if phone_changed?
  end

  def enforce_tenant_messaging_rules
    # 40 lines of tenant-specific conditional logic
  end

  def tier_relevant_change?
    saved_change_to_enrolled? || saved_change_to_deactivated_at?
  end

  def just_enrolled?
    saved_change_to_enrolled? && enrolled?
  end
end
```

This model is the boundary for everything customer-related — which
means it is the boundary for nothing. Identity, policy, side effects,
presentation logic, enrollment workflow, deactivation workflow, loyalty
tier calculation, and CRM integration all live behind a single class
interface. The boundary is too wide: it encompasses concerns that
change for different reasons at different rates, and it offers no
contract to consumers beyond "call any public method and hope the
callbacks do not surprise you."

The model's boundary should be identity and persistence — the data
that defines who this customer is. Policy (eligibility, tier
calculation) belongs behind its own boundary. Workflows (enrollment,
deactivation) belong behind theirs. The model can participate in all
of these as a data source, but it should not *be* all of these.

### The computing view

```erb
<% @customers.select { |c| c.enrolled? && c.loyalty_tier >= 2 }.each do |customer| %>
  <tr class="<%= customer.orders.where('created_at > ?', 30.days.ago).any? ? 'active' : 'inactive' %>">
    <td><%= customer.display_name %></td>
    <td><%= customer.orders.sum(:total_cents) / 100.0 %></td>
    <td>
      <% if customer.external_identifiers.active.where(source: :messaging).exists? %>
        <%= link_to "Send Message", new_message_path(customer_id: customer.id) %>
      <% end %>
    </td>
    <td><%= customer.loyalty_transactions.where(type: :earn).sum(:points) - customer.loyalty_transactions.where(type: :redeem).sum(:points) %></td>
  </tr>
<% end %>
```

The template is filtering, querying, computing, and making decisions.
It is running N+1 queries (each customer's orders, external
identifiers, and loyalty transactions are loaded individually). It
contains business logic — the definition of "active" (ordered within
30 days), the messageable check, the points balance calculation —
that will be duplicated when the same information appears on another
page.

The boundary between "what to show" and "how to decide what to show"
does not exist. The view has absorbed the controller's filtering
responsibility and the model's computation responsibility. When the
definition of "active customer" changes, an engineer must search
templates — not models, not services — to find where the logic lives.

The contract of a view is straightforward: given pre-computed data,
render it. The view should not ask questions about the data; it should
receive answers. A presenter, a view model, a serializer, a
controller that does its job — any of these can fulfill the contract.
The specific mechanism matters less than the boundary: computation
happens before the template, not inside it.

### The non-idempotent controller

```ruby
class EnrollmentsController < ApplicationController
  def create
    @customer = Customer.find(params[:customer_id])

    if @customer.tenant.requires_double_opt_in?
      token = SecureRandom.urlsafe_base64(32)
      PendingEnrollment.create!(customer: @customer, token: token, expires_at: 24.hours.from_now)
      EnrollmentMailer.confirmation_email(@customer, token).deliver_later
    else
      @customer.update!(enrolled: true, enrolled_at: Time.current, enrolled_by: current_user)
      CrmSync.push(@customer)
      MessagingProvider.provision(@customer)
      LoyaltyService.initialize_account(@customer)
      WelcomeSequence.enqueue(@customer)
      AuditLog.record(:enrollment_created, customer: @customer, actor: current_user)
    end

    redirect_to customer_path(@customer), notice: "Enrollment initiated"
  rescue MessagingProvider::ProvisioningError => e
    @customer.update!(enrolled: false)
    CrmSync.push(@customer)
    redirect_to customer_path(@customer), alert: "Enrollment failed: #{e.message}"
  end
end
```

The controller is orchestrating a multi-step workflow: conditional
branching on tenant policy, writing to multiple models, calling
external services, handling partial failures with manual rollback.
If the `MessagingProvider` call fails after the CRM sync succeeded,
the system is in an inconsistent state that the rescue block tries to
unwind — but `LoyaltyService.initialize_account` may have already
executed, and there is no rollback for that.

The contract of a controller action is: receive a request, dispatch
to the domain, return a response. It is a driver — it translates HTTP
into a domain operation and translates the result back into HTTP. When
a controller becomes the orchestrator, it takes on responsibilities
that belong to the domain layer: sequencing, error handling, state
management, rollback logic. The next engineer who needs to enroll a
customer from a different entry point (a background job, an API
endpoint, a console script) cannot reuse this logic because it is
embedded in an HTTP request handler.

The boundary is clear: the controller should call one thing — an
enrollment operation — and let that operation own its internal
sequencing, its error handling, and its consistency guarantees. The
controller decides *whether* to enroll (authentication, authorization,
parameter validation). It does not decide *how*.

### The service layer trap

The instinct after seeing these anti-patterns is to reach for a
service layer — extract the logic from the model, the view, and the
controller into service objects. This is not wrong. It is incomplete.

```ruby
class CustomerEnrollmentService
  def enroll(customer, enrolled_by:)
    # ...the logic from the controller, moved here
  end
end

class CustomerEligibilityService
  def eligible_for_promotion?(customer, promotion)
    # ...the logic from the model, moved here
  end
end

class CustomerPresenterService
  def dashboard_data(customers)
    # ...the computation from the view, moved here
  end
end
```

Taken to its conclusion, a codebase accumulates dozens of service
objects and the models, views, and controllers become perfunctory
pass-throughs. The logic that was scattered is now centralized — in a
`services/` directory that grows without structure, where
`CustomerEnrollmentService` calls `CustomerEligibilityService` calls
`LoyaltyTierService` calls `ExternalIdentifierService`. The services
have become the new models — fat, coupled, and boundary-less.

The service layer is not a boundary strategy. It is a *relocation*
strategy. It moves code from one place to another without answering
the boundary question: what is inside this service, what is outside,
and what is the contract? A service with fifteen public methods and
dependencies on eight other services has the same structural problem
as a model with fifteen concerns — the boundary is too wide and the
contract is too diffuse.

The alternative is simpler and less dramatic: **let each layer perform
its role.** The model stores state and enforces data integrity — not
policy, not workflows, not side effects. The view renders pre-computed
data — not queries, not business logic, not conditional filtering. The
controller dispatches to the domain — not orchestrates, not sequences,
not handles partial failure. When a workflow is complex enough to
warrant its own object, that object has a single responsibility, a
narrow boundary, and a clear contract: "given these inputs, perform
this operation and return this result." It is not a "service" in the
generic sense; it is a named operation with defined boundaries.

The discipline is not "extract everything into services." The
discipline is "keep each boundary narrow enough that its contract can
be stated in a sentence, and keep each layer focused on the role it
was designed for."

## Questions to ask

1. When a piece of code is needed by a second feature, where does it
   go? If the answer requires a team discussion, the file structure
   has a gap.
2. Can two engineers, asked independently, put the same new file in
   the same directory? If not, the hierarchy is not deterministic
   enough.
3. How many cross-directory imports exist that reach into another
   module's internals rather than through a public API? Each one is
   invisible coupling — a dependency with no contract.
4. How many near-duplicate files exist in different directories? Each
   pair is a copy-paste decision that will produce divergent behavior
   over time.
5. For each module in the system: can you state what its boundary is
   and what contract it offers to consumers? If not, the module has
   no boundary — it is an open surface that anything can depend on in
   any way.
6. When a contract between two modules last changed, did the consumers
   update? If nobody knows, the contract is not being enforced — it
   is a suggestion.
7. When a new engineer joins the team, how long before they can
   navigate the file tree without asking where things are? That
   interval is a direct measure of how well the conventions
   communicate.
