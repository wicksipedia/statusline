#!/usr/bin/env bash
# Run with: bash test.sh
S=$(cd "$(dirname "$0")" && pwd)/statusline.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

check() { # name, output, expected substring
  if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: want '$3'"; fail=1; fi
}
reject() { # name, output, substring that must be absent
  if [[ $2 != *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: found '$3'"; fail=1; fi
}

# Print the status line for a temp repo with remote $1 on branch $2.
repo() {
  local d=$T/r$RANDOM
  mkdir -p "$d" && git -C "$d" init -q -b "$2" && git -C "$d" config remote.origin.url "$1"
  printf '{"workspace":{"current_dir":"%s"}}' "$d" | bash "$S"
}

L=$'\e]8;;'
check github     "$(repo git@github.com:a/b.git f/é)"            "${L}https://github.com/a/b/tree/f/%C3%A9"
check token      "$(repo https://tok@github.com/a/b.git main)"   "${L}https://github.com/a/b"$'\e'
check gitlab     "$(repo git@gitlab.com:g/github-mirror.git m)"  "${L}https://gitlab.com/g/github-mirror/-/tree/m"
check ssh-port   "$(repo ssh://git@gitlab.com:22/g/p.git m)"     "${L}https://gitlab.com/g/p"$'\e'
check azure      "$(repo git@ssh.dev.azure.com:v3/o/p/r f/x)"    "${L}https://dev.azure.com/o/p/_git/r?version=GBf%2Fx"
check vsts       "$(repo me@vs-ssh.visualstudio.com:v3/o/p/r m)" "${L}https://o.visualstudio.com/p/_git/r"
check bitbucket  "$(repo git@bitbucket.org:a/b.git m)"           "${L}https://bitbucket.org/a/b/src/m"
check gitlab-col "$(repo git@gitlab.com:g/p.git m)"              $'\e[38;2;252;109;38m'
reject local     "$(repo /a/b:c m)"                              "${L}http"
reject evil-url  "$(repo $'https://github.com/a/b\e\\\e[2J' m)"  "${L}http"

mkdir -p "$T/my dir"
check folder-link "$(printf '{"workspace":{"current_dir":"%s"}}' "$T/my dir" | bash "$S")" "${L}file://${T// /%20}/my%20dir"$'\e'
reject no-folder-link "$(printf '{"workspace":{"current_dir":"/nope/x"}}' | bash "$S")" "${L}file://"

out=$(printf '{"model":{"display_name":"a\\u001b[2J\\u009bb"},"workspace":{"current_dir":"/x/"}}' | LC_ALL=C bash "$S")
reject c0-strip "$out" $'\e[2J'
reject c1-strip "$out" $'\xc2\x9b'

out=$(printf '{"model":"str","cost":{"total_cost_usd":1.5},"context_window":{"used_percentage":1e30}}' | bash "$S" 2>&1)
check bad-type-keeps-cost "$out" '$1.50'
check ctx-capped          "$out" '100%'
reject no-errors          "$out" 'expected'

exit $fail
