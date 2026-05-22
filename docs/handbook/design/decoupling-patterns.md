# Decoupling Patterns

## Problem statement

A payment processing platform supports three payment methods: credit
card, ACH bank transfer, and store credit. Each method has different
validation rules, different API calls to external providers, different
fee calculations, and different receipt formats. The initial
implementation is straightforward:

```python
def process_payment(order, method, details):
    if method == "credit_card":
        if not details.get("card_number") or not details.get("expiry"):
            raise ValidationError("Card number and expiry required")
        if details.get("amount", 0) > 10000:
            raise ValidationError("Credit card limit exceeded")

        response = stripe_client.charge(
            amount=order.total_cents,
            card=details["card_number"],
            expiry=details["expiry"],
            cvv=details["cvv"],
        )
        fee = order.total_cents * 0.029 + 30
        receipt = f"Card ending {details['card_number'][-4:]}: ${order.total_cents / 100:.2f}"

    elif method == "ach":
        if not details.get("routing_number") or not details.get("account_number"):
            raise ValidationError("Routing and account numbers required")

        response = plaid_client.initiate_transfer(
            amount=order.total_cents,
            routing=details["routing_number"],
            account=details["account_number"],
        )
        fee = min(order.total_cents * 0.008, 500)
        receipt = f"ACH transfer from account ending {details['account_number'][-4:]}: ${order.total_cents / 100:.2f}"

    elif method == "store_credit":
        balance = get_store_credit_balance(order.customer_id)
        if balance < order.total_cents:
            raise ValidationError("Insufficient store credit")

        response = deduct_store_credit(order.customer_id, order.total_cents)
        fee = 0
        receipt = f"Store credit: ${order.total_cents / 100:.2f}"

    else:
        raise ValueError(f"Unknown payment method: {method}")

    record_transaction(order, method, response, fee)
    send_receipt(order.customer, receipt)
    return response
```

This is 45 lines and perfectly readable. A junior engineer can trace
every path. The `else` clause catches unknown methods with an explicit
error. For three payment methods, this is arguably the right
implementation — any further abstraction would be premature.

Then the platform grows.

Payment method four arrives: PayPal. Method five: Apple Pay. Method
six: cryptocurrency. Method seven: buy-now-pay-later through a
partner. Each one adds another `elif` block with its own validation,
its own API client, its own fee calculation, its own receipt format.
The function is now 200 lines.

Then the variations multiply within each method. Credit cards need
different processing for different card networks (Visa, Mastercard,
Amex) because the interchange fees differ. ACH needs same-day vs.
standard settlement paths. BNPL has different terms depending on the
partner. Each variation adds nested conditionals inside the existing
`elif` blocks:

```python
    elif method == "credit_card":
        # ...validation...
        if card_network(details["card_number"]) == "amex":
            fee = order.total_cents * 0.035 + 30
            if order.total_cents > 5000:
                fee += 50  # high-value Amex surcharge
        elif card_network(details["card_number"]) == "visa":
            fee = order.total_cents * 0.029 + 30
            if order.customer.is_preferred:
                fee = order.total_cents * 0.025 + 30
        elif card_network(details["card_number"]) == "mastercard":
            # ...
```

The function is now 400 lines. It processes payments, but it is no
longer readable, no longer testable in isolation, and no longer safe
to modify. Adding payment method eight requires reading and
understanding methods one through seven to ensure the new block does
not interfere with existing logic. A bug fix to the Amex fee
calculation requires navigating a 400-line function to find the right
nested conditional. A change to receipt formatting requires touching
every branch.

The function is doing one conceptual thing — processing a payment —
but it is doing it by *enumerating every possible case*. The `if`/
`elif` chain is a manual dispatch table maintained by the programmer.
Every new case is a modification to the function. Every modification
risks every existing case.

## The first refactor: extract and name

The team's first instinct is to extract each branch into its own
function:

```python
def process_payment(order, method, details):
    if method == "credit_card":
        return process_credit_card(order, details)
    elif method == "ach":
        return process_ach(order, details)
    elif method == "store_credit":
        return process_store_credit(order, details)
    elif method == "paypal":
        return process_paypal(order, details)
    elif method == "apple_pay":
        return process_apple_pay(order, details)
    elif method == "crypto":
        return process_crypto(order, details)
    elif method == "bnpl":
        return process_bnpl(order, details)
    else:
        raise ValueError(f"Unknown payment method: {method}")
```

This is better — each method's logic is isolated in its own function,
testable independently, and modifiable without reading the others. But
the dispatch is still manual. Adding method eight still requires
editing `process_payment`. The `else` clause still exists because the
function has no way to know at runtime which methods are available.
The function is a hard-coded routing table.

## The class hierarchy attempt

The next evolution introduces classes. Each payment method gets its
own class with a common interface:

```python
class CreditCardProcessor:
    def validate(self, details):
        if not details.get("card_number") or not details.get("expiry"):
            raise ValidationError("Card number and expiry required")

    def process(self, order, details):
        self.validate(details)
        response = stripe_client.charge(
            amount=order.total_cents,
            card=details["card_number"],
            expiry=details["expiry"],
            cvv=details["cvv"],
        )
        return response

    def calculate_fee(self, order, details):
        return order.total_cents * 0.029 + 30

    def format_receipt(self, order, details):
        return f"Card ending {details['card_number'][-4:]}: ${order.total_cents / 100:.2f}"


class ACHProcessor:
    def validate(self, details):
        if not details.get("routing_number") or not details.get("account_number"):
            raise ValidationError("Routing and account numbers required")

    def process(self, order, details):
        self.validate(details)
        response = plaid_client.initiate_transfer(
            amount=order.total_cents,
            routing=details["routing_number"],
            account=details["account_number"],
        )
        return response

    def calculate_fee(self, order, details):
        return min(order.total_cents * 0.008, 500)

    def format_receipt(self, order, details):
        return f"ACH transfer from account ending {details['account_number'][-4:]}: ${order.total_cents / 100:.2f}"


class StoreCreditProcessor:
    # ...same shape, different implementation
    pass
```

Each processor encapsulates its own validation, API interaction, fee
logic, and receipt formatting. This is a genuine improvement: each
class has a defined boundary, a clear contract (four methods), and
internal coherence. A change to ACH processing does not risk credit
card processing.

But the dispatch problem remains:

```python
def process_payment(order, method, details):
    if method == "credit_card":
        processor = CreditCardProcessor()
    elif method == "ach":
        processor = ACHProcessor()
    elif method == "store_credit":
        processor = StoreCreditProcessor()
    elif method == "paypal":
        processor = PayPalProcessor()
    # ...seven more elif blocks...
    else:
        raise ValueError(f"Unknown payment method: {method}")

    processor.validate(details)
    response = processor.process(order, details)
    fee = processor.calculate_fee(order, details)
    receipt = processor.format_receipt(order, details)
    record_transaction(order, method, response, fee)
    send_receipt(order.customer, receipt)
    return response
```

The branching has moved from "what to do for each method" to "which
class to instantiate for each method" — but it is still a manual
dispatch on a string. The `else` clause is still there. Adding a new
payment method still requires editing this function. The classes are
well-structured, but the system that *selects* them is the same
hand-maintained routing table.

This is where many codebases stop. The team has clean classes, each
with a clear interface, and a central dispatch function that maps
strings to classes. It works. It is maintainable enough. The dispatch
function is ugly but small.

But it is also where a subtle problem takes root.

## The string-matching disease

The dispatch function maps method names (strings) to processor
classes. Other parts of the codebase need to make decisions based on
payment method too. The reporting module needs to know which methods
are refundable. The admin panel needs to display method-specific
configuration. The webhook handler needs to route provider callbacks
to the right processor.

Each of these call sites faces the same question: given a method name
string, what should I do? And each one answers it the same way:

```python
# In the reporting module
def is_refundable(method):
    if method == "credit_card":
        return True
    elif method == "ach":
        return True
    elif method == "store_credit":
        return False
    elif method == "paypal":
        return True
    elif method == "crypto":
        return False
    elif method == "bnpl":
        return False
    else:
        return False

# In the admin panel
def get_config_fields(method):
    if method == "credit_card":
        return ["api_key", "webhook_secret", "capture_mode"]
    elif method == "ach":
        return ["plaid_client_id", "plaid_secret", "settlement_speed"]
    elif method == "paypal":
        return ["client_id", "client_secret", "sandbox_mode"]
    # ...

# In the webhook handler
def route_webhook(provider, payload):
    if provider == "stripe":
        return CreditCardProcessor().handle_webhook(payload)
    elif provider == "plaid":
        return ACHProcessor().handle_webhook(payload)
    elif provider == "paypal":
        return PayPalProcessor().handle_webhook(payload)
    # ...
```

The string-matching dispatch, which was contained in one function, has
metastasized. Every module that touches payment methods has its own
`if`/`elif` chain matching the same strings to the same concepts.
When payment method eight arrives, an engineer must find and update
every one of these scattered switch statements — and the compiler
will not help, because strings have no type system. Forgetting one
produces a silent default (`return False`, `return []`) or a runtime
error that surfaces only when a user selects the new payment method
in a specific context.

The class hierarchy exists. The processors are well-defined. But the
*system does not use them as types.* It uses them as passive
containers that are selected by string matching at every call site.
The classes have behaviors that should be queried polymorphically —
"are you refundable?", "what are your config fields?" — but instead
the calling code answers those questions itself, by checking the
method name string and hard-coding the answer.

This is the worst of both worlds: the ceremony of a class hierarchy
with none of the polymorphic dispatch benefit.

## The registry: letting the system discover behavior

The fix is to eliminate the string-matching dispatch entirely. Instead
of a function that maps strings to classes, the system maintains a
registry that classes populate themselves:

```python
from abc import ABC, abstractmethod


class PaymentProcessor(ABC):
    _registry: dict[str, type["PaymentProcessor"]] = {}

    def __init_subclass__(cls, method_name: str = "", **kwargs):
        super().__init_subclass__(**kwargs)
        if method_name:
            PaymentProcessor._registry[method_name] = cls

    @classmethod
    def for_method(cls, method: str) -> "PaymentProcessor":
        processor_class = cls._registry.get(method)
        if not processor_class:
            raise ValueError(
                f"Unknown payment method: {method}. "
                f"Available: {', '.join(cls._registry)}"
            )
        return processor_class()

    @classmethod
    def available_methods(cls) -> list[str]:
        return list(cls._registry.keys())

    @abstractmethod
    def validate(self, details: dict) -> None: ...

    @abstractmethod
    def process(self, order, details: dict): ...

    @abstractmethod
    def calculate_fee(self, order, details: dict) -> int: ...

    @abstractmethod
    def format_receipt(self, order, details: dict) -> str: ...

    @property
    @abstractmethod
    def refundable(self) -> bool: ...

    @property
    @abstractmethod
    def config_fields(self) -> list[str]: ...

    @property
    @abstractmethod
    def provider_name(self) -> str: ...
```

Each processor registers itself by declaring its method name:

```python
class CreditCardProcessor(PaymentProcessor, method_name="credit_card"):
    provider_name = "stripe"
    refundable = True
    config_fields = ["api_key", "webhook_secret", "capture_mode"]

    def validate(self, details):
        if not details.get("card_number") or not details.get("expiry"):
            raise ValidationError("Card number and expiry required")

    def process(self, order, details):
        self.validate(details)
        return stripe_client.charge(
            amount=order.total_cents,
            card=details["card_number"],
            expiry=details["expiry"],
            cvv=details["cvv"],
        )

    def calculate_fee(self, order, details):
        return order.total_cents * 0.029 + 30

    def format_receipt(self, order, details):
        return f"Card ending {details['card_number'][-4:]}: ${order.total_cents / 100:.2f}"


class ACHProcessor(PaymentProcessor, method_name="ach"):
    provider_name = "plaid"
    refundable = True
    config_fields = ["plaid_client_id", "plaid_secret", "settlement_speed"]

    def validate(self, details):
        if not details.get("routing_number") or not details.get("account_number"):
            raise ValidationError("Routing and account numbers required")

    def process(self, order, details):
        self.validate(details)
        return plaid_client.initiate_transfer(
            amount=order.total_cents,
            routing=details["routing_number"],
            account=details["account_number"],
        )

    def calculate_fee(self, order, details):
        return min(order.total_cents * 0.008, 500)

    def format_receipt(self, order, details):
        return f"ACH transfer from account ending {details['account_number'][-4:]}: ${order.total_cents / 100:.2f}"


class StoreCreditProcessor(PaymentProcessor, method_name="store_credit"):
    provider_name = "internal"
    refundable = False
    config_fields = []

    def validate(self, details):
        pass  # validated at process time against live balance

    def process(self, order, details):
        balance = get_store_credit_balance(order.customer_id)
        if balance < order.total_cents:
            raise ValidationError("Insufficient store credit")
        return deduct_store_credit(order.customer_id, order.total_cents)

    def calculate_fee(self, order, details):
        return 0

    def format_receipt(self, order, details):
        return f"Store credit: ${order.total_cents / 100:.2f}"
```

The dispatch function becomes trivial:

```python
def process_payment(order, method, details):
    processor = PaymentProcessor.for_method(method)
    processor.validate(details)
    response = processor.process(order, details)
    fee = processor.calculate_fee(order, details)
    receipt = processor.format_receipt(order, details)
    record_transaction(order, method, response, fee)
    send_receipt(order.customer, receipt)
    return response
```

No `if`/`elif`. No `else`. No string matching. The function does not
know which payment methods exist. It does not need to. It asks the
registry for a processor, and the processor provides everything the
system needs through a defined interface.

The scattered string-matching call sites disappear:

```python
# Reporting — was a 20-line if/elif chain
def is_refundable(method):
    return PaymentProcessor.for_method(method).refundable

# Admin panel — was a 15-line if/elif chain
def get_config_fields(method):
    return PaymentProcessor.for_method(method).config_fields

# Webhook routing — was a 10-line if/elif chain
def route_webhook(provider, payload):
    for processor_class in PaymentProcessor._registry.values():
        if processor_class.provider_name == provider:
            return processor_class().handle_webhook(payload)
    raise ValueError(f"Unknown provider: {provider}")
```

Adding payment method eight requires one action: writing a new class
that subclasses `PaymentProcessor` with the appropriate
`method_name`. No existing code changes. No dispatch function to
update. No scattered string-matching sites to find and extend. The
new processor registers itself by existing — `__init_subclass__` runs
when the class is defined, and the registry updates automatically.

## What changed

The progression from the original function to the registry is not
about adding abstraction for its own sake. Each step addressed a
specific failure mode:

**Extract and name** addressed readability — each method's logic in
its own function, independently understandable.

**Class hierarchy** addressed encapsulation — each method's
validation, processing, fees, and receipts behind a single boundary
with a defined contract.

**Registry** addressed dispatch — the system discovers available
methods at runtime rather than enumerating them in a hard-coded
routing table.

The critical transition is the last one, because it changes the
*character* of the system. The branching versions — whether functions
or classes — are *declarative*: the programmer has listed every
possible case and coded the response to each. The registry version is
*adaptive*: the system does not know its own capabilities at write
time. It discovers them at runtime by inspecting what has been
registered. A new capability appears by being defined, not by being
added to an enumeration.

This is the distinction between a program that *selects* behavior and
a system that *resolves* behavior. Selection requires the programmer
to anticipate every case. Resolution requires only that each case
conform to a contract.

## Beyond the registry

The registry pattern is one mechanism. The underlying principle —
**replace enumeration with resolution** — manifests in several forms
depending on the language and the problem.

### Dispatch tables

When the behavior associated with each case is a single function
rather than a class with multiple methods, a dictionary is sufficient:

```python
FEE_CALCULATORS: dict[str, Callable[[Order], int]] = {
    "credit_card": lambda order: order.total_cents * 0.029 + 30,
    "ach": lambda order: min(order.total_cents * 0.008, 500),
    "store_credit": lambda _: 0,
}

def calculate_fee(order, method):
    calculator = FEE_CALCULATORS.get(method)
    if calculator is None:
        raise ValueError(f"No fee calculator for method: {method}")
    return calculator(order)
```

The dispatch table is still manually maintained, but the dispatch is
data rather than control flow. Adding a new entry is adding a line to
a dictionary, not adding a branch to a function. The dictionary is
inspectable, iterable, and testable as data — you can verify at
startup that every registered payment method has a corresponding fee
calculator.

### Decorators as registration

Python decorators make registration explicit at the definition site:

```python
WEBHOOK_HANDLERS: dict[str, Callable] = {}

def handles_webhook(provider: str):
    def decorator(func):
        WEBHOOK_HANDLERS[provider] = func
        return func
    return decorator

@handles_webhook("stripe")
def handle_stripe_webhook(payload):
    # ...process Stripe event

@handles_webhook("plaid")
def handle_plaid_webhook(payload):
    # ...process Plaid event

def route_webhook(provider, payload):
    handler = WEBHOOK_HANDLERS.get(provider)
    if handler is None:
        raise ValueError(f"No handler for provider: {provider}")
    return handler(payload)
```

The decorator pattern makes the registration visible at the point
where the handler is defined. An engineer reading `handle_stripe_
webhook` sees immediately that it is registered as the Stripe webhook
handler. The routing function does not need to know which handlers
exist.

### Protocol-based dispatch

Python's `Protocol` (from `typing`) allows structural typing — a
class satisfies a protocol if it has the right methods, without
needing to inherit from a base class:

```python
from typing import Protocol, runtime_checkable


@runtime_checkable
class Refundable(Protocol):
    def refund(self, transaction_id: str, amount: int) -> dict: ...
    def refund_deadline(self, transaction_id: str) -> datetime | None: ...


def attempt_refund(processor, transaction_id, amount):
    if not isinstance(processor, Refundable):
        raise TypeError(f"{type(processor).__name__} does not support refunds")
    deadline = processor.refund_deadline(transaction_id)
    if deadline and datetime.now() > deadline:
        raise RefundError("Refund deadline has passed")
    return processor.refund(transaction_id, amount)
```

The `Refundable` protocol defines a contract without requiring
inheritance. A processor is refundable if it implements `refund` and
`refund_deadline` — regardless of its class hierarchy, regardless of
whether it was designed with refunds in mind. This is capability
discovery: the system asks "can you do this?" rather than checking
"are you on the list of things that can do this?"

The distinction matters when the set of capabilities is not known at
design time. A processor written by a third-party plugin can be
refundable without the core system knowing about it — it just needs to
implement the protocol.

### Event-driven dispatch

When the response to a condition is not a single function call but a
coordination across multiple subsystems, events replace direct
dispatch:

```python
class PaymentEventBus:
    def __init__(self):
        self._listeners: dict[str, list[Callable]] = {}

    def subscribe(self, event_type: str, handler: Callable):
        self._listeners.setdefault(event_type, []).append(handler)

    def publish(self, event_type: str, payload: dict):
        for handler in self._listeners.get(event_type, []):
            handler(payload)


event_bus = PaymentEventBus()

event_bus.subscribe("payment.completed", update_order_status)
event_bus.subscribe("payment.completed", send_receipt_email)
event_bus.subscribe("payment.completed", sync_to_accounting)
event_bus.subscribe("payment.failed", notify_customer)
event_bus.subscribe("payment.failed", log_failure_metrics)
```

No call site decides what should happen when a payment completes.
The event bus resolves the handlers at runtime based on what has
subscribed. Adding a new reaction to `payment.completed` — say,
updating a real-time dashboard — is adding a subscription, not
modifying the payment processing code.

Event-driven dispatch introduces genuine complexity: ordering
guarantees, error handling (does one failed handler prevent others
from running?), debugging (the execution path is no longer visible
in a stack trace). These costs are real and they are the reason
event-driven architecture is not the default answer. But for systems
where multiple independent subsystems must react to the same
condition, events eliminate the coordination code that would otherwise
live in a central orchestrator — the function that calls
`update_order_status` and then `send_receipt_email` and then
`sync_to_accounting` and must be edited every time a new reaction is
added.

## When to stop

Every pattern in this progression adds indirection. Indirection has
a cost: the execution path is less visible, debugging requires
understanding the dispatch mechanism, and a new engineer must learn
the registration/resolution system before they can trace behavior.

The original 45-line function with three `elif` branches had no
indirection cost. An engineer could read it top to bottom and know
exactly what happened for every payment method. That directness has
genuine value, and losing it is a real price paid for the ability to
extend the system without modifying existing code.

The heuristic is not "always use a registry" or "always use events."
It is: **the dispatch mechanism should match the rate of change.**

**Low rate of change:** Three payment methods that have been stable
for two years. The `elif` chain is fine. The cost of indirection is
not justified by the nonexistent cost of modifying the dispatch.

**Moderate rate of change:** A new payment method every few months,
integrated by the core team. A class hierarchy with a simple registry
gives each method its own boundary and makes adding a new one
mechanical. The dispatch function does not need to be a registry — a
dictionary mapping strings to classes, maintained alongside the
classes, is sufficient.

**High rate of change:** Payment methods added by external partners
via a plugin system, with capabilities that vary (some support
refunds, some do not). Protocol-based dispatch and a self-registering
class hierarchy let the system discover capabilities without the core
code knowing what plugins exist.

**Coordination across subsystems:** Multiple independent modules must
react to payment events, and the set of reactions changes
independently of the payment processing code. Event-driven dispatch
decouples the reactions from the trigger.

The mistake is reaching for the sophisticated mechanism before the
simpler one has failed. A registry for three stable payment methods is
over-engineering. An `elif` chain for twenty payment methods added by
external partners is under-engineering. The right mechanism is the one
whose complexity matches the problem's complexity — no more, no less.

## The testing signal

Testing is often treated as an afterthought — something bolted on
after the design is complete. But testability is one of the strongest
signals that a design's boundaries are correctly drawn. If a component
cannot be tested without scaffolding the entire system around it, the
component does not have real boundaries. Its implementation has leaked
into its dependencies, or its dependencies have leaked into it, and
the test is forced to reproduce the entire entangled context to
exercise any single behavior.

### The untestable design

Consider a Rails controller that enrolls a customer. The controller
sets attribute accessor flags on the model to control which callbacks
fire, because the model's callback chain triggers different side
effects depending on the context of the save:

```ruby
class EnrollmentsController < ApplicationController
  def create
    @customer = Customer.find(params[:customer_id])
    @customer.skip_crm_sync = true
    @customer.skip_messaging_provision = false
    @customer.enrolled_by_admin = current_user.admin?
    @customer.suppress_welcome_email = params[:silent].present?
    @customer.enrolled = true
    @customer.enrolled_at = Time.current
    @customer.save!
    redirect_to customer_path(@customer)
  end
end
```

Testing this controller requires:

- A real (or carefully mocked) database with a customer record, a
  tenant, and tenant configuration
- The `Customer` model's full callback chain to be loaded, because the
  test must verify which callbacks fired and which were suppressed
- External service stubs for CRM, messaging provider, and email
  delivery — because any callback that was *not* suppressed will call
  them
- Tenant fixture data, because some callbacks are conditional on
  tenant configuration
- Knowledge of which `attr_accessor` flags interact — does
  `skip_crm_sync` affect the audit log callback? Does
  `enrolled_by_admin` change the welcome email logic?

```ruby
RSpec.describe EnrollmentsController, type: :controller do
  let(:tenant) { create(:tenant, messaging_enabled: true, double_opt_in: false) }
  let(:customer) { create(:customer, tenant: tenant, enrolled: false) }

  before do
    stub_crm_sync
    stub_messaging_provider
    stub_email_delivery
    sign_in(create(:admin_user))
  end

  it "enrolls the customer" do
    post :create, params: { customer_id: customer.id }
    customer.reload
    expect(customer.enrolled).to be true
    expect(customer.enrolled_at).to be_present
  end

  it "skips CRM sync" do
    expect(CrmSync).not_to receive(:push)
    post :create, params: { customer_id: customer.id }
  end

  it "does not skip messaging provision" do
    expect(MessagingProvider).to receive(:provision)
    post :create, params: { customer_id: customer.id }
  end

  it "suppresses welcome email when silent" do
    expect(WelcomeMailer).not_to receive(:enrollment_email)
    post :create, params: { customer_id: customer.id, silent: "1" }
  end
end
```

The test must know the *internals* of the model — which flags suppress
which side effects — to verify the controller's behavior. When a new
callback is added to the model, every controller test that saves a
customer must be re-evaluated: does the new callback need a new flag?
Does the existing flag configuration accidentally trigger or suppress
it?

The complexity grows exponentially. If there are five flags and ten
controllers that save customers, each with different flag
configurations, the interaction matrix is fifty cells — each of which
represents a potential bug when any callback changes. The `attr_
accessor` flags are the symptom. The disease is that the controller
is reaching into the model's internal state-management mechanism to
control behavior that should not be the controller's responsibility.

### Dependency injection as design discipline

The fix is not "write better tests." The fix is a design that does
not require the test to reproduce the entangled context. Dependency
injection is the mechanism, but the value is not testability alone —
it is the design discipline that DI enforces.

Returning to the payment processor example in Python:

```python
class PaymentWorkflow:
    def __init__(
        self,
        processor: PaymentProcessor,
        transaction_store: TransactionStore,
        receipt_sender: ReceiptSender,
        event_bus: EventBus,
    ):
        self.processor = processor
        self.transaction_store = transaction_store
        self.receipt_sender = receipt_sender
        self.event_bus = event_bus

    def execute(self, order, details):
        self.processor.validate(details)
        response = self.processor.process(order, details)
        fee = self.processor.calculate_fee(order, details)

        self.transaction_store.record(
            order=order,
            method=self.processor.method_name,
            response=response,
            fee=fee,
        )

        receipt = self.processor.format_receipt(order, details)
        self.receipt_sender.send(order.customer, receipt)
        self.event_bus.publish("payment.completed", {"order_id": order.id})

        return response
```

Every dependency is explicit. The workflow does not instantiate its own
transaction store, does not know which receipt delivery mechanism is in
use, does not reach into a global event bus. It receives what it needs
through its constructor.

Testing with an in-memory substitute:

```python
class InMemoryTransactionStore:
    def __init__(self):
        self.transactions = []

    def record(self, order, method, response, fee):
        self.transactions.append({
            "order_id": order.id,
            "method": method,
            "response": response,
            "fee": fee,
        })


class InMemoryReceiptSender:
    def __init__(self):
        self.sent = []

    def send(self, customer, receipt):
        self.sent.append({"customer": customer, "receipt": receipt})


class InMemoryEventBus:
    def __init__(self):
        self.published = []

    def publish(self, event_type, payload):
        self.published.append({"type": event_type, "payload": payload})


def test_payment_workflow_records_transaction():
    store = InMemoryTransactionStore()
    sender = InMemoryReceiptSender()
    bus = InMemoryEventBus()
    processor = StoreCreditProcessor()

    workflow = PaymentWorkflow(
        processor=processor,
        transaction_store=store,
        receipt_sender=sender,
        event_bus=bus,
    )

    order = Order(id=1, total_cents=5000, customer=Customer(id=1))
    workflow.execute(order, {})

    assert len(store.transactions) == 1
    assert store.transactions[0]["fee"] == 0
    assert store.transactions[0]["method"] == "store_credit"


def test_payment_workflow_publishes_event():
    store = InMemoryTransactionStore()
    sender = InMemoryReceiptSender()
    bus = InMemoryEventBus()
    processor = StoreCreditProcessor()

    workflow = PaymentWorkflow(
        processor=processor,
        transaction_store=store,
        receipt_sender=sender,
        event_bus=bus,
    )

    order = Order(id=1, total_cents=5000, customer=Customer(id=1))
    workflow.execute(order, {})

    assert len(bus.published) == 1
    assert bus.published[0]["type"] == "payment.completed"
```

No database. No external service stubs. No mocking framework. No
setup that must be re-evaluated when an unrelated component changes.
The in-memory array is as effective as a transactional database for
verifying the workflow's behavior — because the workflow's contract
with `TransactionStore` is "call `record` with these arguments." It
does not care how `record` is implemented. An array, a PostgreSQL
table, a Redis stream — the workflow behaves identically.

### The canary

The in-memory substitutes work *because the boundary is honored.* The
workflow interacts with `TransactionStore` through a defined interface
— `record(order, method, response, fee)` — and never reaches past it.

The moment a design starts to depend on a dependency's internal state,
the in-memory substitute breaks:

```python
# This test would fail with InMemoryTransactionStore
def test_transaction_ordering():
    store = InMemoryTransactionStore()
    # ...
    workflow.execute(order_1, {})
    workflow.execute(order_2, {})

    # BAD: depending on auto-increment IDs from the store
    assert store.transactions[1]["id"] > store.transactions[0]["id"]

    # BAD: depending on the store's timestamp behavior
    assert store.transactions[0]["recorded_at"] < store.transactions[1]["recorded_at"]

    # BAD: depending on the store's deduplication logic
    workflow.execute(order_1, {})  # same order again
    assert len(store.transactions) == 2  # expects store to deduplicate
```

Each of these assertions depends on behavior that belongs to the
*store's internals* — auto-increment sequencing, timestamp
generation, deduplication logic. The in-memory array does not
implement these because they are not part of the contract. The test
failure is the canary: it signals that the workflow has coupled itself
to implementation details that it has no business knowing about.

This is why testability is a design signal, not just a testing
concern. When a test requires elaborate setup, mocked internal state,
or knowledge of a dependency's implementation to pass, the code under
test has a boundary violation. The test is not too hard to write —
the design is too entangled to test.

### Factories and builders

Dependency injection solves the wiring problem — how does the
`PaymentWorkflow` get its dependencies? In a test, the answer is
obvious: the test constructs them. In production, the answer is a
factory:

```python
class PaymentWorkflowFactory:
    def __init__(self, config):
        self.config = config

    def build(self, method: str) -> PaymentWorkflow:
        processor = PaymentProcessor.for_method(method)
        return PaymentWorkflow(
            processor=processor,
            transaction_store=PostgresTransactionStore(self.config.db_url),
            receipt_sender=self._build_receipt_sender(),
            event_bus=RabbitMQEventBus(self.config.amqp_url),
        )

    def _build_receipt_sender(self):
        if self.config.receipt_mode == "email":
            return EmailReceiptSender(self.config.smtp_config)
        elif self.config.receipt_mode == "sms":
            return SmsReceiptSender(self.config.twilio_config)
        return NoOpReceiptSender()
```

The factory centralizes construction decisions. The workflow does not
know whether it is talking to PostgreSQL or an in-memory array. It
does not know whether receipts go by email or SMS. It does not know
whether events go to RabbitMQ or a test bus. The factory decides, and
the workflow operates against the contract.

For complex object graphs where construction has multiple steps,
conditional logic, or shared dependencies, the builder pattern
provides a fluent construction interface:

```python
class PaymentWorkflowBuilder:
    def __init__(self):
        self._processor = None
        self._store = None
        self._sender = None
        self._bus = None

    def with_processor(self, processor):
        self._processor = processor
        return self

    def with_store(self, store):
        self._store = store
        return self

    def with_receipt_sender(self, sender):
        self._sender = sender
        return self

    def with_event_bus(self, bus):
        self._bus = bus
        return self

    def build(self):
        return PaymentWorkflow(
            processor=self._processor,
            transaction_store=self._store or InMemoryTransactionStore(),
            receipt_sender=self._sender or NoOpReceiptSender(),
            event_bus=self._bus or NoOpEventBus(),
        )
```

The builder makes construction explicit and composable. A test that
only cares about transaction recording can build a workflow with
defaults for everything else:

```python
def test_fee_calculation():
    store = InMemoryTransactionStore()
    workflow = (
        PaymentWorkflowBuilder()
        .with_processor(CreditCardProcessor())
        .with_store(store)
        .build()
    )
    order = Order(id=1, total_cents=10000, customer=Customer(id=1))
    workflow.execute(order, {"card_number": "4111111111111111", "expiry": "12/27", "cvv": "123"})

    assert store.transactions[0]["fee"] == 10000 * 0.029 + 30
```

### Production-optimized, not test-optimized

The factory and builder patterns are not testing utilities. They are
production architecture. The factory that wires `PostgresTransaction
Store` in production and `InMemoryTransactionStore` in tests is the
same factory that wires `SmsReceiptSender` for one tenant and
`EmailReceiptSender` for another. The builder that lets tests omit
irrelevant dependencies is the same builder that lets a background job
construct a workflow without a receipt sender because the job does not
send receipts.

The design is production-optimized. The testability is a consequence,
not a goal. When a system is built from components with explicit
dependencies and defined contracts, testing becomes simple because
the design *is* simple — each component does one thing, receives what
it needs, and is agnostic to how those needs are fulfilled.

This reinforces strict boundaries in a way that no other practice
does. If a dependency's internal state starts to become part of your
implementation — if you find yourself checking the database's
auto-increment counter, or relying on the event bus's ordering
guarantee, or depending on the receipt sender's retry logic — the
in-memory substitute surfaces the violation immediately. The test
fails not because the test is wrong but because the code has reached
past a boundary.

It also promotes idempotency naturally. When your component receives
its dependencies rather than reaching for global state, it is less
tempted to depend on *where* in a sequence it runs. It processes the
order it is given, records the transaction it is told to record,
sends the receipt it is told to send. Whether it runs first or last,
once or twice, in a test or in production — the behavior is the same,
because the behavior depends only on the inputs and the contracts, not
on accumulated state in systems it does not control.

Thinking back to the Rails `attr_accessor` pattern: the controller
that sets five flags before saving a customer is a controller that has
absorbed knowledge of the model's internal callback orchestration. It
cannot be tested without reproducing that orchestration. It cannot be
reasoned about without understanding which flags interact. Every new
controller that saves a customer must learn the flag protocol —
which flags to set, in which combination, for which context. The
complexity grows exponentially with the number of controllers and
models, because each controller-model pair represents a unique
configuration of internal state that must be held in the programmer's
head.

The DI-based design eliminates this entirely. The enrollment workflow
receives its dependencies. The controller calls the workflow. The
controller does not know what the workflow does internally — it does
not set flags, does not suppress callbacks, does not configure
internal state. It provides inputs and receives outputs. If the
enrollment workflow changes its internal behavior — adds a new side
effect, removes an old one, reorders its operations — no controller
changes. The boundary holds. The contract holds. The system remains
composable.

## The living system

There is a qualitative difference between a program that enumerates
its behaviors and a system that discovers them.

The enumerating program is fully specified at write time. Every case
is known, every response is coded, every path is visible in the
source. This is the `if`/`elif` chain, the `match`/`case` statement,
the hard-coded dispatch table. It is easy to read, easy to debug, and
easy to reason about — as long as the set of cases is small and
stable. When the set grows or changes frequently, the enumerating
program requires modification at every extension point and risks
every existing behavior with each modification.

The discovering system is specified at write time only in terms of
contracts. The actual behaviors are resolved at runtime from whatever
has been registered, subscribed, or implemented. The source code does
not contain a list of payment methods — it contains the rules for what
a payment method must provide. The system handles payment method
eight not because a programmer added an eighth branch, but because an
eighth class conformed to the contract and the system found it.

This is where programming transitions from pure computation — take
these inputs, apply these rules, produce this output — to something
that behaves more like a living system. The individual components are
simple: each processor validates, processes, calculates fees, and
formats receipts. The emergent behavior — a payment platform that
handles any method conforming to its contract, routes webhooks from
any provider, and coordinates reactions across independent
subsystems — arises from the composition of those components through
defined interfaces.

The skill is not knowing the patterns. The patterns are well
documented, widely taught, and straightforward to implement. The skill
is recognizing the moment when a system's rate of change has outgrown
its dispatch mechanism — when the `elif` chain that was fine last year
is now a liability, when the class hierarchy that was sufficient is
now missing a capability-discovery layer, when the direct function
calls that were clear are now a coordination bottleneck. That
recognition comes from experience: from maintaining systems that grew
past their dispatch mechanisms and paying the cost, from watching a
well-placed registry eliminate an entire category of bugs, from
over-engineering a simple system with events and watching the
debugging cost exceed the extension cost it was supposed to eliminate.

There are no rules for this. There are patterns, guidelines, and
hard-learned judgment about when each tool earns its keep. The
preceding pages established the vocabulary: Separation of Concerns
identifies what should be apart, Locality determines where it lives,
and this page addresses how the parts communicate once they are
separated. The thread that runs through all three is the same
question, asked at different scales: **what code belongs together, and
what code belongs apart?** The decoupled system's answer is: the parts
belong apart, the contract belongs between them, and the system's
behavior emerges from honoring those contracts at runtime.

## Questions to ask

1. How many `if`/`elif` or `match`/`case` chains in the codebase
   dispatch on the same value? Each duplicate chain is a maintenance
   liability — when a new case arrives, every chain must be found and
   updated.
2. When a new variant is added (a new payment method, a new
   notification channel, a new report type), how many files change?
   If the answer is more than one or two, the dispatch mechanism is
   too distributed.
3. Do the classes in the system carry behavior that is queried
   polymorphically, or are they passive containers selected by
   external string matching? If the calling code checks the type name
   and hard-codes the answer, the class hierarchy is ceremony.
4. Does the system know its own capabilities? Can it enumerate what
   payment methods are available, what webhook providers are
   supported, what report types exist — without a hard-coded list
   somewhere?
5. Is the dispatch mechanism's complexity proportional to the
   problem's rate of change? A registry for three stable variants is
   over-engineering. An `elif` chain for twenty dynamic variants is
   under-engineering.
6. When an unexpected input arrives — a payment method the system has
   never seen, a webhook from an unknown provider — does the system
   produce a clear, diagnosable error, or does it fall through a
   default branch silently?
