#!/usr/bin/env bash
# The status line refreshes many times a minute, so avoid forks: one jq call, git only when needed.
export GIT_OPTIONAL_LOCKS=0

# jq @sh quotes each value, so eval only assigns the variables.
eval "$(jq -r '
  def ok(f): try (f | if type == "string" or type == "number" then . else "" end) catch "";
  def n(f): try (f | if type == "number" then . else "" end) catch "";
  def i(f; cap): n(f) | if . == "" then . else [([floor, cap] | min), 0] | max end;
  @sh "model=\(ok(.model.display_name))
       cwd=\(ok(.workspace.current_dir))
       cost=\(n(.cost.total_cost_usd))
       mins=\(i(.cost.total_duration_ms / 60000; 999999))
       add=\(i(.cost.total_lines_added; 1e9))
       del=\(i(.cost.total_lines_removed; 1e9))
       ctx=\(i(.context_window.used_percentage; 100))"
' 2>/dev/null)"

# Repos and the JSON can carry terminal control codes in names. Strip them before you print.
# In the C locale, [[:cntrl:]] misses the UTF-8 C1 codes (C2 80-9F), so strip those bytes too.
clean() {
  local LC_ALL=C
  local s=${1//[[:cntrl:]]/}
  s=${s//$'\xc2'[$'\x80'-$'\x9f']/}
  printf -v "$2" %s "$s"
}

clean "$model" model
d=${cwd%/}; clean "${d##*/}" dir

[ -n "$cwd" ] || cwd=/nonexistent
if branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null); then :
else branch=$(git -C "$cwd" rev-parse --short -q HEAD 2>/dev/null); fi
clean "$branch" branch
remote=$(git -C "$cwd" remote get-url origin 2>/dev/null)
clean "$remote" remote

# Map a git remote URL (ssh, scp-style, git:// or http/https) to its web page.
web_url() {
  local u=${1%.git} a h
  web=
  case $u in
    git@ssh.dev.azure.com:v3/*)
      IFS=/ read -r org proj repo <<<"${u#*:v3/}"
      web="https://dev.azure.com/$org/$proj/_git/$repo" ;;
    *@vs-ssh.visualstudio.com:v3/*)
      IFS=/ read -r org proj repo <<<"${u#*:v3/}"
      web="https://$org.visualstudio.com/$proj/_git/$repo" ;;
    http://*|https://*)
      u=${u#*://}; a=${u%%/*}
      web="${1%%://*}://${a##*@}${u#"$a"}" ;;
    ssh://*|git://*)
      u=${u#*://}; a=${u%%/*}
      h=${a##*@}; web="https://${h%%:*}${u#"$a"}" ;;
    *://*) ;;
    [!/.]*:*)
      u=${u#*@}
      web="https://${u%%:*}/${u#*:}" ;;
  esac
  a=${web#*://}; a=${a%%/*}
  case $a in ''|.*) web= ;; esac
  # A URL that is still odd after mapping gets no link, so it cannot break out of the OSC 8 code.
  case $web in *[!A-Za-z0-9._~:/?#@!\$\&\'\(\)*+,\;=%-]*) web= ;; esac
}
[ -n "$remote" ] && web_url "$remote"

# Percent-encode $1 into $2. If $3 is set, keep "/" as is.
urienc() {
  local LC_ALL=C s=$1 o= c h i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~-]) o+=$c ;;
      /) if [ -n "$3" ]; then o+=/; else o+=%2F; fi ;;
      *) printf -v h '%02X' "'$c"; o+=%${h: -2} ;;
    esac
  done
  printf -v "$2" %s "$o"
}

host=${web#*://}; host=${host%%/*}
# Nerd Font glyphs in brand colours; the generic git glyph covers unknown hosts.
# GitHub's brand is black or white, so it uses the terminal's own foreground.
case $host in
  github.com|*.github.com) kind=github icon=$'\xef\x82\x9b' icol=1 ;;
  gitlab.com|*.gitlab.com|gitlab.*) kind=gitlab icon=$'\xef\x8a\x96' icol='38;2;252;109;38' ;;
  dev.azure.com|*.visualstudio.com) kind=azure icon=$'\xee\xaf\xa8' icol='38;2;0;120;215' ;;
  bitbucket.org|*.bitbucket.org) kind=bitbucket icon=$'\xef\x85\xb1' icol='38;2;38;132;255' ;;
  *) kind=other icon=$'\xee\x9c\x82' icol='38;2;240;80;50' ;;
esac

E=$'\033'
D="$E[2m│$E[0m"
R="$E[0m"
link() { out+="$E]8;;$1$E\\$2$E]8;;$E\\"; }

out="🤖 $E[1;35m$model$R $D 📁 "
if [ -d "$cwd" ]; then
  urienc "$cwd" f 1
  link "file://$f" "$E[34m$dir$R"
else
  out+="$E[34m$dir$R"
fi

if [ -n "$web" ]; then
  name=${web#*://*/}; name=${name/_git\//}
  out+=" $D $E[${icol}m$icon$R "
  link "$web" "$E[4;34m$name$R"
  if [ -n "$branch" ]; then
    case $kind in
      azure) urienc "$branch" b; tree="$web?version=GB$b" ;;
      gitlab) urienc "$branch" b 1; tree="$web/-/tree/$b" ;;
      bitbucket) urienc "$branch" b 1; tree="$web/src/$b" ;;
      *) urienc "$branch" b 1; tree="$web/tree/$b" ;;
    esac
    out+=" "$'\xee\x9c\xa5'" "
    link "$tree" "$E[4;32m$branch$R"
  fi
elif [ -n "$branch" ]; then
  out+=" $D 🌿 $E[32m$branch$R"
fi
if [ -n "$cost" ]; then printf -v cost '$%.2f' "$cost"; out+=" $D 💰 $E[33m$cost$R"; fi
[ -n "$mins" ] && out+=" $D ⏱ $E[36m${mins}m$R"
[ -n "$add" ] && out+=" $D ✏️ $E[32m+$add$R/$E[31m-${del:-0}$R"
if [ -n "$ctx" ]; then
  col=32; [ "$ctx" -ge 50 ] && col=33; [ "$ctx" -ge 80 ] && col=31
  out+=" $D 🧠 $E[${col}m$ctx%$R"
fi

printf '%s' "$out"
