#!/usr/bin/env python3
"""Refuse to replace a bundle whose executable is still running."""
from pathlib import Path
import subprocess
import sys


def require_idle_destination(executable, running_commands):
    destination = Path(executable).resolve()
    for command in running_commands:
        command = command.strip()
        if not command.startswith("/"):
            continue
        running = Path(command).resolve()
        # The process name can change during a rebrand. Any executable in this
        # bundle's MacOS directory still makes replacing that bundle unsafe.
        same_app = (destination.parent.name == "MacOS"
                    and destination.parent.parent.name == "Contents"
                    and running.parent == destination.parent)
        if running == destination or same_app:
            raise RuntimeError(
                f"Refusing to replace the running app at {destination.parent.parent.parent}. "
                "Quit that copy first, or set GLEE_DESTINATION to a separate build location."
            )


def check(executable):
    # comm contains executable paths only, never process arguments or secrets.
    result = subprocess.run(["/bin/ps", "-axo", "comm="], check=True,
                            capture_output=True, text=True)
    require_idle_destination(executable, result.stdout.splitlines())


def main():
    if len(sys.argv) != 2:
        print("Usage: check_build_destination.py /path/App.app/Contents/MacOS/App", file=sys.stderr)
        return 2
    try:
        check(sys.argv[1])
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError):
        print("Could not inspect running apps. Refusing to replace the app bundle.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
