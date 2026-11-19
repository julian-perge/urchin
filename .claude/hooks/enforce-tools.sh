#!/usr/bin/env bash
# Enforces the urchin rules that a Bash command can break, by exiting 2 with a message the agent can act on.
# .claude/settings.json runs it before every Bash tool call. The Hooks section of AGENTS.md lists the rules and how to trigger each one.
# The command is parsed first, so a rule only fires on a program that would actually run and never on a mention of its name in an argument, a quoted string or a heredoc body.
# The parser is a copy of the one in Julian's global ~/.claude/hooks/enforce-tools.sh, which other machines do not have.

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)
[[ -z $COMMAND ]] && exit 0
[[ -z $CWD ]] && CWD=$PWD

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
JUSTFILE=$REPO/justfile
FFDEC_LOCK=/tmp/urchin-ffdec.lock

# Indexing a string byte by byte in the C locale keeps the parser fast on long heredocs.
LC_ALL=C

# PIPED is 1 while the parser checks a command whose output goes into a pipe.
PIPED=0
# FFDEC_LOCKED is 1 while the parser checks a command that runs under the ffdec lock.
FFDEC_LOCKED=0
RUNS_GIT_COMMIT=0
COMMIT_DIR=
COMMIT_ALL=0

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Short options can be bundled, so `-am` sets the a flag as much as `-a` does.
has_short_flag() {
  [[ $1 == -[!-]* && $1 == *"$2"* ]]
}

# Prints the justfile recipe whose body is `uv run <entry point>`, such as gut for the gut entry point, or nothing.
recipe_for_entry_point() {
  awk -v entry="$1" '
    /^[a-z][a-z0-9-]*[ :]/ { recipe = $1; sub(/:$/, "", recipe) }
    /^    uv run / && ($3 == entry || $3 == entry "\"") { print recipe; exit }
  ' "$JUSTFILE"
}

# Succeeds when the justfile recipe declares that it needs ffdec.
recipe_runs_ffdec() {
  awk -v recipe="$1" '
    ($1 == recipe || $1 == recipe ":") && /require "ffdec"/ { found = 1; exit }
    END { exit !found }
  ' "$JUSTFILE"
}

require_ffdec_lock() {
  ((FFDEC_LOCKED)) && return
  block "'$1' runs ffdec, and two ffdec processes must never run at once (docs/agents/art-extraction.md). Run it as 'lockf -k $FFDEC_LOCK $1 ...'. To hold the lock over a trace-swf, trace-run and log copy, wrap all three in one lockf with bash -c."
}

check_just() {
  local recipe
  while [[ ${1-} == -* ]]; do
    case "$1" in
      -c | --command)
        shift
        [[ ${1-} == uv ]] || block "Run '${1-}' directly, not through 'just --command'. Plain tools do not read .env (AGENTS.md, Commands)."
        check_command "$@"
        return
        ;;
      -f | --justfile | -d | --working-directory | -F | --dotenv-filename | -E | --dotenv-path | --color | --shell | --shell-arg | --chooser | --dotenv-command) shift; shift ;;
      --set) shift; shift; shift ;;
      *) shift ;;
    esac
  done
  recipe=${1-}
  [[ -z $recipe ]] && return
  if [[ $recipe == gut || $recipe == test ]] && ((PIPED)); then
    block "Do not pipe 'just $recipe' into another command: the pipe gives the exit code of the last command (docs/agents/multi-model.md). Run 'agent-skills run -- just $recipe' for a short summary and the exit code."
  fi
  recipe_runs_ffdec "$recipe" && require_ffdec_lock "just $recipe"
}

check_uv_run() {
  local entry recipe
  [[ ${1-} == run ]] || return
  shift
  while [[ ${1-} == -* ]]; do
    case "$1" in
      --with | --with-requirements | --python | -p | --project | --directory | --package | --extra | --group | --env-file | --index) shift; shift ;;
      *) shift ;;
    esac
  done
  entry=${1-}
  [[ -z $entry ]] && return
  recipe=$(recipe_for_entry_point "$entry")
  [[ -n $recipe ]] && block "Run 'just $recipe' instead of 'uv run $entry'. The recipe loads .env and finds Godot (AGENTS.md, Commands)."
}

check_git() {
  local dir=$CWD sub arg
  while [[ ${1-} == -* ]]; do
    case "$1" in
      -C)
        if [[ ${2-} == /* ]]; then dir=$2; else dir=$dir/${2-}; fi
        shift; shift
        ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path) shift; shift ;;
      *) shift ;;
    esac
  done
  sub=${1-}
  [[ $sub == commit ]] || return
  shift
  RUNS_GIT_COMMIT=1
  COMMIT_DIR=$dir
  for arg in "$@"; do
    if [[ $arg == --all ]] || has_short_flag "$arg" a; then COMMIT_ALL=1; fi
  done
}

check_command() {
  local name arg previous_lock

  # Each pass removes one layer that runs another program, such as a keyword, a variable assignment or a wrapper like env or xargs.
  while (($#)); do
    case "$1" in
      if | then | elif | else | while | until | do | '!' | '{' | time)
        shift
        ;;
      env)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -u | -C) shift; shift ;;
            *) shift ;;
          esac
        done
        ;;
      command | builtin)
        shift
        [[ ${1-} == -v || ${1-} == -V ]] && return
        ;;
      exec | nohup)
        shift
        ;;
      nice)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -n) shift; shift ;;
            *) shift ;;
          esac
        done
        ;;
      timeout)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -k | -s) shift; shift ;;
            *) shift ;;
          esac
        done
        shift
        ;;
      xargs)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -I | -J | -L | -n | -P | -R | -S | -s | -E | -d | -a) shift; shift ;;
            *) shift ;;
          esac
        done
        ;;
      # lockf is the macOS lock command and flock the Linux one. Either one holds the lock for the whole command it runs, a bash -c script included.
      lockf | flock | /usr/bin/lockf | /usr/bin/flock)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -t | -w | -E | --timeout | --conflict-exit-code) shift; shift ;;
            *) shift ;;
          esac
        done
        previous_lock=$FFDEC_LOCKED
        [[ ${1-} == "$FFDEC_LOCK" ]] && FFDEC_LOCKED=1
        (($#)) && shift
        check_command "$@"
        FFDEC_LOCKED=$previous_lock
        return
        ;;
      agent-skills | */agent-skills)
        shift
        [[ ${1-} == --repo ]] && shift 2
        [[ ${1-} == --repo=* ]] && shift
        [[ ${1-} == run ]] || return
        shift
        while (($#)); do
          case "$1" in
            --name | --tail) shift; shift ;;
            --name=* | --tail=*) shift ;;
            --) shift; break ;;
            *) break ;;
          esac
        done
        ;;
      bash | sh | zsh | dash | fish)
        shift
        while [[ ${1-} == -* ]]; do
          case "$1" in
            -o | -O) shift; shift ;;
            --*) shift ;;
            -*c*) analyze_text "${2-}"; return ;;
            *) shift ;;
          esac
        done
        return
        ;;
      eval)
        shift
        analyze_text "$*"
        return
        ;;
      *=*)
        [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]] || break
        shift
        ;;
      *)
        break
        ;;
    esac
  done
  (($#)) || return

  # A system path still names the same tool, but any other path is treated as a project's own program, such as .venv/bin/python.
  name=$1
  case "$name" in
    /usr/bin/* | /usr/local/bin/* | /usr/sbin/* | /bin/* | /sbin/* | /opt/homebrew/* | /home/linuxbrew/.linuxbrew/*) name=${name##*/} ;;
  esac
  shift

  case "$name" in
    godot | Godot | */Godot.app/Contents/MacOS/Godot | '$GODOT_BIN' | '${GODOT_BIN}')
      block "Run Godot through just: 'just godot <arguments>', 'just gut' or 'just import'. just picks the binary and takes a Godot slot (AGENTS.md, Commands)."
      ;;
    ffdec | ffdec.sh | */ffdec | */ffdec.sh)
      require_ffdec_lock "$name"
      ;;
    java)
      for arg in "$@"; do
        [[ $arg == *ffdec* ]] && require_ffdec_lock java
      done
      ;;
    uv)
      check_uv_run "$@"
      ;;
    just)
      check_just "$@"
      ;;
    git)
      check_git "$@"
      ;;
  esac
}

read_heredoc_bodies() {
  local entry strip delimiter line
  for entry in ${heredocs[@]+"${heredocs[@]}"}; do
    strip=${entry%%:*}
    delimiter=${entry#*:}
    while IFS= read -r line; do
      ((pos += ${#line} + 1))
      if ((strip)); then
        while [[ $line == $'\t'* ]]; do line=${line#$'\t'}; done
      fi
      [[ $line == "$delimiter" ]] && break
    done <<<"${s:pos}"
  done
  heredocs=()
}

parse_heredoc_delimiter() {
  local c delimiter=""
  while [[ ${s:pos:1} == ' ' || ${s:pos:1} == $'\t' ]]; do ((pos++)); done
  while ((pos < len)); do
    c=${s:pos:1}
    case "$c" in
      ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>' | '(' | ')') break ;;
      "'" | '"') ((pos++)) ;;
      '\') delimiter+=${s:pos+1:1}; ((pos += 2)) ;;
      *) delimiter+=$c; ((pos++)) ;;
    esac
  done
  heredocs+=("$1:$delimiter")
}

parse_backtick() {
  local c next inner=""
  ((pos++))
  while ((pos < len)); do
    c=${s:pos:1}
    if [[ $c == '`' ]]; then
      ((pos++))
      break
    fi
    if [[ $c == '\' ]]; then
      next=${s:pos+1:1}
      if [[ $next == '`' || $next == '\' || $next == '$' ]]; then
        inner+=$next
      else
        inner+=$c$next
      fi
      ((pos += 2))
      continue
    fi
    inner+=$c
    ((pos++))
  done
  analyze_text "$inner"
  word+='$()'
}

parse_double_quoted() {
  local c next rest plain
  ((pos++))
  while ((pos < len)); do
    rest=${s:pos}
    plain=${rest%%[\"\\\$\`]*}
    word+=$plain
    ((pos += ${#plain}))
    c=${s:pos:1}
    case "$c" in
      '"')
        ((pos++))
        return
        ;;
      '\')
        next=${s:pos+1:1}
        case "$next" in
          '"' | '\' | '$' | '`') word+=$next ;;
          $'\n') ;;
          *) word+=$c$next ;;
        esac
        ((pos += 2))
        ;;
      '`')
        parse_backtick
        ;;
      '$')
        if [[ ${s:pos+1:1} == '(' ]]; then
          ((pos += 2))
          parse_list ')'
          word+='$()'
        else
          word+=$c
          ((pos++))
        fi
        ;;
      *)
        word+=$c
        ((pos++))
        ;;
    esac
  done
}

end_word() {
  if ((has_word)); then
    ((redirect_target)) || words+=("$word")
    redirect_target=0
  fi
  word=""
  has_word=0
}

end_command() {
  if ((${#words[@]})); then
    case "${words[0]}" in
      'case') ((case_depth++)) ;;
      'esac') ((case_depth--)) ;;
    esac
    check_command "${words[@]}"
  fi
  words=()
}

# Parses commands until the end of the text, or until the closing parenthesis when $1 is ')', and checks each simple command as it ends.
# It leaves `pos` just past what it consumed, which is how a nested $(...) hands control back to the word it sits inside.
parse_list() {
  local stop=$1 c next rest plain word="" has_word=0 redirect_target=0 case_depth=0
  local -a words=() heredocs=()
  while ((pos < len)); do
    c=${s:pos:1}
    case "$c" in
      '\')
        next=${s:pos+1:1}
        if [[ $next != $'\n' ]]; then
          word+=$next
          has_word=1
        fi
        ((pos += 2))
        ;;
      "'")
        has_word=1
        ((pos++))
        rest=${s:pos}
        plain=${rest%%\'*}
        word+=$plain
        ((pos += ${#plain} + 1))
        ;;
      '"')
        has_word=1
        parse_double_quoted
        ;;
      '`')
        has_word=1
        parse_backtick
        ;;
      '$')
        has_word=1
        next=${s:pos+1:1}
        if [[ $next == '(' ]]; then
          ((pos += 2))
          parse_list ')'
          word+='$()'
        elif [[ $next == "'" ]]; then
          ((pos += 2))
          while ((pos < len)) && [[ ${s:pos:1} != "'" ]]; do
            [[ ${s:pos:1} == '\' ]] && ((pos++))
            word+=${s:pos:1}
            ((pos++))
          done
          ((pos++))
        elif [[ $next == '"' ]]; then
          ((pos++))
        else
          word+=$c
          ((pos++))
        fi
        ;;
      ' ' | $'\t')
        end_word
        ((pos++))
        ;;
      $'\n')
        end_word
        end_command
        ((pos++))
        read_heredoc_bodies
        ;;
      ';' | '&' | '|')
        end_word
        # A single | or a |& sends the output of the command that ends here into the next one, and a || does not.
        [[ $c == '|' && ${s:pos+1:1} != '|' && ${s:pos-1:1} != '|' ]] && PIPED=1
        end_command
        PIPED=0
        ((pos++))
        ;;
      '(')
        end_word
        end_command
        ((pos++))
        parse_list ')'
        ;;
      ')')
        end_word
        # A closing parenthesis inside a case statement ends a pattern such as `grep)`, and that pattern is not a command to run.
        if [[ ${words[0]-} == case ]]; then
          ((case_depth++))
          words=()
        elif ((case_depth > 0)); then
          words=()
        else
          end_command
          if [[ $stop == ')' ]]; then
            ((pos++))
            return
          fi
          words=()
        fi
        ((pos++))
        ;;
      '<' | '>')
        # The digits in a redirection like 2>&1 belong to the operator and are not a word of the command.
        if ((has_word)) && [[ $word =~ ^[0-9]+$ ]]; then
          word=""
          has_word=0
        fi
        end_word
        next=${s:pos+1:1}
        if [[ $next == '(' ]]; then
          ((pos++))
        elif [[ ${s:pos:3} == '<<<' ]]; then
          ((pos += 3))
          redirect_target=1
        elif [[ ${s:pos:3} == '<<-' ]]; then
          ((pos += 3))
          parse_heredoc_delimiter 1
        elif [[ ${s:pos:2} == '<<' ]]; then
          ((pos += 2))
          parse_heredoc_delimiter 0
        else
          ((pos++))
          while [[ ${s:pos:1} == '>' || ${s:pos:1} == '&' || ${s:pos:1} == '|' ]]; do ((pos++)); done
          redirect_target=1
        fi
        ;;
      '#')
        if ((has_word)); then
          word+=$c
          ((pos++))
        else
          while ((pos < len)) && [[ ${s:pos:1} != $'\n' ]]; do ((pos++)); done
        fi
        ;;
      *)
        word+=$c
        has_word=1
        ((pos++))
        ;;
    esac
  done
  end_word
  end_command
}

analyze_text() {
  local s=$1 pos=0 len=${#1}
  parse_list ''
}
analyze_text "$COMMAND"

# ruff reads each file as it is on disk, which differs from the staged copy when the file also has unstaged edits.
if ((RUNS_GIT_COMMIT)); then
  top=$(git -C "$COMMIT_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(
    git -C "$top" diff --cached --name-only --diff-filter=ACMR -z -- '*.py'
    ((COMMIT_ALL)) && git -C "$top" diff --name-only --diff-filter=ACMR -z -- '*.py'
  )
  ((${#files[@]})) || exit 0
  output=$(cd "$top" && uv run --quiet --project "$REPO" ruff format --check --force-exclude -- "${files[@]}" 2>&1) ||
    block "Staged Python fails 'uv run ruff format --check'. Run 'uv run ruff format' on these files and stage the result:
$output"
  output=$(cd "$top" && uv run --quiet --project "$REPO" ruff check --force-exclude -- "${files[@]}" 2>&1) ||
    block "Staged Python fails 'uv run ruff check'. Fix these findings, or run 'uv run ruff check --fix', and stage the result:
$output"
fi

exit 0
