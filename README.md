# cr - Claude Resume

A fast, interactive session picker for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Browse your recent conversations, preview details, and resume any session from your terminal.

![cr demo](https://img.shields.io/badge/shell-bash-blue) ![fzf](https://img.shields.io/badge/requires-fzf-green) ![python](https://img.shields.io/badge/requires-python3-yellow)

## The Problem

Claude Code stores conversation sessions across `~/.claude/projects/`. When you want to pick up where you left off, you need to remember session IDs or dig through files manually. `claude --resume` exists, but you need to already know the session ID.

## The Solution

`cr` gives you a searchable, previewable list of all your Claude Code sessions:

<p align="center">
  <img src="demo.svg" alt="cr demo — interactive session picker with preview pane" width="960"/>
</p>

Select a session and you're back in it. Press `ESC` to start a fresh session instead.

## Features

- **Finds every session** — scans both Claude's session indexes and raw `.jsonl` files, so nothing falls through the cracks (including currently-running sessions)
- **AI-generated summaries** — optionally uses Claude Haiku to generate short topic labels for sessions that don't have one, with a local cache so each session is only summarized once
- **Preview pane** — see the full first message, project path, git branch, message count, and session ID before resuming
- **Fuzzy search** — type to filter across all sessions by any field
- **Auto-cd** — resumes the session in its original project directory

## How It Works

1. **Scans `~/.claude/projects/`** for session index files and raw `.jsonl` conversation logs
2. **Parses session metadata** — extracts the first user prompt, message count, project path, git branch, and timestamps
3. **Generates summaries** — calls Claude Haiku (if an API key is available) to produce 3-8 word topic labels for sessions missing a summary, cached locally at `~/.claude/cache/cr-summaries.json`
4. **Presents sessions via fzf** with a formatted list showing age, message count, project directory, and summary
5. **Resumes the selected session** by `cd`-ing to the project directory and calling `claude --resume <session-id>`

### Data Sources (Two Phases)

- **Phase 1 — Indexed sessions**: Reads `sessions-index.json` files that Claude Code maintains. Fast to parse, pre-extracted metadata.
- **Phase 2 — Raw session files**: Scans all `.jsonl` files across every project directory, picking up any sessions not covered by an index (including active/running sessions). Reads the first ~200 lines to extract metadata, then estimates total message count from the remainder.

Deduplication ensures no session appears twice regardless of whether it's in an index, a `.jsonl` file, or both.

### Filtering

- Skips sidechain sessions (internal Claude Code branches)
- Strips XML tags, boilerplate prefixes, and interrupted-request markers from prompts
- Filters out empty sessions (no messages and no prompt)

## Installation

### Prerequisites

- **bash** (4.0+)
- **python3** (3.6+)
- **fzf** — install it if you don't have it:
  ```bash
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --bin
  ```
- **Claude Code** — with existing sessions in `~/.claude/projects/`

### Optional (for AI summaries)

- **anthropic** Python package: `pip install anthropic`
- An `ANTHROPIC_API_KEY` set in your environment or in `~/.anthropic_env`

Without these, `cr` works fine — it just shows the first prompt instead of a generated summary.

### Install cr

```bash
# Clone and symlink to your PATH
git clone https://github.com/phelix001/Claude-Resume.git
ln -sf "$(pwd)/Claude-Resume/cr" ~/.local/bin/cr
```

Or copy directly:

```bash
curl -o ~/.local/bin/cr https://raw.githubusercontent.com/phelix001/Claude-Resume/main/cr && chmod +x ~/.local/bin/cr
```

## Usage

```bash
# Show the 40 most recent sessions (default)
cr

# Show the 100 most recent sessions
cr 100

# Show only the 10 most recent
cr 10
```

### Controls

| Key | Action |
|-----|--------|
| `Enter` | Resume the selected session |
| `ESC` / `Ctrl-C` | Cancel and start a new Claude session |
| Type | Fuzzy search across all sessions |
| `Ctrl-j` / `Ctrl-k` | Navigate up/down |

## Configuration

`cr` uses `~/.fzf/bin/fzf` by default. If your `fzf` is installed elsewhere, edit the `FZF_BIN` variable at the top of the script.

## License

MIT
