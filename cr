#!/usr/bin/env bash
#
# cr - Claude Resume picker
# Shows recent Claude Code conversations, lets you pick one to resume.
# Usage: cr [count]  (default: 40)
#

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
FZF_BIN="$HOME/.fzf/bin/fzf"
CR_MAX="${1:-40}"

if [[ ! -d "$CLAUDE_DIR/projects" ]]; then
    echo "No Claude projects found at $CLAUDE_DIR/projects"
    exit 1
fi

if [[ ! -x "$FZF_BIN" ]]; then
    echo "fzf not found at $FZF_BIN"
    echo "Install: git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --bin"
    exit 1
fi

CR_TMPDIR=$(mktemp -d /tmp/cr.XXXXXX)
trap 'rm -rf "$CR_TMPDIR"' EXIT

SESSION_LIST=$(python3 - "$CR_MAX" "$CR_TMPDIR" << 'PYEOF'
import json, os, re, sys
from datetime import datetime, timezone
from pathlib import Path

claude_dir = Path.home() / ".claude" / "projects"
max_sessions = int(sys.argv[1])
tmpdir = sys.argv[2]
home = str(Path.home())

sessions = []
seen_sids = set()

# ── Phase 1: indexed sessions (fast) ───────────────────────────────
for index_file in claude_dir.glob("*/sessions-index.json"):
    try:
        data = json.loads(index_file.read_text())
        for entry in data.get("entries", []):
            if entry.get("isSidechain"):
                continue
            sid = entry.get("sessionId", "")
            if sid:
                seen_sids.add(sid)
            sessions.append(entry)
    except (json.JSONDecodeError, IOError):
        continue

# ── Phase 2: unindexed .jsonl files ────────────────────────────────
for proj_dir in claude_dir.iterdir():
    if not proj_dir.is_dir():
        continue
    if (proj_dir / "sessions-index.json").exists():
        continue

    for jf in sorted(proj_dir.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True):
        sid = jf.stem
        if sid in seen_sids:
            continue
        seen_sids.add(sid)

        try:
            stat = jf.stat()
            mtime = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)

            first_prompt = ""
            project_path = ""
            git_branch = ""
            msg_count = 0
            found_prompt = False

            with open(jf) as f:
                for ln, line in enumerate(f):
                    try:
                        d = json.loads(line.strip())
                    except json.JSONDecodeError:
                        continue

                    dtype = d.get("type", "")
                    if dtype in ("user", "assistant"):
                        msg_count += 1
                    if not project_path and d.get("cwd"):
                        project_path = d["cwd"]
                    if not git_branch and d.get("gitBranch"):
                        git_branch = d["gitBranch"]

                    if not found_prompt and dtype == "user":
                        msg = d.get("message", {})
                        content = msg.get("content", "") if isinstance(msg, dict) else msg
                        text = ""
                        if isinstance(content, list):
                            for c in content:
                                if isinstance(c, dict) and c.get("type") == "text":
                                    text = c["text"]
                                    break
                        else:
                            text = str(content)
                        # Skip boilerplate and interrupted messages
                        if text and "[Request interrupted" not in text \
                                and "Caveat: The messages below" not in text \
                                and not text.startswith("<local-command") \
                                and not text.startswith("<command-name>"):
                            first_prompt = text
                            found_prompt = True

                    # After 200 lines, estimate remaining
                    if ln > 200 and found_prompt:
                        remaining = sum(1 for _ in f)
                        msg_count += remaining // 3
                        break

            sessions.append({
                "sessionId": sid,
                "firstPrompt": first_prompt,
                "summary": "",
                "messageCount": msg_count,
                "modified": mtime.isoformat(),
                "projectPath": project_path,
                "gitBranch": git_branch,
            })
        except (IOError, OSError):
            continue

# ── Sort, filter, display ───────────────────────────────────────────

def parse_date(s):
    try:
        raw = s.get("modified", "2000-01-01T00:00:00Z")
        if isinstance(raw, (int, float)):
            return datetime.fromtimestamp(raw / 1000, tz=timezone.utc)
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except:
        return datetime.min.replace(tzinfo=timezone.utc)

# Filter out empty sessions (0 messages and no prompt)
sessions = [s for s in sessions
            if s.get("messageCount", 0) > 0
            or s.get("firstPrompt")
            or s.get("summary")]

sessions.sort(key=parse_date, reverse=True)
sessions = sessions[:max_sessions]
now = datetime.now(timezone.utc)

def clean(text):
    """Clean up prompt text for display."""
    if not text:
        return "(no prompt)"
    # Strip XML tags and normalize whitespace early
    text = re.sub(r'<[^>]+>', ' ', text)
    text = text.strip()
    # Strip common boilerplate
    text = re.sub(r'\[Request interrupted[^\]]*\]', '(interrupted)', text)
    text = re.sub(r'^Caveat:.*?generated by the user[^.]*\.?\s*', '', text, flags=re.S)
    text = re.sub(r'^Implement the following plan:\s*#?\s*', '', text, flags=re.S)
    text = re.sub(r'^orchestrator\s+/orchestrator\s+', '', text, flags=re.I)
    text = re.sub(r'^\s*#\s*', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text[:200] if text else "(no prompt)"

def ago(mod):
    d = now - mod
    if d.days > 365: return f"{d.days // 365}y"
    if d.days > 30:  return f"{d.days // 30}mo"
    if d.days > 0:   return f"{d.days}d"
    h = d.seconds // 3600
    if h > 0: return f"{h}h"
    m = d.seconds // 60
    return f"{m}m" if m > 0 else "now"

for i, s in enumerate(sessions):
    sid     = s.get("sessionId", "")
    summary = (s.get("summary") or "").replace("\n", " ").strip()
    prompt  = clean(s.get("firstPrompt", ""))
    msgs    = s.get("messageCount", 0)
    proj    = s.get("projectPath", "")
    branch  = s.get("gitBranch", "")
    mod     = parse_date(s)
    mod_str = mod.strftime("%b %d %I:%M%p")

    if proj.startswith(home):
        proj = "~" + proj[len(home):]
    proj = proj or "~"

    label = summary if summary else prompt
    if len(label) > 55:
        label = label[:55] + "…"
    proj_short = proj if len(proj) <= 22 else "…" + proj[-21:]

    line = f"{i+1:>3}  {ago(mod):>4}  {msgs:>3}msg  {proj_short:<22}  {label}"

    # Keep raw project path for cd-before-resume
    proj_raw = s.get("projectPath", "") or ""

    detail = (
        f"\\033[1;36m━━━ Session Details ━━━━━━━━━━━━━━━━━━━━━━━━━\\033[0m\\n"
        f"\\n"
        f"\\033[1;33mSummary\\033[0m\\n"
        f"  {summary or '(none)'}\\n"
        f"\\n"
        f"\\033[1;33mFirst Message\\033[0m\\n"
        f"  {prompt}\\n"
        f"\\n"
        f"\\033[1;33mProject\\033[0m    {proj}\\n"
        f"\\033[1;33mBranch\\033[0m     {branch or '(none)'}\\n"
        f"\\033[1;33mMessages\\033[0m   ~{msgs}\\n"
        f"\\033[1;33mModified\\033[0m   {mod_str}\\n"
        f"\\033[1;33mSession\\033[0m    {sid}"
    )

    Path(tmpdir, sid).write_text(detail)
    print(f"{line}\t{sid}\t{proj_raw}")
PYEOF
)

if [[ -z "$SESSION_LIST" ]]; then
    echo "No sessions found. Starting new Claude session..."
    exec claude
fi

HEADER="  cr — Claude Resume Picker
  ──────────────────────────────────────────────────────────
  ENTER: resume  |  ESC/ctrl-c: new session  |  type to search
  ──────────────────────────────────────────────────────────
   #   AGO  MSGS  PROJECT                SUMMARY"

SELECTED=$(echo "$SESSION_LIST" | \
    "$FZF_BIN" \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview="echo -e \"\$(cat '$CR_TMPDIR'/{2} 2>/dev/null)\"" \
        --preview-window=right:45%:wrap \
        --header="$HEADER" \
        --header-lines=0 \
        --reverse \
        --no-sort \
        --height=100% \
        --border=rounded \
        --border-label=" Claude Sessions " \
        --border-label-pos=3 \
        --prompt="search: " \
        --pointer="▶" \
        --marker="●" \
        --color="header:bold:cyan,pointer:yellow,prompt:yellow,border:blue,label:blue:bold" \
        --bind="ctrl-j:down,ctrl-k:up" \
    || true)

if [[ -z "$SELECTED" ]]; then
    echo "Starting new Claude session..."
    exec claude
fi

SESSION_ID=$(echo "$SELECTED" | awk -F$'\t' '{print $2}')
PROJECT_DIR=$(echo "$SELECTED" | awk -F$'\t' '{print $3}')

if [[ -z "$SESSION_ID" ]]; then
    echo "Starting new Claude session..."
    exec claude
fi

# cd to the project directory so claude resumes in the right context
if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    cd "$PROJECT_DIR"
fi

echo "Resuming session $SESSION_ID in ${PROJECT_DIR:-$(pwd)}..."
exec claude --resume "$SESSION_ID"
