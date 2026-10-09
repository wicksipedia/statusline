#!/usr/bin/env bash
in=$(cat)
j() { jq -r "$1 // empty" <<<"$in"; }

model=$(j .model.display_name)
dir=$(basename "$(j .workspace.current_dir)")
cost=$(j .cost.total_cost_usd)
ms=$(j .cost.total_duration_ms)
add=$(j .cost.total_lines_added)
del=$(j .cost.total_lines_removed)
ctx=$(j .context_window.used_percentage)

# Older builds lack context_window, so estimate from the last usage entry. Assume a 200k window.
if [ -z "$ctx" ]; then
  t=$(j .transcript_path)
  [ -f "$t" ] && ctx=$(tail -n 200 "$t" | jq -s '[.[] | .message.usage? // empty | (.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | last // empty | . / 2000 | floor' 2>/dev/null)
fi

branch=$(git -C "$(j .workspace.current_dir)" branch --show-current 2>/dev/null)

# Map a git remote URL (ssh or https; GitHub, GitLab, Azure DevOps) to its web page.
web_url() {
  local u=$1
  u=${u%.git}
  case $u in
    git@ssh.dev.azure.com:v3/*)
      IFS=/ read -r org proj repo <<<"${u#git@ssh.dev.azure.com:v3/}"
      echo "https://dev.azure.com/$org/$proj/_git/$repo" ;;
    *@vs-ssh.visualstudio.com:v3/*)
      IFS=/ read -r org proj repo <<<"${u#*:v3/}"
      echo "https://$org.visualstudio.com/$proj/_git/$repo" ;;
    http*://*)
      u=${u#*://}
      echo "https://${u#*@}" ;;
    ssh://*)
      u=${u#ssh://}; u=${u#*@}
      local host=${u%%/*}
      echo "https://${host%%:*}/${u#*/}" ;;
    *@*:*)
      u=${u#*@}
      echo "https://${u%%:*}/${u#*:}" ;;
  esac
}

remote=$(git -C "$(j .workspace.current_dir)" remote get-url origin 2>/dev/null)
web=$([ -n "$remote" ] && web_url "$remote")

# Nerd Font glyphs in brand colours; the generic git glyph covers unknown hosts.
# GitHub's brand is black or white, so it uses the terminal's own foreground.
case $web in
  *github*) icon=$'\xef\x82\x9b' icol=1 ;;
  *gitlab*) icon=$'\xef\x8a\x96' icol='38;2;252;109;38' ;;
  *dev.azure.com*|*visualstudio.com*) icon=$'\xee\xaf\xa8' icol='38;2;0;120;215' ;;
  *bitbucket*) icon=$'\xef\x85\xb1' icol='38;2;38;132;255' ;;
  *) icon=$'\xee\x9c\x82' icol='38;2;240;80;50' ;;
esac

D=$'\033[2m│\033[0m'
c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

out="🤖 $(c '1;35' "$model") $D 📁 $(c 34 "$dir")"
# OSC 8 hyperlink: link <url> <text>
link() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

if [ -n "$web" ]; then
  out+=" $D $(c "$icol" "$icon") $(link "$web" "$(c '4;34' "$(sed 's#^https://[^/]*/##; s#_git/##' <<<"$web")")")"
  if [ -n "$branch" ]; then
    b=$(jq -rn --arg b "$branch" '$b | @uri')
    bp=${b//"%2F"/\/}
    case $web in
      *dev.azure.com*|*visualstudio.com*) tree="$web?version=GB$b" ;;
      *gitlab*) tree="$web/-/tree/$bp" ;;
      *bitbucket*) tree="$web/src/$bp" ;;
      *) tree="$web/tree/$bp" ;;
    esac
    out+=" "$'\xee\x9c\xa5'" $(link "$tree" "$(c '4;32' "$branch")")"
  fi
elif [ -n "$branch" ]; then
  out+=" $D 🌿 $(c 32 "$branch")"
fi
[ -n "$cost" ] && out+=" $D 💰 $(c 33 "$(printf '$%.2f' "$cost")")"
[ -n "$ms" ] && out+=" $D ⏱ $(c 36 "$((ms / 60000))m")"
[ -n "$add" ] && out+=" $D ✏️ $(c 32 "+$add")/$(c 31 "-${del:-0}")"
if [ -n "$ctx" ]; then
  ctx=${ctx%.*}
  col=32; [ "$ctx" -ge 50 ] && col=33; [ "$ctx" -ge 80 ] && col=31
  out+=" $D 🧠 $(c "$col" "$ctx%")"
fi

printf '%s' "$out"
