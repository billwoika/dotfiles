# The Case Against Least Privilege

## A disclaimer

This page argues against a principle that is considered foundational
to information security, is a requirement for compliance frameworks
like SOC 2, and is endorsed by virtually every security professional
in the industry. The author is aware of how unorthodox this position
is. The argument is not that access controls are unnecessary or that
sensitive data should be unprotected. The argument is that the
*implementation* of least privilege as practiced in most organizations
today produces outcomes that are the opposite of what the principle
intends — and that the industry has mistaken the implementation for
the principle.

Read the full argument before dismissing it. The position is narrower
than the title suggests.

## The principle and its implementation

The principle of least privilege states that a user, process, or
system should have only the minimum access necessary to perform its
function. In its original formulation, this is sound. A web
application should not run as root. A database connection pool should
not use a superuser account. A deployment pipeline should not have
write access to every production resource in the organization.

Nobody is arguing with that.

What the industry has done is extend this principle from *systems* to
*people*, and from *write access to production* to *read access to
everything*. The result is an access model where a software engineer
at a company with two hundred microservices must file a use-case-
justified ticket to gain read access to an individual GitHub
repository. There are hundreds of these repositories. Some that
DevOps insists are retired are actively running in production. Nobody
knows to look at them because nobody knows they exist.

Here is what this looks like in practice. A team lead is tasked with
remediating a failing service. Centralized logs reference a service
name. The team lead files a ticket for read access to the repository
behind that service. The ticket is reviewed by a systems
administrator whose title was updated to reflect a cultural shift
toward DevOps — not someone who performs development work or
evaluates code. This person is not qualified to judge whether the
repository in question is the one that underlies the service the team
lead is trying to fix. Some of the repositories they insist are
retired are actively running in production. The default posture is
"no." A team lead — someone the organization trusts to lead engineers,
make architectural decisions, and take responsibility for production
systems — cannot get read access to a repository, archived or
otherwise, without a use-case justification evaluated by someone who
cannot evaluate the use case.

This is not security. This is organizational amnesia enforced by
policy.

## Known knowns, known unknowns, and unknown unknowns

Donald Rumsfeld's taxonomy — whatever one thinks of its original
context — is a precise description of the access problem:

**Known knowns.** The engineer knows the service exists and knows how
it works. They have access to the repository, the dashboards, the
logs. They can diagnose issues, understand dependencies, and make
informed changes. This is the state every organization claims to want.

**Known unknowns.** The engineer knows the service exists but does not
have access to see how it works. They know there is a payment
processing service. They do not have access to the repository,
cannot read the code, cannot see the logs. When their service
interacts with it and something breaks, they file a ticket and wait.
The knowledge exists in the organization — it is just inaccessible to
the person who needs it right now.

**Unknown unknowns.** The engineer does not know the service exists.
It was built by a team that has since been reorganized, maintained by
an engineer who has since left, and runs on infrastructure that no
current team member has visibility into. It processes data that feeds
into a downstream system that the engineer's service depends on. When
it breaks, nobody knows where to look — because nobody knew it was
there.

Least privilege as currently practiced moves organizations from the
first state toward the second and third. Every access restriction
that prevents an engineer from reading a non-sensitive repository is
a small step toward unknown unknowns. The aggregate effect is an
organization where the people who build the software cannot see the
software they are building.

The IAM paradox makes this worse: to request access, you must know
what to request. To know what to request, you need enough visibility
to understand what exists. When that visibility is itself gated behind
access controls, the engineer cannot even articulate which permissions
they need. They are locked out of the information required to
describe the information they are locked out of.

## What this costs

### Knowledge silos

When read access to code, dashboards, and non-production
environments is restricted to the team that owns each service, the
organization creates hard boundaries around institutional knowledge.
The payment team understands payments. The enrollment team
understands enrollment. Nobody understands how payments and
enrollment interact — or rather, three people do, and when two of
them leave, the organization discovers that its access controls have
also been knowledge-retention controls, and they retained nothing.

There is no better disinfectant than sunlight. An engineer who can
browse the codebase, read other teams' services, see how data flows
through the system — that engineer develops a mental model of the
organization's software that no onboarding document can provide. An
engineer who can only see their own team's repositories develops a
mental model that ends at the team boundary. When the system fails
at the boundary (and it will — see [The Layers](layers.md)), the
engineer with the broader model diagnoses it in an hour. The engineer
without it files a ticket and waits for a rotation.

### The elitist architecture

Least privilege as practiced creates a two-tier engineering culture.
The first tier — senior engineers, team leads, infrastructure
engineers, the people who designed the access policies — have broad
access. They can see the full system, read any repository, access
any dashboard. They designed the access model, so they gave
themselves the access they needed. The second tier — everyone else —
sees only what has been explicitly granted to them, one ticket at a
time.

The first tier does not experience the friction. They do not wait for
access approvals. They do not discover that the dashboard they need
requires a ticket to a team they have never heard of. They do not
spend twenty minutes filing a request form to read a configuration
file. Because they do not experience it, they do not know it is
happening. When the second tier raises the issue, it sounds like
complaining about a minor inconvenience — because from the first
tier's perspective, access is easy. They have it.

This is not a security architecture. It is a caste system with a
compliance justification.

### Growth suppression

Most web developers are not working on state secrets. They are
building enrollment flows, dashboard components, API integrations,
reporting features. Making these engineers jump through hoops to
learn more about how their software works — to see it in action, to
understand how users interact with it, to discover friction points
they could address — is the opposite of nurturing a sustainable
growth mindset.

A junior engineer who reads a senior engineer's service
implementation learns patterns they would not encounter for years
otherwise. A frontend engineer who can read the API service's code
understands why the response is shaped the way it is, instead of
treating the backend as a black box and filing a ticket when the
shape changes. A platform engineer who can see the application code
understands what the applications actually need, instead of building
infrastructure based on a requirements document that was out of date
when it was written.

Every access restriction on non-sensitive resources is a small tax
on curiosity. Each individual restriction is minor. The aggregate
is an organization that actively discourages engineers from being
active participants — from taking an interest in the shared codebase,
from understanding the system they are part of, from growing beyond
their assigned scope.

### The feedback loop that never closes

Organizations that do not provide engineers with access to
production-sourced, de-identified data — in aggregation dashboards,
in logging pipelines, in performance monitoring — will never produce
well-optimized software. This is not a matter of discipline or
talent. It is a structural impossibility. Engineers who cannot see
the accumulation of their design choices cannot learn from them.

A database query that scans a full table is invisible to the
engineer who wrote it if they cannot see production query metrics. A
UI flow that users abandon at step three is invisible to the
engineer who designed it if they cannot see production analytics. An
API endpoint that responds in 200ms under development load and 4
seconds under production load is invisible to the engineer who built
it if they cannot see production latency dashboards. In each case
the engineer ships code, receives no signal about its real-world
behavior, and moves on to the next feature — repeating the same
mistakes because the feedback that would correct them is locked
behind an access request.

De-identification solves the PII concern. Aggregation solves the
individual-record concern. The technology for providing production
feedback without exposing sensitive data has existed for years. The
obstacle is not technical — it is the reflexive application of least
privilege to dashboards and log streams that contain no sensitive
data after de-identification. The result is engineers who design in
the dark and organizations that wonder why production performance
degrades quarter over quarter despite hiring talented people.

## The failure mode

The most dangerous failure mode of aggressive least privilege is
invisible: the incident that takes eight hours instead of one
because the engineer who could have diagnosed it did not have access
to the logs, the dashboard, or the repository that would have shown
them the root cause. This failure never appears in a post-mortem as
"access controls slowed the response." It appears as "it took time
to identify the affected service" or "the on-call engineer was
unfamiliar with the upstream dependency." The access model is never
named as a contributing factor because the people writing the
post-mortem have access and do not think to ask whether others do
not.

The second failure mode is organizational: people leave. When three
engineers own the institutional knowledge for a critical service,
and that knowledge is not distributed because nobody else can see
the code, any departure becomes a knowledge crisis. The organization
did not lose the code — it lost the *understanding* of the code. The
code is right there in the repository. Nobody else has ever read it.
The bus factor is not a hypothetical. It is a direct consequence of
access policies that prevent knowledge from distributing naturally.

The third failure mode is the one the access ticket scenario
illustrates in full: the infrastructure itself becomes an unknown
unknown. Services that operations marks as retired continue running
in production. Nobody discovers this because nobody can see them —
and the people who review access requests are not in a position to
know the difference. The organization's own software becomes
invisible to the organization. This is not a security posture. It
is an organization that has lost track of what it runs.

## What least privilege should mean

The argument is not for a free-for-all. It is for a different
interpretation of the same principle — one that applies the
restriction where the risk actually lives.

**Restrict write access aggressively.** Nobody is arguing that
junior engineers should force-push to production, that every
engineer needs `DROP DATABASE` privileges, or that deployment
credentials should be broadly distributed. Write access to
production systems, PII-containing data stores, and infrastructure
configuration should be tightly controlled, audited, and justified.
This is where least privilege earns its keep.

**Default read access to open.** Source code, non-production
environments, internal dashboards, architecture documentation, log
streams for non-PII services, CI/CD pipeline configurations — these
should be readable by any engineer in the organization by default.
The burden should be on restricting access, not on granting it. An
engineer should not need to file a ticket to read a repository.
They should need to file a ticket to be *excluded* from one that
contains genuinely sensitive material.

**Distinguish data sensitivity from system sensitivity.** A
repository that contains application code for an enrollment flow is
not sensitive. A repository that contains cryptographic key material
is. An S3 bucket that contains anonymized analytics data is not
sensitive. An S3 bucket that contains customer PII is. Applying the
same access model to both treats all information as equally
dangerous, which means the controls are too tight for the common
case and — because people work around controls that are too tight —
often too loose for the sensitive case.

**Fix the IAM paradox.** Publish a service catalog. Make the list of
what exists readable by everyone. An engineer who can see that a
`payment-reconciliation` service exists and can read its README is
an engineer who can make an informed access request. An engineer who
does not know it exists cannot request anything — and when their
service starts failing because `payment-reconciliation` changed its
output format, they discover its existence during an incident,
which is the worst possible time.

## The compliance reality

SOC 2, ISO 27001, HIPAA, PCI DSS — these frameworks require access
controls. They require documentation of who has access to what. They
require the principle of least privilege. This page is not arguing
that these requirements are invalid or that organizations should
ignore them.

The argument is that compliance frameworks describe *outcomes*, not
*implementations*. SOC 2 requires that access is appropriate to the
role. It does not require that a software engineer cannot read source
code. The auditor asks "who has access to production data?" — not
"who can read the enrollment service's repository?" The gap between
what compliance requires and what organizations implement is filled
by risk aversion, and that risk aversion has costs that are never
measured because they are invisible: slower incident response,
knowledge loss, reduced engineering growth, organizational fragility.

An organization that defaults read access to open, restricts write
access aggressively, and classifies data by actual sensitivity is
compliant. It is also more resilient, because its engineers
understand the software they build.

## When this argument is wrong

This page has advocated strongly for broad read access. Here is
where the position breaks down:

- **Regulated industries with data classification requirements.**
  Healthcare, financial services, government contracting — these
  have legal requirements about who can see what, and those
  requirements may extend to source code that processes regulated
  data. The argument for broad read access does not override legal
  obligations.

- **Genuinely sensitive material.** Cryptographic implementations,
  security tooling, fraud detection logic — there are legitimate
  reasons to restrict read access to code that would enable an
  attacker if leaked. The argument is against *reflexive*
  restriction, not against *justified* restriction.

- **Large organizations with adversarial threat models.** A company
  with 50,000 employees and nation-state threat actors has a
  different risk calculus than a company with 200 engineers building
  a SaaS product. The cost-benefit analysis shifts at scale.

- **Contractor and vendor access.** External parties with temporary
  access to internal systems have a different trust profile than
  full-time employees. Restricting their read access is reasonable
  in ways that restricting an employee's is not.

The principle is not "all access, all the time." The principle is:
*default to visibility, restrict where the risk is real, and measure
the cost of restriction as carefully as you measure the cost of
access.*

## Working within the system

Regulatory environments are unlikely to change soon, and the likely
reader of this page is not in a position to rewrite their
organization's ACL policies. The arguments above are worth making
when the opportunity arises — in architecture reviews, in
post-mortems, in one-on-ones with leadership. But in the meantime,
there is practical work to be done within the system as it exists.

### Make access requests undeniable

When requesting write or execute access to a resource, always
provide an artifact: a reproduction of the error, an email thread,
a link to the ticket, a screenshot of the log line that references
the service. Cite identifiers that can be cross-referenced — ticket
numbers, incident IDs, service names from centralized logging. The
goal is to make the request self-evident to the reviewer, even if
the reviewer is not in a position to evaluate the technical merits
independently.

Frame requests as user stories. "As an engineer working on
PROJ-4821, I need read access to the `payment-reconciliation`
repository so I can identify the source of the malformed response
referenced in the attached error log." This format works because it
answers the three questions every access reviewer is implicitly
asking: who is requesting, why do they need it, and what will they
do with it. It also creates a paper trail that satisfies the
compliance requirement the reviewer is enforcing.

### Scope strategically

The more narrowly scoped a request, the less access it will produce.
This is a trade-off. When expediency matters — when an incident is
active, when a deadline is close — keep the request limited and
narrow: one repository, one dashboard, one log stream. The approval
comes faster because the reviewer's risk assessment is simpler.

When expediency is less pressing, broader framing can be more
effective. A request to "view and aggregate datasets necessary to
perform the essential elements of the role" — backed by a job
description or a manager's endorsement — establishes a standing
justification that applies to future requests, not just the current
one. The first approval is harder. The second and third are easier,
because a precedent exists.

This is not cynicism. It is the well-studied foot-in-the-door
phenomenon: once someone grants access, they are more likely to view
the decision as correct and extend it further. Each successful
request recalibrates the reviewer's sense of what is normal for the
role. An engineer who has been granted access to twelve repositories
without incident is a lower-risk approval for the thirteenth than an
engineer requesting their first. Build the pattern deliberately.

### Document what you find

When access is granted and the work reveals something useful —
a dependency nobody knew about, a service marked as retired that is
still active, a configuration that explains a recurring incident —
document it where others can find it. The strongest argument for
broad access is evidence that broad access produces organizational
knowledge. Every time an engineer discovers something valuable
because they could see a resource, that discovery is a data point
in the case for changing the policy.

## Questions to ask

1. Can every engineer in the organization read the source code for
   every service their code interacts with? If not, what is the
   security justification — not the compliance justification, the
   *security* justification — for preventing it?
2. When was the last time an access restriction measurably prevented
   a security incident? When was the last time it measurably slowed
   one down?
3. How many engineers in the organization could explain, without
   looking it up, which services run in production? If the answer is
   "a few senior engineers," the access model has created a
   knowledge monopoly.
4. What is the mean time to gain read access to a repository or
   dashboard? If it is measured in days, the access model is a
   bottleneck masquerading as a control.
5. If three specific engineers left the organization tomorrow, which
   services would become unknown unknowns? The answer reveals where
   the access model has concentrated knowledge instead of
   distributing it.
