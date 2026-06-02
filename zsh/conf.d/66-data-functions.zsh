# $ZDOTDIR/conf.d/66-data-functions.zsh
# ─────────────────────────────────────────────────────────────────────
# Data and text processing — CSV, JSON, table inspection.
# ─────────────────────────────────────────────────────────────────────

# ── csvsplit: split a CSV into chunks, preserving the header row ────
# Usage: csvsplit [-l lines] [-p prefix] [-d outdir] <file.csv>
csvsplit() {
  local usage="Usage: csvsplit [-l lines] [-p prefix] [-d outdir] <file.csv>"
  local lines=10000
  local prefix=""
  local outdir="."

  while getopts ":l:p:d:h" opt; do
    case $opt in
      l) lines=$OPTARG ;;
      p) prefix=$OPTARG ;;
      d) outdir=$OPTARG ;;
      h) echo "$usage"; return 0 ;;
      \?) echo "Unknown option: -$OPTARG" >&2; return 1 ;;
      :)  echo "Option -$OPTARG requires an argument" >&2; return 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  local infile="${1:?$usage}"
  [[ -f "$infile" ]] || { echo "Error: '$infile' not found" >&2; return 1; }
  [[ -z "$prefix" ]] && prefix="${infile:t:r}_"  # zsh: tail → strip ext
  mkdir -p "$outdir" || return 1

  awk -v chunk="$lines" -v pre="$outdir/$prefix" '
    NR == 1 {
      header = $0
      part = 0
      outfile = sprintf("%s%04d.csv", pre, part)
      print header > outfile
      next
    }
    (NR - 2) % chunk == 0 && NR > 2 {
      close(outfile)
      part++
      outfile = sprintf("%s%04d.csv", pre, part)
      print header > outfile
    }
    { print >> outfile }
    END {
      if (outfile) close(outfile)
      printf "Split %d data rows into %d files\n", NR - 1, part + 1
    }
  ' "$infile"
}

# ── csv-preview: head of a CSV with column alignment ────────────────
csv-preview() {
  [[ $# -ge 1 ]] || { echo "usage: csv-preview <file> [rows]" >&2; return 1; }
  local rows="${2:-20}"
  head -n "$rows" "$1" | column -t -s','
}

# ── JSON helpers ────────────────────────────────────────────────────
alias jqp='jq .'              # pretty
alias jqc='jq -c .'           # compact
alias jqs='jq -S .'           # sorted keys (reproducible diffs)

# Count unique values of a jq expression across a JSONL stream
jq-count() {
  [[ $# -eq 1 ]] || { echo "usage: jq-count <jq-expression>" >&2; return 1; }
  jq -r "$1" | sort | uniq -c | sort -rn
}
# Usage: cat events.jsonl | jq-count '.event_type'
