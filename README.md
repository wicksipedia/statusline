# statusline

A status line for [Claude Code](https://claude.com/claude-code). It shows the model, folder, repo, branch, session cost, time, lines changed and context use on one line.

The repo and branch are clickable links in terminals that support OSC 8 hyperlinks, such as iTerm2, WezTerm, Kitty and Ghostty. The repo icon takes the colour of its host: GitLab orange, Azure DevOps blue, Bitbucket blue. GitHub uses your terminal's text colour, because its brand black disappears on dark themes.

Supported remotes: GitHub, GitLab, Azure DevOps (`dev.azure.com` and `visualstudio.com`) and Bitbucket, over SSH or HTTPS. Other hosts get a generic git icon and a best-guess web link. Local paths get no link.

## Requirements

- `bash`, `git` and [`jq`](https://jqlang.org)
- A [Nerd Font](https://www.nerdfonts.com) in your terminal, for the repo and branch icons

## Install

Copy the script into your Claude Code folder:

```sh
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/wicksipedia/statusline/main/statusline.sh
```

Add this to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline.sh"
}
```

The status line appears on the next refresh.

## Context use

The context figure turns yellow at 50% and red at 80%.

## Safety

The script strips terminal control codes from the model, folder, branch and remote before it prints them. If a remote URL still has odd characters after that, the script shows no repo link.

## Tests

Run `bash test.sh`. It builds throwaway repos in a temp folder and checks the links, icon colours and control-code stripping.

## Licence

MIT
