"""Turn a demo run into a one-page HTML timeline of what the agents did.

Reads the shared remote of a run (WORKDIR/origin.git): every message, status change and
claim on the coordination branch, and every commit on the code branches, in the order
they were made. Uses only the standard library.

Usage: uv run python demo/timeline.py WORKDIR [-o timeline.html]
"""

import argparse
import html
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

COORDINATION = "coordination"
TYPE_LABELS = {
    "handover": "handover",
    "question": "question",
    "answer": "answer",
    "review": "review",
    "release-request": "release request",
    "released": "released",
    "returned": "returned",
    "heads-up": "heads-up",
}


@dataclass
class Event:
    """One thing that happened in the run."""

    time: int  # committer time, seconds since the epoch
    time_text: str
    kind: str  # message, status, claim, decision, commit
    actor: str
    title: str
    detail: str = ""
    meta: list[str] = field(default_factory=list)


def utc_text(stamp: int) -> str:
    """ISO time in UTC for a Unix time."""
    return datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def drop_repeated_status(events: list[Event]) -> list[Event]:
    """Drop a status event that repeats the line's previous status unchanged."""
    last_status: dict[str, tuple[str, str]] = {}
    kept = []
    for event in events:
        if event.kind == "status":
            key = (event.title, event.detail)
            if last_status.get(event.actor) == key:
                continue
            last_status[event.actor] = key
        kept.append(event)
    return kept


def git(repo: Path, *args: str) -> str:
    """Run git in a bare repository and return its output."""
    result = subprocess.run(
        ["git", "--git-dir", str(repo), *args], capture_output=True, text=True, check=True
    )
    return result.stdout


def header_value(text: str, key: str) -> str:
    """Value of a 'key: value' header line of a message, or an empty string."""
    match = re.search(rf"^{re.escape(key)}:\s*(.*)$", text, flags=re.M)
    return match.group(1).strip() if match else ""


def agent_of_lines(repo: Path) -> dict[str, str]:
    """The agent tool each line's latest status file names (field '- Agent:')."""
    agents = {}
    listing = git(repo, "ls-tree", "--name-only", f"{COORDINATION}:status/")
    for name in listing.split():
        if not name.endswith(".md"):
            continue
        text = git(repo, "show", f"{COORDINATION}:status/{name}")
        agent = header_value(text, "- Agent")
        agents[name[:-3]] = agent.replace(" (simulated by demo/replay.sh)", " (simulated)")
    return agents


def coordination_events(repo: Path) -> list[Event]:
    """Events from the coordination branch, one per added or changed file."""
    log = git(
        repo, "log", "--reverse", "--format=@@%ct %H %an", "--name-status", COORDINATION
    )
    events = []
    for block in log.split("@@")[1:]:
        lines = block.strip().splitlines()
        stamp, commit, author = lines[0].split(" ", 2)
        time_text = utc_text(int(stamp))
        commit_files = [line.split("\t") for line in lines[1:] if "\t" in line]
        for status, *paths in commit_files:
            path = paths[-1]
            event = coordination_event(repo, commit, int(stamp), time_text, author, status, path)
            if event:
                events.append(event)
    return events


def coordination_event(
    repo: Path, commit: str, stamp: int, time_text: str, author: str, status: str, path: str
) -> Event | None:
    """One event for a file change on the coordination branch, or None to skip it."""
    if path.endswith(".gitkeep") or path == "README.md":
        return None
    if path.startswith("messages/") and status == "A":
        text = git(repo, "show", f"{commit}:{path}")
        kind = header_value(text, "type")
        sender = header_value(text, "from") or author
        recipients = header_value(text, "to")
        body = text.split("\n\n", 1)[1] if "\n\n" in text else text
        return Event(
            stamp, time_text, "message", sender,
            f"{TYPE_LABELS.get(kind, kind)} to {recipients}", body.strip(), [Path(path).name],
        )
    if path.startswith("status/"):
        line = Path(path).stem
        # The status as it was at this commit, not the latest one
        text = git(repo, "show", f"{commit}:{path}") if status != "D" else ""
        state = header_value(text, "- State")
        task = header_value(text, "- Task")
        return Event(stamp, time_text, "status", line, f"status: {state}", task)
    if path.startswith("claims/"):
        task = Path(path).stem
        verb = {"A": "claims", "D": "releases", "M": "renews"}.get(status, "changes")
        return Event(stamp, time_text, "claim", author, f"{verb} {task}")
    if path.startswith("decisions/") and status == "A":
        text = git(repo, "show", f"{commit}:{path}")
        return Event(stamp, time_text, "decision", author, f"records {Path(path).name}", text.strip())
    return None


def commit_events(repo: Path) -> list[Event]:
    """Events for commits on the code branches (everything but coordination)."""
    refs = [
        ref for ref in git(repo, "for-each-ref", "--format=%(refname)", "refs/heads/").split()
        if ref != f"refs/heads/{COORDINATION}"
    ]
    if not refs:
        return []
    log = git(repo, "log", "--reverse", "--format=@@%ct %H %an %s", "--name-only", *refs)
    events = []
    for block in log.split("@@")[1:]:
        lines = block.strip().splitlines()
        stamp, sha, author, subject = lines[0].split(" ", 3)
        time_text = utc_text(int(stamp))
        branches = git(repo, "branch", "--contains", sha, "--format=%(refname:short)").split()
        events.append(Event(
            int(stamp), time_text, "commit", author, subject,
            "\n".join(lines[1:]), [sha[:7], ", ".join(b for b in branches if b != COORDINATION)],
        ))
    return events


def render(events: list[Event], agents: dict[str, str], run_name: str, summary: list[str]) -> str:
    """The whole page as HTML."""
    rows = []
    for event in events:
        tool = agents.get(event.actor, "")
        meta = " · ".join(html.escape(m) for m in event.meta if m)
        detail = (
            f"<details><summary>show</summary><pre>{html.escape(event.detail)}</pre></details>"
            if event.detail and event.kind in ("message", "decision", "commit") else
            f"<div class='note'>{html.escape(event.detail)}</div>" if event.detail else ""
        )
        rows.append(f"""
<li class="event {event.kind}">
  <div class="when">{html.escape(event.time_text[11:19])}</div>
  <div class="what">
    <div><span class="actor">{html.escape(event.actor)}</span>
      {f'<span class="tool">{html.escape(tool)}</span>' if tool else ''}
      <span class="kind">{event.kind}</span> {html.escape(event.title)}</div>
    {f'<div class="meta">{meta}</div>' if meta else ''}
    {detail}
  </div>
</li>""")
    summary_html = "".join(f"<li>{html.escape(item)}</li>" for item in summary)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MAP run timeline</title>
<style>
:root {{ --bg:#ffffff; --text:#1f2328; --muted:#59636e; --line:#d0d7de; --card:#f6f8fa;
  --message:#0969da; --commit:#1a7f37; --claim:#9a6700; --status:#8250df; --decision:#cf222e; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0d1117; --text:#e6edf3; --muted:#9198a1;
  --line:#3d444d; --card:#151b23; --message:#4493f8; --commit:#3fb950; --claim:#d29922;
  --status:#ab7df8; --decision:#f85149; }} }}
body {{ background:var(--bg); color:var(--text); margin:0 auto; max-width:900px; padding:24px 16px;
  font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; }}
h1 {{ font-size:22px; margin:0 0 4px; }} .sub {{ color:var(--muted); margin:0 0 16px; }}
ul.summary {{ background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px 12px 12px 32px; }}
ol {{ list-style:none; padding:0; margin:24px 0; }}
.event {{ display:grid; grid-template-columns:72px 1fr; gap:12px; padding:10px 0; border-top:1px solid var(--line); }}
.when {{ color:var(--muted); font:13px ui-monospace,SFMono-Regular,Menlo,monospace; padding-top:2px; }}
.actor {{ font-weight:600; }} .tool {{ color:var(--muted); font-size:13px; margin-left:4px; }}
.kind {{ font-size:12px; border-radius:10px; padding:1px 8px; margin:0 6px; color:#fff; }}
.message .kind {{ background:var(--message); }} .commit .kind {{ background:var(--commit); }}
.claim .kind {{ background:var(--claim); }} .status .kind {{ background:var(--status); }}
.decision .kind {{ background:var(--decision); }}
.meta, .note {{ color:var(--muted); font-size:13px; }}
.meta {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }}
details summary {{ cursor:pointer; color:var(--muted); font-size:13px; }}
pre {{ background:var(--card); border:1px solid var(--line); border-radius:6px; padding:10px;
  overflow-x:auto; font-size:12.5px; white-space:pre-wrap; }}
</style></head><body>
<h1>MAP run timeline</h1>
<p class="sub">{html.escape(run_name)}: every message, claim, status change and commit, in order.
Times are UTC.</p>
<ul class="summary">{summary_html}</ul>
<ol>{"".join(rows)}</ol>
</body></html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Write an HTML timeline of a demo run.")
    parser.add_argument("workdir", type=Path, help="the run's work directory (holds origin.git)")
    parser.add_argument("-o", "--output", type=Path, help="output file (default: WORKDIR/timeline.html)")
    args = parser.parse_args()
    repo = args.workdir / "origin.git"
    if not repo.is_dir():
        sys.exit(f"timeline.py: {repo} not found; give the work directory of a run")

    agents = agent_of_lines(repo)
    now = int(datetime.now(timezone.utc).timestamp())

    def order(event: Event) -> tuple[int, int]:
        # demo/replay.sh commits on a fixed clock in the future (setups made before
        # 2026-10-29 too): those come first, in their own order
        return (0, event.time) if event.time > now else (1, event.time)

    events = drop_repeated_status(sorted(coordination_events(repo) + commit_events(repo), key=order))
    for event in events:
        if event.time > now:
            event.meta.append("fixed demo clock")
    real_times = [e.time for e in events if e.time <= now]
    messages = [e for e in events if e.kind == "message"]
    main_head = git(repo, "log", "-1", "--format=%h %an: %s", "main").strip()
    tags = git(repo, "tag").split()
    summary = [
        "Agents: " + ", ".join(f"{line} ({tool})" for line, tool in sorted(agents.items())),
        f"{len(messages)} messages, {sum(e.kind == 'commit' for e in events)} commits",
        f"main: {main_head}",
        "Tags: " + (", ".join(tags) if tags else "none (a tag waits for the owner)"),
    ]
    if real_times:
        minutes = (max(real_times) - min(real_times)) / 60
        summary.append(f"From first to last event: {minutes:.0f} minutes")
    output = args.output or args.workdir / "timeline.html"
    output.write_text(render(events, agents, args.workdir.name, summary))
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
