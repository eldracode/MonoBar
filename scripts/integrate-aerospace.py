#!/usr/bin/env python3
"""Back up the active AeroSpace config and add MonoBar event hooks."""

from datetime import datetime
import json
from pathlib import Path
import re
import shutil
import tomllib

config = Path.home() / ".aerospace.toml"
app = Path.home() / "Applications/MonoBar.app"
source = config.read_text()
stamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
backup = config.with_name(f"{config.name}.backup-{stamp}")
shutil.copy2(config, backup)

focus_command = (
    '  "exec-and-forget /bin/sh -c \'printf focus | '
    "nc -U $HOME/.config/monobar/events.sock\'\",\n"
)

source = re.sub(r"^on-focused-workspace-changed = .*\n", "", source, flags=re.MULTILINE)

startup = f"after-startup-command = ['exec-and-forget open -a {app}']"
source = re.sub(r"^after-startup-command = .*$", startup, source, count=1, flags=re.MULTILINE)

workspace_match = re.search(r"^exec-on-workspace-change = (.+)$", source, flags=re.MULTILINE)
if not workspace_match:
    raise SystemExit("Could not find the existing exec-on-workspace-change command")
workspace_argv = tomllib.loads("hook = " + workspace_match.group(1))["hook"]
if len(workspace_argv) < 3 or workspace_argv[1] != "-c":
    raise SystemExit("The existing exec-on-workspace-change hook has an unexpected command shape")
if "printf workspace | nc -U $HOME/.config/monobar/events.sock" not in workspace_argv[2]:
    workspace_argv[2] = re.sub(r" && printf workspace \| nc -U [^ ]+", "", workspace_argv[2])
    workspace_argv[2] += " && printf workspace | nc -U $HOME/.config/monobar/events.sock"
source = source[:workspace_match.start(1)] + json.dumps(workspace_argv) + source[workspace_match.end(1):]

if "printf focus | nc -U $HOME/.config/monobar/events.sock" not in source:
    marker = "on-focus-changed = ["
    start = source.find(marker)
    if start < 0:
        raise SystemExit("Could not find the existing on-focus-changed callback")
    close = source.find("\n]", start)
    if close < 0:
        raise SystemExit("Could not find the end of the on-focus-changed callback")
    source = source[:close] + "\n" + focus_command.rstrip("\n") + source[close:]

config.write_text(source)
print(f"Backup: {backup}")
print(f"Updated: {config}")
