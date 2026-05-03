# Database and API Tools

Two categories of IDE-adjacent tooling that the framework treats
deliberately: database clients for browsing schemas, running ad-hoc
queries, and managing connections; and API clients for exploring HTTP
services, sharing request collections across a team, and writing
automated checks. Both share a problem class — they're stateful,
project-scoped, and they want to sync — and the framework's stance is
the same in both: prefer file-based, version-controllable tools over
SaaS-locked ones whenever practical.

## Database clients

### The recommended tools

| Tool | License | Best for |
|------|---------|----------|
| **TablePlus** | Paid (free tier with row-count limits) | Native macOS, polished, multi-database |
| **DBeaver Community** | Free, Apache 2.0 | Cross-platform, license-clean |
| **DataGrip** | JetBrains (paid, included in All Products Pack) | SQL intelligence, schema diff, refactoring |
| **Postico 2** | Paid, Postgres-only | Best-in-class for Postgres specifically |

!!! tip "psql is still part of the toolkit"

    GUI clients are not a replacement for `psql`. Anything you'd
    script or automate — schema dumps, bulk operations, anything in
    CI — belongs in `psql`. The framework expects you to have both:
    `psql` for repeatable work, a GUI for interactive exploration.

### Connection management

Database clients share a hazard: they want to remember credentials.
The framework's [secrets principles](../operations/secrets.md) apply
directly:

- **TablePlus**: choose "Store in Keychain" rather than "Store in
  Connection"
- **DBeaver**: enable the master-password feature that encrypts stored
  credentials at rest
- **DataGrip**: use macOS Keychain integration (Settings > Database >
  Data Sources > "Save password in macOS Keychain")

All clients support reading from environment variables (`PGPASSWORD`
for Postgres, `MYSQL_PWD` for MySQL). If you launch the client from a
shell where direnv has loaded the environment via `use_1password`, the
password is in env vars and the client picks it up.

### What not to do

- **Don't commit connection details** to a project's repo. Exported
  connection files often contain plaintext passwords.
- **Don't store production credentials** in a personal client.
  Production access should go through a bastion or short-lived dynamic
  credentials from Vault.
- **Don't share session.sql files** with credentials in them. Query
  history panes occasionally capture `ALTER USER ... WITH PASSWORD`
  statements.

### Project-local connection documentation

The framework's recommended pattern: a `db/README.md` in projects
that ship a database, documenting connection details for each
environment *without secrets*:

```markdown
## Connecting to databases

### Development (local)
- Host:     localhost
- Port:     5432 (compose.yml)
- Database: myapp_dev
- User:     app
- Password: `app` (compose.yml; not a secret)

### Staging
- Host:     staging-db.springbig.internal (via bastion)
- Password: `op://eng/Staging DB/password`
```

## API clients

### Recommendation matrix

| Tool | License | Best for |
|------|---------|----------|
| **Bruno** | MIT (open source) | File-based collections, version-controllable |
| **.http files** (REST Client) | Free (editor extension) | Inline in VS Code/JetBrains, lightweight |
| **Postman** | Freemium (SaaS-synced) | Large existing collections, team collaboration |

### Bruno

Bruno stores collections as plain files on disk — no cloud sync, no
account, no SaaS dependency. Collections live in a directory that can
be committed to the project repo. This aligns with the framework's
file-based-and-version-controllable stance.

### Editor-based: REST Client and .http files

Both VS Code (REST Client extension) and JetBrains (built-in HTTP
Client) support `.http` files — plain text files with HTTP request
syntax that execute inline with a click or keyboard shortcut. The
files are version-controllable, shareable, and don't require a
separate application.

```http
### Get all users
GET {{host}}/api/v1/users
Authorization: Bearer {{token}}

### Create a user
POST {{host}}/api/v1/users
Content-Type: application/json

{
  "name": "Test User",
  "email": "test@example.com"
}
```

Environment variables (`{{host}}`, `{{token}}`) are defined in a
companion `http-client.env.json` file. Commit the template; gitignore
the file with actual credentials.

### Postman

Postman is the dominant tool in the category by install base. Its
collaboration features (shared workspaces, collection versioning,
monitors) are genuinely useful for large API teams. The tradeoff: data
lives on Postman's servers, and the free tier has usage limits.

The framework's recommendation: **if your team already uses Postman,
continue.** If starting fresh or choosing for a new project, prefer
Bruno or `.http` files for the version-controllability.

### OpenAPI / Swagger

For APIs with an OpenAPI specification, the specification itself is the
source of truth. Tools that generate client SDKs, documentation, and
test stubs from the spec (Swagger Codegen, openapi-generator) are the
specification-first alternative to manually-maintained request
collections. The framework recommends specification-first for any API
intended for external consumption.
