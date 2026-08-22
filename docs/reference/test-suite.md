# POSIX Test Suite

The framework includes a 30-test suite that validates the `~/.profile`
POSIX shim. The suite emits TAP (Test Anything Protocol) output for
harness compatibility and runs under any POSIX-compliant shell.

## Running the suite

```sh
# From anywhere, via the global mise task
mise run dotfiles:test

# Single shell, direct invocation
sh sh/tests/profile_test.sh

# Multi-shell sweep (dash, bash --posix, busybox)
sh sh/tests/profile_test.sh --multi
```

## Design principles

- **POSIX sh only** — the test suite itself uses no bashisms, matching
  the constraint on the profile it tests.
- **Self-contained** — no external test framework. TAP output for
  tooling integration, human-readable by default.
- **Non-destructive** — tests run in a temporary `$HOME` directory and
  clean up after themselves.

## Test groups

| Group | Tests | Validates |
|-------|-------|-----------|
| 1. Syntax | 3 | Profile sources without error, no bashisms, no shebang |
| 2. XDG defaults | 5 | `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` default correctly; pre-set values are preserved |
| 3. Tool locations | 4 | `CARGO_HOME`, `RUSTUP_HOME`, `GOPATH` derive from `XDG_DATA_HOME`; no `MISE_HOME` override |
| 4. Editor / locale | 3 | `EDITOR=vim`, `VISUAL=EDITOR`, `LANG` is UTF-8 |
| 5. PATH construction | 6 | mise shims, `CARGO_HOME/bin`, `GOPATH/bin`, `HOME/.local/bin` in PATH; priority order correct |
| 6. Idempotency | 2 | Sourcing twice/thrice produces identical PATH |
| 7. Non-existent dirs | 2 | Missing directories are not added to PATH |
| 8. Variable cleanup | 2 | Loop variables unset after sourcing; PATH is exported |
| 9. POSIX portability | 3 | `printf`, `command -v`, parameter expansion work |

## Key tests explained

### mise shim path priority (Groups 3 and 5)

The test verifies that `$XDG_DATA_HOME/mise/shims` appears in PATH
*before* `$CARGO_HOME/bin`. This priority order ensures that
mise-managed tool versions win over cargo-installed binaries when both
provide the same tool name. The profile's iteration order (lowest to
highest priority) and prepend semantics produce this.

### Idempotent PATH (Group 6)

The profile uses a `case ":${PATH}:"` guard to skip directories
already present. The idempotency test sources the profile three times
and asserts the PATH is identical each time. This catches the common
bug where sourcing the profile twice produces duplicate PATH entries.

### POSIX portability markers (Group 9)

These tests confirm that the POSIX primitives the profile relies on
(`printf`, `command -v`, `${VAR:-default}` parameter expansion) work
in the test shell. They catch environments where a non-POSIX shell is
masquerading as `/bin/sh`.

## CI integration

Add the test suite to CI pipelines for any change that touches the
profile:

```yaml
# In .github/workflows/test.yml
- name: POSIX profile tests
  run: sh sh/tests/profile_test.sh
```

## Expected output

```
# Testing: /path/to/dotfiles/profile
# Shell:   profile_test.sh (pid 12345)
ok 1 - profile sources without error
ok 2 - no bashisms in profile
ok 3 - profile has no shebang
ok 4 - XDG_CONFIG_HOME defaults to HOME/.config
...
1..30
# All 30 tests passed
```
