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
