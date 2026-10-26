#!/bin/sh
# Bookkeeping for baton runs. Each subcommand does in one call what would
# otherwise take the orchestrator several tool calls, and prints a few short
# lines and nothing else.
#
#   baton.sh start <flow> [--doc-only] [--in-place] [--allow <path>] [--turns N] [--minutes M] <<'BATON_END'
#   check: <command>        (optional; written verbatim to check.sh)
#   eval: <command>         (optional; written verbatim to eval.sh)
#   options: <json object>  (optional)
#   task:
#   <the TASK verbatim, any number of lines>
#   BATON_END
#   baton.sh resume <run-id | --flow <flow>> [--turns N] [--minutes M]
#   baton.sh turn <run-dir> <label> <role> <status> [-C <dir>] [-m <message>] [--no-commit] <<'EOF'
#   <one-line summary>
#   EOF
#   baton.sh eval <run-dir> <label> [-C <dir> | --sha <commit>] [--beat <score> --goal max|min]
#   baton.sh gates <run-dir> <plan-path> <plan-commit>
#   baton.sh stop <run-dir> <finished|stopped|failed> <reason>
#
# The TASK and the user's --check / --eval commands never pass through this
# script's arguments: they arrive on stdin through a quoted heredoc, so no
# quoting can change them.

set -u

die() { echo "ERROR: $*"; exit 2; }

is_int() { case $1 in ''|*[!0-9]*) return 1;; esac; }

abspath() { (cd "$1" 2>/dev/null && pwd) || die "no such directory: $1"; }

load_env() {
  [ -f "$1/run.env" ] || die "no run.env in $1"
  . "$1/run.env"
}

# Read a string or number field from a run's state.json, pretty-printed or not.
js() { tr -d '\n' < "$1/state.json" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'; }
jn() { tr -d '\n' < "$1/state.json" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" | head -1 | sed 's/.*:[[:space:]]*//'; }

# Runs started before 0.2.0 have only state.json; build the run.env the script needs from it.
migrate_env() {
  [ -f "$1/state.json" ] || die "no run.env or state.json in $1"
  m_branch=$(js "$1" branch); m_base=$(js "$1" base); m_started=$(jn "$1" started_epoch)
  [ -n "$m_branch" ] && [ -n "$m_base" ] && [ -n "$m_started" ] || die "can't read branch, base and started_epoch from $1/state.json"
  m_minutes=$(jn "$1" minutes)
  m_turns=$(jn "$1" turns)
  cat > "$1/run.env" <<EOF
FLOW='$(js "$1" flow)'
RUN_ID='$(basename "$1")'
BRANCH='$m_branch'
START_BRANCH='$(js "$1" start_branch)'
BASE='$m_base'
STARTED=$m_started
MAX_TURNS=${m_turns:-8}
DEADLINE=${m_minutes:+$((m_started + m_minutes * 60))}
EOF
  echo "note: this run started before baton 0.2.0, so run.env was rebuilt from state.json. It has no check.sh or eval.sh: if it used --check or --eval, write those commands there (they are in state.json) before the next turn."
}

# Labels that share a family are counted together: t3 and t4, or "r2 lane-1" and "r3 lane-1".
family() { printf '%s\n' "$1" | sed -E 's/^([a-z]+)[0-9]+(.*)$/\1[0-9]+\2/'; }

file_tag() { printf '%s' "$1" | tr ' /' '--'; }

cmd_start() {
  [ $# -ge 1 ] || die "usage: start <flow> [options]"
  flow=$1; shift
  doc=0; inplace=0; allow=""; turns=8; minutes=""
  while [ $# -gt 0 ]; do
    case $1 in
      --doc-only) doc=1 ;;
      --in-place) inplace=1 ;;
      --allow) allow=$2; shift ;;
      --turns) turns=$2; shift ;;
      --minutes) minutes=$2; shift ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done
  is_int "$turns" || die "--turns must be a whole number"
  [ -z "$minutes" ] || is_int "$minutes" || die "--minutes must be a whole number"
  [ ! -t 0 ] || die "pass the run spec (check:, eval:, options:, task:) on stdin"
  spec=$(cat)

  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git repository: run git init and make a first commit"
  cd "$top" || die "cannot enter $top"
  git rev-parse -q --verify HEAD >/dev/null || die "the repository has no commits yet: make a first commit"

  if [ $doc = 0 ]; then
    dirty=$(git status --porcelain | awk -v p="$allow" 'substr($0, 4) != p')
    if [ -n "$dirty" ]; then
      echo "ERROR: the working tree has uncommitted changes; commit or stash them first:"
      printf '%s\n' "$dirty" | head -10
      exit 3
    fi
  fi

  id=$flow-$(date +%Y%m%d-%H%M%S)
  if [ -e ".baton/runs/$id" ]; then sleep 1; id=$flow-$(date +%Y%m%d-%H%M%S); fi
  rd=.baton/runs/$id
  mkdir -p "$rd" || die "cannot create $rd"
  ex=$(git rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$ex")"
  grep -qxF '.baton/' "$ex" 2>/dev/null || echo '.baton/' >> "$ex"

  start_branch=$(git symbolic-ref -q --short HEAD || git rev-parse --short HEAD)
  base=$(git rev-parse HEAD)
  branch=$start_branch
  if [ $doc = 0 ] && [ $inplace = 0 ]; then
    branch=baton/$id
    git switch -q -c "$branch" || die "cannot create branch $branch"
  fi

  now=$(date +%s)
  deadline=""
  [ -z "$minutes" ] || deadline=$((now + minutes * 60))
  cat > "$rd/run.env" <<EOF
FLOW='$flow'
RUN_ID='$id'
BRANCH='$branch'
START_BRANCH='$start_branch'
BASE='$base'
STARTED=$now
MAX_TURNS=$turns
DEADLINE=$deadline
EOF
  echo "# baton $flow · run $id · base $(git rev-parse --short "$base") · budget $turns turns${minutes:+, $minutes min}" > "$rd/log.md"

  header() { printf '%s\n' "$spec" | awk -v k="$1: " '/^task:/ { exit } index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
  c=$(header check); [ -z "$c" ] || printf '%s\n' "$c" > "$rd/check.sh"
  e=$(header eval); [ -z "$e" ] || printf '%s\n' "$e" > "$rd/eval.sh"
  o=$(header options); [ -n "$o" ] || o="{}"
  task=$(printf '%s\n' "$spec" | awk 'go { print } /^task:/ && !go { go = 1; sub(/^task:[ ]?/, ""); if ($0 != "") print }' |
    awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, ""); if (NR > 1) print "\\n"; print }')
  printf '{"flow": "%s", "run_id": "%s", "task": "%s", "options": %s, "extra": {}}\n' "$flow" "$id" "$task" "$o" > "$rd/state.json"

  echo "run_id=$id"
  echo "run_dir=$rd"
  echo "branch=$branch (from $start_branch)"
  echo "base=$base"
  echo "budget=$turns turns${minutes:+, $minutes min}"
  echo "wrote state.json${c:+, check.sh}${e:+, eval.sh}"
}

cmd_resume() {
  id=""; flow=""; turns=""; minutes=""
  while [ $# -gt 0 ]; do
    case $1 in
      --flow) flow=$2; shift ;;
      --turns) turns=$2; shift ;;
      --minutes) minutes=$2; shift ;;
      -*) die "unknown option: $1" ;;
      *) id=$1 ;;
    esac
    shift
  done
  [ -z "$turns" ] || is_int "$turns" || die "--turns must be a whole number"
  [ -z "$minutes" ] || is_int "$minutes" || die "--minutes must be a whole number"
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git repository"
  cd "$top" || die "cannot enter $top"

  if [ -z "$id" ]; then
    [ -n "$flow" ] || die "give a run id or --flow <flow>"
    for d in $(ls -1d .baton/runs/"$flow"-* 2>/dev/null | sort -r); do
      last=$(grep -E '^stop · ' "$d/log.md" 2>/dev/null | tail -1)
      case $last in "stop · finished"*|"stop · failed"*) continue ;; esac
      [ -f "$d/state.json" ] && case $(js "$d" status) in finished|failed) continue ;; esac
      id=$(basename "$d"); break
    done
    [ -n "$id" ] || die "no $flow run to resume"
  fi
  rd=.baton/runs/$id
  [ -d "$rd" ] || die "no run $id in .baton/runs"
  [ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes; commit or stash them first"
  [ -f "$rd/run.env" ] || migrate_env "$rd"
  load_env "$rd"
  cur=$(git symbolic-ref -q --short HEAD || echo "")
  if [ "$cur" != "$BRANCH" ]; then git switch -q "$BRANCH" || die "cannot switch to $BRANCH"; fi
  now=$(date +%s)
  [ -z "$turns" ] || echo "MAX_TURNS=$turns" >> "$rd/run.env"
  [ -z "$minutes" ] || echo "DEADLINE=$((now + minutes * 60))" >> "$rd/run.env"
  echo "resume · $(date +%Y%m%d-%H%M%S)${turns:+ · turns $turns}${minutes:+ · minutes $minutes}" >> "$rd/log.md"
  load_env "$rd"

  echo "run_id=$id"
  echo "run_dir=$rd"
  echo "branch=$BRANCH (from $START_BRANCH)"
  echo "base=$BASE"
  echo "budget=$MAX_TURNS turns"
  echo "last turns:"
  grep -E '^[a-z]+[0-9]+[^·]* · ' "$rd/log.md" | tail -4
}

cmd_turn() {
  [ $# -ge 4 ] || die "usage: turn <run-dir> <label> <role> <status> [options] < summary"
  rd=$1; label=$2; role=$3; status=$4; shift 4
  wd=.; msg=""; commit=1
  while [ $# -gt 0 ]; do
    case $1 in
      -C) wd=$2; shift ;;
      -m) msg=$2; shift ;;
      --no-commit) commit=0 ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done
  case $status in progress|done|blocked|missing) ;; *) die "status must be progress, done, blocked or missing" ;; esac
  load_env "$rd"
  ard=$(abspath "$rd")
  tag=$(file_tag "$label")
  summary=$(head -n 1 | tr -d '\r' | cut -c1-200)
  [ -n "$summary" ] || summary="(no summary)"
  [ -n "$msg" ] || msg="baton($FLOW): $label $role"

  change=-; sha=""
  if [ $commit = 1 ]; then
    git -C "$wd" add -A || die "git add failed in $wd"
    if git -C "$wd" diff --cached --quiet; then
      change=empty
    else
      git -C "$wd" commit -q -m "$msg" || die "commit failed in $wd"
      change=changed
      sha=$(git -C "$wd" rev-parse --short HEAD)
    fi
  fi

  check=-; code=""
  if [ -f "$ard/check.sh" ]; then
    git -C "$wd" ls-files --others --exclude-standard > "$ard/pre-check.txt"
    (cd "$wd" && sh "$ard/check.sh") > "$ard/check-$tag.log" 2>&1
    code=$?
    git -C "$wd" ls-files --others --exclude-standard | grep -vxFf "$ard/pre-check.txt" |
      while IFS= read -r f; do
        rm -f -- "$wd/$f"
        d=$(dirname -- "$f")
        [ "$d" = . ] || (cd "$wd" && rmdir -p -- "$d" 2>/dev/null)
      done
    if [ "$code" = 0 ]; then check=pass; else check=fail; fi
  fi

  echo "$label · $role · $status · $change · $check · $summary" >> "$ard/log.md"
  echo "$label · $role · $status · $change · $check · $summary"

  line2="commit ${sha:-none ($change)}"
  [ "$check" = - ] || line2="$line2 · check $check (exit $code, log $rd/check-$tag.log)"
  echo "$line2"

  fam=$(family "$label")
  grep -E "^$fam · " "$ard/log.md" | awk -F ' · ' -v s="$status" -v c="$change" '
    { st[NR] = $3; ch[NR] = $4 }
    END {
      a = 0; for (i = NR; i > 0 && st[i] == s; i--) a++
      b = 0; for (i = NR; i > 0 && ch[i] == c; i--) b++
      prev = (NR > a) ? st[NR - a] : "none"
      printf "streak: %s x%d (before that: %s) · %s x%d\n", s, a, prev, c, b
      if ((s == "blocked" || s == "missing") && a >= 2) printf "FAILED: second %s turn in a row\n", s
    }'

  case $label in
    t[0-9]*|r[0-9]*)
      n=$(printf '%s' "$label" | sed -E 's/^[a-z]+([0-9]+).*/\1/')
      now=$(date +%s)
      el=$(( (now - STARTED) / 60 ))
      left=continue
      [ "$n" -ge "$MAX_TURNS" ] && left="spent (turns)"
      if [ -n "$DEADLINE" ]; then
        [ "$now" -ge "$DEADLINE" ] && left="spent (minutes)"
        echo "budget: $n/$MAX_TURNS turns · $el of $(( (DEADLINE - STARTED) / 60 )) min · $left"
      else
        echo "budget: $n/$MAX_TURNS turns · $el min · $left"
      fi
      ;;
  esac
}

cmd_eval() {
  [ $# -ge 2 ] || die "usage: eval <run-dir> <label> [-C <dir> | --sha <commit>] [--beat <score> --goal max|min]"
  rd=$1; label=$2; shift 2
  wd=.; sha=""; beat=""; goal=max
  while [ $# -gt 0 ]; do
    case $1 in
      -C) wd=$2; shift ;;
      --sha) sha=$2; shift ;;
      --beat) beat=$2; shift ;;
      --goal) goal=$2; shift ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done
  ard=$(abspath "$rd")
  [ -f "$ard/eval.sh" ] || die "no eval.sh in $rd"
  tag=$(file_tag "$label")
  log=$ard/eval-$tag.log
  wt=""
  if [ -n "$sha" ]; then
    wt=$ard/eval-wt
    git worktree remove --force "$wt" >/dev/null 2>&1
    git worktree add -q --detach "$wt" "$sha" || die "cannot check out $sha"
    [ -d .lake/packages ] && mkdir -p "$wt/.lake" && ln -s "$PWD/.lake/packages" "$wt/.lake/packages"
    wd=$wt
  fi
  (cd "$wd" && sh "$ard/eval.sh") > "$log" 2>&1
  code=$?
  last=$(tail -n 1 "$log" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  score=none
  if [ "$code" = 0 ] && printf '%s\n' "$last" | grep -Eq '^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$'; then
    score=$last
  fi

  if [ -n "$sha" ]; then
    full=$(git rev-parse "$sha")
    git worktree remove --force "$wt" >/dev/null 2>&1
    if command -v shasum >/dev/null 2>&1; then sum=$(shasum -a 256 "$log" | cut -d' ' -f1); else sum=$(sha256sum "$log" | cut -d' ' -f1); fi
    esum=$(if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$ard/eval.sh"; else sha256sum "$ard/eval.sh"; fi | cut -d' ' -f1)
    mkdir -p "$ard/receipts"
    cat > "$ard/receipts/$tag.json" <<EOF
{"label": "$label", "commit": "$full", "score": "$score", "exit_code": $code, "eval_sha256": "$esum", "log": "eval-$tag.log", "log_sha256": "$sum", "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
  fi

  if [ "$score" = none ]; then
    if [ "$code" != 0 ]; then why="exit $code"; else why="no number on the last line"; fi
    result="rejected ($why)"
  elif [ -n "$beat" ] && [ "$beat" != none ]; then
    better=$(awk -v a="$score" -v b="$beat" -v g="$goal" 'BEGIN { if (g == "min") print (a + 0 < b + 0) ? "yes" : "no"; else print (a + 0 > b + 0) ? "yes" : "no" }')
    result="score $score · beats $beat ($goal): $better"
  else
    result="score $score"
  fi
  echo "eval $label · ${sha:+$(git rev-parse --short "$sha") · }$result" >> "$ard/log.md"
  echo "eval $label: $result · log $rd/eval-$tag.log"
  [ "$score" != none ] || tail -n 2 "$log" | cut -c1-200
  [ -z "$sha" ] || echo "receipt $rd/receipts/$tag.json"
}

cmd_gates() {
  [ $# -ge 3 ] || die "usage: gates <run-dir> <plan-path> <plan-commit>"
  rd=$1; plan=$2; pc=$3
  load_env "$rd"
  ard=$(abspath "$rd")
  fails=""
  added=$ard/added.txt
  # Added lines since the plan was committed, so the plan's own text never trips a gate.
  git diff "$pc"..HEAD -U0 | awk '/^\+\+\+ /{ f = substr($0, 7); next } /^\+/{ print f ": " substr($0, 2) }' > "$added"

  g1=$(grep -E '^t[0-9]+ · ' "$ard/log.md" | tail -1 | awk -F ' · ' '{ print $5 }')
  case $g1 in fail) echo "G1 fail: the check failed (see the latest check log)"; fails="$fails G1" ;; pass) echo "G1 pass" ;; *) echo "G1 pass (no check)" ;; esac

  hits=$(git grep -nE '^(<<<<<<<|>>>>>>>)( |$)' -- . ':(exclude).baton' 2>/dev/null | head -3 | cut -c1-160)
  if [ -n "$hits" ]; then echo "G2 fail: conflict markers"; printf '%s\n' "$hits"; fails="$fails G2"; else echo "G2 pass"; fi

  hits=$(grep -E '(TODO|FIXME|XXX|NotImplementedError|unimplemented!|todo!\()' "$added" | head -3 | cut -c1-160)
  if [ -n "$hits" ]; then echo "G3 fail: new stubs"; printf '%s\n' "$hits"; fails="$fails G3"; else echo "G3 pass"; fi

  hits=$(grep -E '(@pytest\.mark\.skip|\.skip\(|\bxit\(|@Disabled|t\.Skip\()' "$added" | head -3 | cut -c1-160)
  if [ -n "$hits" ]; then echo "G4 fail: skipped tests"; printf '%s\n' "$hits"; fails="$fails G4"; else echo "G4 pass"; fi

  hits=$(grep -E '(BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,})' "$added" | cut -d: -f1 | sort -u | head -3)
  if [ -n "$hits" ]; then echo "G5 fail: something that looks like a secret in (values not shown):"; printf '%s\n' "$hits"; fails="$fails G5"; else echo "G5 pass"; fi

  if [ -n "$(git diff --stat "$pc"..HEAD -- "$plan")" ]; then echo "G6 fail: the plan file was edited"; fails="$fails G6"; else echo "G6 pass"; fi

  rm -f "$added"
  if [ -n "$fails" ]; then echo "gates: fail$fails"; else echo "gates: all pass"; fi
}

cmd_stop() {
  [ $# -ge 3 ] || die "usage: stop <run-dir> <finished|stopped|failed> <reason>"
  rd=$1; st=$2; shift 2
  case $st in finished|stopped|failed) ;; *) die "status must be finished, stopped or failed" ;; esac
  load_env "$rd"
  echo "stop · $st · $*" >> "$rd/log.md"
  used=$(grep -cE '^t[0-9]+ · ' "$rd/log.md")
  echo "stop: $st · $* · $used work turns logged (budget $MAX_TURNS)"
  echo "commits on $BRANCH since base:"
  git log --oneline "$BASE"..HEAD | head -20
  last=$(grep -E '^t[0-9]+ · ' "$rd/log.md" | tail -1 | awk -F ' · ' '{ print $5 }')
  [ -z "$last" ] || [ "$last" = - ] || echo "last check: $last"
  if [ "$BRANCH" != "$START_BRANCH" ]; then
    echo "keep:   git switch $START_BRANCH && git merge $BRANCH"
    echo "drop:   git switch $START_BRANCH && git branch -D $BRANCH"
  fi
  [ "$st" = finished ] || echo "resume: /baton:$FLOW --resume $RUN_ID"
}

[ $# -ge 1 ] || die "usage: baton.sh <start|resume|turn|eval|gates|stop> ..."
sub=$1; shift
case $sub in
  start) cmd_start "$@" ;;
  resume) cmd_resume "$@" ;;
  turn) cmd_turn "$@" ;;
  eval) cmd_eval "$@" ;;
  gates) cmd_gates "$@" ;;
  stop) cmd_stop "$@" ;;
  *) die "unknown subcommand: $sub" ;;
esac
