# Command-Line Techniques

This page assumes daily shell use — `ls`, `cd`, `cat`, basic piping.
The target is the engineer who reaches for Python or a throwaway
script when a shell one-liner would do, and wants to close that gap.

All examples use zsh unless noted. Where macOS and Linux zsh diverge
— usually because of differing underlying coreutils — the divergence
is called out explicitly.

## Piping vs. redirection

These are different mechanisms that look similar and are frequently
confused.

### Piping

A pipe connects the stdout of one process to the stdin of the next.
The processes run concurrently — the second process reads as the
first writes:

```zsh
ps aux | grep python | grep -v grep
```

Three processes, running in parallel, connected by two pipes. `ps`
writes process listings. `grep python` filters to Python processes.
`grep -v grep` removes the grep process itself from the output. Each
process starts before the previous one finishes.

Pipes only carry stdout by default. Stderr goes to the terminal
unless explicitly redirected:

```zsh
# stdout to grep, stderr to terminal
command_that_warns 2>&1 | grep "error"

# stderr only to grep (portable POSIX redirection — order matters)
command_that_warns 2>&1 >/dev/null | grep "error"
```

### Redirection

Redirection connects a file descriptor to a file. No second process
is involved:

```zsh
# stdout to a file (overwrite)
ls -la > listing.txt

# stdout to a file (append)
echo "new entry" >> log.txt

# stdin from a file
sort < unsorted.txt

# stderr to a file
make 2> build-errors.txt

# both stdout and stderr to the same file
make > build.log 2>&1

# stdout and stderr to separate files
make > build-stdout.log 2> build-stderr.log
```

The key distinction: `>` connects a process to a *file*. `|`
connects a process to another *process*. Using `>` where you mean
`|` silently overwrites a file. Using `|` where you mean `>` sends
output to a process that may or may not consume it.

### Process substitution

Process substitution bridges piping and redirection. It creates a
temporary file descriptor that carries the output of a command, and
presents it as a filename:

```zsh
# Compare the output of two commands
diff <(sort file1.txt) <(sort file2.txt)

# Feed command output to a program that expects a filename
wc -l <(grep "error" server.log)

# Use the output of a command as input to another
paste <(cut -d',' -f1 data.csv) <(cut -d',' -f3 data.csv)
```

`<(command)` is not a pipe and not a file. It is a file descriptor
disguised as a path — `/dev/fd/63` or similar. Programs that accept
filenames but not stdin can consume it. This is particularly useful
with `diff`, `paste`, `comm`, and any tool that requires two input
sources.

### tee

`tee` splits a pipe — it writes stdin to both a file and stdout,
allowing the pipeline to continue:

```zsh
# Save intermediate output while continuing the pipeline
curl -s https://api.example.com/data | tee raw-response.json | jq '.results[]'

# Log and process simultaneously
make 2>&1 | tee build.log | grep "error"

# Write to multiple files
echo "deploy at $(date)" | tee deploy.log | tee -a history.log > /dev/null
```

`tee` is essential for debugging pipelines — insert it at any stage
to capture what is flowing through without breaking the chain.

## Heredocs

Heredocs embed multi-line text directly in a shell command. The
syntax is `<< DELIMITER` ... `DELIMITER`:

```zsh
cat << 'EOF'
This is a multi-line string.
Variables like $HOME are NOT expanded because the delimiter is quoted.
Single quotes around EOF prevent interpolation.
EOF
```

```zsh
cat << EOF
This is a multi-line string.
The home directory is $HOME.
Without quotes on the delimiter, variables ARE expanded.
EOF
```

The distinction matters: quoted delimiters (`'EOF'`) produce literal
text. Unquoted delimiters (`EOF`) perform variable expansion and
command substitution. Use quoted delimiters for config files,
templates, and anything where a `$` should be a literal `$`.

### Heredoc with indentation

The `<<-` variant strips leading tabs (not spaces) from the heredoc
body, allowing indented heredocs inside functions and conditionals:

```zsh
if [[ $deploy == "true" ]]; then
	cat <<- 'EOF'
	apiVersion: apps/v1
	kind: Deployment
	metadata:
	  name: enrollment-service
	EOF
fi
```

### Heredoc to a file

Combine heredoc with redirection to write multi-line content to a
file:

```zsh
cat << 'EOF' > /tmp/config.yaml
database:
  host: localhost
  port: 5432
  name: enrollment_dev
EOF
```

### Heredoc to a command

Heredocs can feed any command that reads stdin, not just `cat`:

```zsh
# Feed SQL to psql
psql enrollment_dev << 'EOF'
SELECT customer_id, status, enrolled_at
FROM enrollments
WHERE status = 'active'
ORDER BY enrolled_at DESC
LIMIT 10;
EOF

# Feed JSON to jq
jq '.results[] | {id, status}' << 'EOF'
{"results": [{"id": 1, "status": "active"}, {"id": 2, "status": "pending"}]}
EOF
```

## The text processing pipeline

The shell's power is composition: small tools connected by pipes,
each doing one thing. The canonical pattern for text processing:

```
generate | filter | transform | sort | deduplicate | format
```

A concrete example — find the ten most common HTTP status codes in
an nginx access log:

```zsh
cat access.log | awk '{print $9}' | sort | uniq -c | sort -rn | head -10
```

Each stage:

1. `cat access.log` — emit the log file (or use `< access.log` to
   avoid the useless use of cat)
2. `awk '{print $9}'` — extract the 9th field (HTTP status code in
   the default nginx log format)
3. `sort` — sort the status codes (required by `uniq`)
4. `uniq -c` — count consecutive identical lines
5. `sort -rn` — sort numerically in reverse (highest count first)
6. `head -10` — take the top ten

This pattern scales. Replace `cat` with `curl`, `kubectl logs`, or
`docker logs`. Replace `awk` with `cut` or `jq`. Replace `head` with
`tail` or `tee`. The pipeline structure is the same.

### cut vs. awk for field extraction

`cut` is simpler and faster for fixed-delimiter data:

```zsh
# Extract the first and third columns from a CSV
cut -d',' -f1,3 data.csv

# Extract username from /etc/passwd
cut -d':' -f1 /etc/passwd
```

`awk` is necessary when the delimiter is irregular (whitespace), when
fields need computation, or when the extraction logic is conditional:

```zsh
# Whitespace-delimited (cut cannot handle variable whitespace)
ps aux | awk '{print $1, $11}'

# Conditional extraction
awk -F',' '$3 > 100 {print $1, $3}' data.csv

# Field computation
awk -F',' '{total += $3} END {print "Sum:", total}' data.csv
```

The rule: if the data has a fixed, single-character delimiter and you
need simple field extraction, use `cut`. For anything else, use `awk`.

## grep

`grep` searches text for patterns. The basics are well known; the
intermediate features are where it becomes powerful.

### Essential flags

```zsh
# Recursive search in a directory
grep -r "def enroll" src/

# Recursive, but only in Python files
grep -r --include="*.py" "def enroll" src/

# Show line numbers
grep -rn "TODO" src/

# Show only filenames (not matching lines)
grep -rl "import structlog" src/

# Invert match (lines that do NOT match)
grep -v "^#" config.ini    # strip comments

# Count matches
grep -c "error" server.log

# Show context around matches
grep -B2 -A5 "Exception" server.log    # 2 lines before, 5 after
```

### Basic vs. extended regex

By default, `grep` uses basic regular expressions where `+`, `?`,
`{`, `|`, and `(` are literal characters. Use `grep -E` (extended
regex) to enable them (and `grep -F` for fixed strings). The legacy
`egrep`/`fgrep` wrappers are deprecated — GNU grep 3.8+ prints an
obsolescence warning for them — so prefer the `-E`/`-F` flags:

```zsh
# Basic regex: must escape special characters
grep 'customer_id=[0-9]\+' server.log

# Extended regex: no escaping needed
grep -E 'customer_id=[0-9]+' server.log

# Extended regex: alternation
grep -E '(error|warning|critical)' server.log

# Extended regex: optional match
grep -E 'https?://' urls.txt
```

### Fixed strings

When searching for a literal string that happens to contain regex
metacharacters, use `-F` (fixed string) instead of escaping:

```zsh
# Wrong: the dots are regex wildcards
grep "192.168.1.1" server.log

# Right: literal string match
grep -F "192.168.1.1" server.log
```

### ripgrep

On both macOS and Linux, `ripgrep` (`rg`) is a faster alternative
that respects `.gitignore`, uses extended regex by default, and
produces cleaner output:

```zsh
# Equivalent to grep -rn --include="*.py"
rg "def enroll" --type py

# Respect .gitignore (default behavior)
rg "TODO"

# Show only matches, not surrounding text
rg -o 'customer_id=\d+' server.log
```

`ripgrep` is not installed by default on either platform — in this
framework it is declared in mise's `[tools]` (aqua-backed), so
`mise install` delivers `rg` everywhere.

## sed

`sed` is a stream editor — it transforms text line by line. Its
primary use is substitution, but it can also delete, insert, and
rearrange lines.

### Substitution

```zsh
# Replace first occurrence on each line
sed 's/old/new/' file.txt

# Replace all occurrences on each line
sed 's/old/new/g' file.txt

# Case-insensitive replacement (GNU sed)
sed 's/old/new/gI' file.txt
```

### In-place editing

This is where macOS and Linux diverge. GNU sed (Linux) and BSD sed
(macOS) handle in-place editing differently:

```zsh
# GNU sed (Linux): -i with no argument
sed -i 's/old/new/g' file.txt

# BSD sed (macOS): -i requires an extension argument
sed -i '' 's/old/new/g' file.txt
```

The macOS syntax `sed -i ''` passes an empty extension (no backup).
Omitting the `''` on macOS causes sed to interpret the next argument
as the backup extension, producing cryptic errors. This is one of the
most common macOS/Linux portability issues in shell scripts.

**Portable approach:** use `sed -i.bak` on both platforms (creates a
backup file), then remove the backup:

```zsh
sed -i.bak 's/old/new/g' file.txt && rm file.txt.bak
```

Or use the framework's approach: detect the platform and alias
accordingly.

### Address ranges

`sed` can operate on specific lines or ranges:

```zsh
# Only line 5
sed '5s/old/new/' file.txt

# Lines 10 through 20
sed '10,20s/old/new/g' file.txt

# From a pattern to end of file
sed '/^## START/,$s/old/new/g' file.txt

# Delete lines matching a pattern
sed '/^#/d' config.ini        # remove comments

# Delete blank lines
sed '/^$/d' file.txt

# Print only matching lines (like grep)
sed -n '/pattern/p' file.txt
```

### When sed is the wrong tool

`sed` operates line by line. It cannot:

- Join lines or operate across line boundaries (without arcane
  hold-space gymnastics that nobody should write or maintain)
- Parse structured data (JSON, XML, YAML) — use `jq`, `xmllint`, or
  `yq`
- Perform arithmetic — use `awk`
- Handle complex conditionals — use `awk` or a script

If the `sed` command requires more than one substitution or a hold
space command, it has probably outgrown `sed`.

## awk

`awk` is a pattern-scanning and text-processing language. It sits
between `sed` (too simple for field processing) and a scripting
language (too heavy for one-liners). Its sweet spot is structured,
delimited text.

### Basics

`awk` splits each line into fields (`$1`, `$2`, ..., `$NF` for the
last field). The default delimiter is whitespace:

```zsh
# Print the second field of each line
awk '{print $2}' file.txt

# Print the last field
awk '{print $NF}' file.txt

# Custom delimiter
awk -F',' '{print $1, $3}' data.csv

# Multiple delimiters (any character in the bracket)
awk -F'[,;:]' '{print $1, $2}' mixed.txt
```

### Pattern matching

`awk` can filter lines by pattern before processing:

```zsh
# Only lines matching a regex
awk '/error/ {print $0}' server.log

# Only lines where field 3 exceeds a threshold
awk -F',' '$3 > 1000 {print $1, $3}' transactions.csv

# Only lines where a field matches a string
awk -F',' '$2 == "active" {print $1}' customers.csv

# Negate a pattern
awk '!/^#/' config.ini    # skip comments
```

### BEGIN and END

`BEGIN` runs before any input is processed. `END` runs after all
input is processed. Together they enable aggregation:

```zsh
# Sum a column
awk -F',' '{sum += $3} END {print "Total:", sum}' transactions.csv

# Count lines matching a condition
awk -F',' '$2 == "error" {count++} END {print "Errors:", count}' events.csv

# Average
awk -F',' '{sum += $3; n++} END {print "Average:", sum/n}' data.csv

# Set output delimiter
awk 'BEGIN {OFS="\t"} {print $1, $3}' data.txt
```

### Built-in variables

| Variable | Meaning |
|----------|---------|
| `NR` | Current line number (across all files) |
| `NF` | Number of fields in current line |
| `FS` | Input field separator |
| `OFS` | Output field separator |
| `RS` | Input record separator |
| `ORS` | Output record separator |
| `FILENAME` | Current input filename |

```zsh
# Print line numbers
awk '{print NR, $0}' file.txt

# Skip the header line
awk 'NR > 1 {print $2}' data.csv

# Print lines with more than 5 fields
awk 'NF > 5' data.txt
```

### When awk is the wrong tool

`awk` is excellent for line-oriented, field-delimited text. It is the
wrong tool for:

- JSON — use `jq`
- XML/HTML — use `xmllint`, `xq`, or a proper parser
- Binary data — use `xxd`, `od`, or a hex editor
- Anything requiring state across thousands of lines with complex
  data structures — write a script

The threshold: if the `awk` one-liner exceeds roughly 80 characters
or requires multiple pattern-action blocks with shared state, it has
outgrown the one-liner format. Write it as an awk script file or
switch to Python.

## xargs

`xargs` reads items from stdin and executes a command with those
items as arguments. It bridges tools that produce output (find, grep)
with tools that accept arguments (rm, mv, chmod).

### Basic usage

```zsh
# Delete all .pyc files
find . -name "*.pyc" | xargs rm

# Grep in files found by find
find . -name "*.py" | xargs grep "import os"
```

### Handling filenames with spaces

The default `xargs` splits on whitespace, which breaks on filenames
containing spaces. Use null-delimited input:

```zsh
# find -print0 produces null-delimited output
# xargs -0 reads null-delimited input
find . -name "*.log" -print0 | xargs -0 rm
```

This is non-negotiable for any `xargs` usage that handles
user-generated filenames or paths that may contain spaces.

### The -I{} pattern

`-I{}` replaces `{}` in the command with each input item. This allows
placing the argument anywhere in the command, not just at the end:

```zsh
# Rename files: foo.txt.bak -> foo.txt
find . -name "*.bak" | xargs -I{} mv {} {}.restored

# Run a command for each line of input
cat hosts.txt | xargs -I{} ssh {} "uptime"

# Copy files to a destination
find . -name "*.conf" | xargs -I{} cp {} /backup/configs/
```

### Parallel execution

`xargs -P` runs multiple processes in parallel:

```zsh
# Compress files in parallel (4 at a time)
find . -name "*.log" -print0 | xargs -0 -P4 gzip

# Run tests in parallel
find tests/ -name "test_*.py" | xargs -P4 -I{} python -m pytest {}
```

**macOS note:** macOS `xargs` supports `-P` for parallel execution.
The behavior is the same as GNU `xargs` on Linux for this flag.

## printf vs. echo

`echo` is the most common way to print text in shell scripts. It is
also non-portable — behavior varies between shells, between platforms,
and between configurations.

### Where echo diverges

```zsh
# Does this print a literal \n or a newline?
echo "line1\nline2"
```

The answer depends on the shell and platform:

- **zsh (macOS and Linux):** prints two lines (interprets `\n`)
- **bash (macOS, built-in):** prints the literal `\n`
- **bash (Linux, built-in):** prints the literal `\n`
- **bash with `echo -e`:** interprets `\n`, but `-e` is not
  POSIX-specified

```zsh
# Does this print -n literally or suppress the newline?
echo -n "no newline"
```

- **zsh:** suppresses the newline
- **bash:** suppresses the newline
- **POSIX sh:** behavior is undefined for `-n`

### printf is portable

`printf` behaves identically across zsh, bash, dash, and any
POSIX-compliant shell:

```zsh
# Newline is explicit and portable
printf "line1\nline2\n"

# No trailing newline (no flag needed)
printf "no newline"

# Format strings
printf "%-20s %10d\n" "enrollment" 4821
printf "%-20s %10d\n" "payment" 9917

# Padding and alignment
printf "%05d\n" 42        # 00042

# Repeating a character
printf '%.0s-' {1..40}    # print 40 dashes
printf '\n'
```

### When it matters

For interactive one-liners, `echo` is fine — you know your shell,
you know its behavior. In scripts, functions, and anything that
might run on a different platform or under a different shell, use
`printf`. The cost is minimal (a format string instead of a bare
string) and the portability is absolute.

```zsh
# In a script: always printf
log() {
  printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

# Not this
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"
}
```

The `printf` version produces identical output on macOS zsh, Linux
bash, Alpine dash, and any other POSIX shell. The `echo` version
might, depending on how the message string interacts with `echo`'s
escape interpretation.

## macOS vs. Linux divergences

Beyond `sed -i` and `echo`, several core utilities behave differently
between macOS (BSD userland) and Linux (GNU coreutils). These
divergences are the most common source of "works on my machine"
failures in shell scripts.

### date

```zsh
# GNU date (Linux): -d for date parsing
date -d "2026-05-24" +%s

# BSD date (macOS): -j -f for date parsing
date -j -f "%Y-%m-%d" "2026-05-24" +%s

# GNU date: relative dates
date -d "+3 days" +%Y-%m-%d

# BSD date: relative dates
date -v+3d +%Y-%m-%d
```

### stat

```zsh
# GNU stat (Linux): file size
stat -c %s file.txt

# BSD stat (macOS): file size
stat -f %z file.txt
```

### readlink

```zsh
# Resolve a symlink fully (canonicalize). `readlink -f` works on both
# GNU (Linux) and current macOS — verified on macOS 26.x: /usr/bin/readlink
# now accepts -f and canonicalizes like GNU, despite a stale man page that
# still documents the old BSD `-f format` syntax.
readlink -f /usr/local/bin/python3

# For maximum portability (older macOS releases genuinely lacked
# readlink -f, and for POSIX-leaning scripts), `realpath` is the safer
# choice and is available on Linux and recent macOS:
realpath /usr/local/bin/python3
```

### sort

```zsh
# GNU sort (Linux): human-readable numeric sort
du -sh * | sort -h
# -h (human-numeric) works on both GNU sort and current macOS sort
# (macOS adopted the FreeBSD-derived sort, which supports -h).
```

### The portable solution

For scripts that must run on both platforms, two strategies:

**Install GNU coreutils on macOS:**

```zsh
brew install coreutils
# GNU tools are available with 'g' prefix: gdate, gsed, gstat, greadlink
```

The framework's approach is to install GNU coreutils and alias the
`g`-prefixed versions when the script requires GNU behavior. See
the [Platform Portability](../framework-platform-portability.md) page
for the full strategy.

**Use POSIX-only features:** stick to the subset that both BSD and
GNU tools support. This is more restrictive but requires no
additional dependencies. The POSIX profile
(`sh/tests/profile_test.sh`) demonstrates this approach — it runs
identically on macOS, Linux, and Alpine with no GNU dependency.

## Questions to ask

1. When you need to extract a field from structured text, do you
   reach for `cut`/`awk` or write a Python script? If the latter,
   consider whether a one-liner would suffice.
2. Are your shell scripts portable between macOS and Linux? The
   `sed -i`, `date`, and `readlink` divergences are the most common
   failures.
3. When you pipe data between commands, do you know which file
   descriptors are connected? Stderr silently bypassing a pipe is a
   common source of "missing" output.
4. Do your heredocs use quoted delimiters (`'EOF'`) for literal
   content? Unquoted heredocs with `$` characters are a frequent
   source of unexpected variable expansion.
5. When an `awk` one-liner exceeds 80 characters, do you refactor it
   into a script? The threshold between "elegant one-liner" and
   "unmaintainable incantation" is lower than most engineers think.
