# Customization

The framework's source uses a small set of placeholder strings that
should be substituted when forking. They were chosen to be distinctive
enough to grep without colliding with unrelated content.

## The placeholder convention

| Placeholder | Used for | Substitute with |
|-------------|----------|-----------------|
| `zftadvancements` | Org name, repo paths, kebab-case identifiers | Your org's slug |
| `zftadvancements.com` | Email domain, public URLs | Your org's domain |
| `zftadvancements.internal` | Internal infrastructure suffix | Your internal-network suffix |
| `bastion.zftadvancements.internal` | Specific bastion host | Your bastion host |
| `staging-db.zftadvancements.internal` | Specific internal DB host | Your staging DB host |
| `billwoika.com` | Personal domain | Your personal domain |
| `dev@zftadvancements.com` | Work email / git identity | Your work email |
| `you@billwoika.com` | Personal email / git identity | Your personal email |
| `your-username` | SSH user, GitHub username | Your username |

## Why these specific strings

Distinctive real strings (`zftadvancements`, `billwoika`) are easier to
find-and-replace than generic placeholders precisely because they
don't collide with anything else. A `sed` pass replacing `zftadvancements`
with `acme` will only touch the framework's placeholder text, not
something inside an unrelated config or comment.

The personal placeholders (`your-username`, `you@billwoika.com`) use
distinctive forms that don't appear naturally in technical content.
After substituting org names, a second pass on the personal
placeholders is clean.

## Substitution recipe

A blanket `sed` pass after cloning gets most of the way:

```sh
grep -rl 'zftadvancements\|billwoika\|your-username' . | \
  xargs sed -i \
    -e 's/zftadvancements/your-org/g' \
    -e 's/billwoika/your-domain/g' \
    -e 's/your-username/your-user/g'
```

Then audit the result:

```sh
# Confirm nothing was missed
grep -rn 'zftadvancements\|billwoika\|your-username' . || echo "Clean."
```

## What's deliberately not parameterized

The framework is **not** templated with Jinja or similar. Source files
contain literal placeholder strings, not `{{ org.name }}`-style
variables. The reasoning:

- **Literal strings stay readable** in any markdown viewer (GitHub,
  IDE preview, terminal `less`). Templated variables don't render
  usefully without a build step.
- **`grep` works.** Finding "where is the org name referenced?" is
  `grep -r zftadvancements`. Finding "where is `{{ org.name }}` referenced?"
  works too, but the literal-string version is more concrete.
- **Substitution is a one-time forking action**, not a per-build step.
  The framework expects you to fork once, customize, then maintain
  your own copy with your own values.

If you genuinely need multi-deployment support (different builds for
different environments from one source), MkDocs supports the
`mkdocs-macros-plugin` for true variable substitution. The framework
doesn't ship this; add it if you need it.

## Versioning

The framework is versioned via the docs site, not the dotfiles.
Dotfile changes that break compatibility get noted in the relevant
docs page; otherwise the dotfiles are continuously developed on
`main`.

Earlier framework versions (when the manuscript was a Word document)
are preserved in the `archive/` directory of the repo. The most
recent of those is `v2.7-snapshot.docx`, frozen at the start of the
MkDocs migration.

## Versioning conventions used here

When the docs reference framework versions:

- **v2.4** — Container chapter added (Section 21)
- **v2.5** — Make as a thin wrapper around mise tasks (Section 7.2)
- **v2.6** — Editor and IDE chapter (Section 22, ~50 pages)
- **v2.7** — Tool-enforced git practices (Section 17.10), MkDocs
  migration

These are the versions of the manuscript document. Going forward,
the docs site is the source of truth, and version numbers may
become less prominent — pages get updated when they need updating,
without ceremonial version bumps.
