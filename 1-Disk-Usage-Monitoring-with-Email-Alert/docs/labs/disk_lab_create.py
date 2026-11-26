#!/usr/bin/env python3
"""Create new lab deployment targets without replacing existing installations.

Usage: python3 disk_lab_create.py directory TARGET
       python3 disk_lab_create.py files MODE SOURCE TARGET [MODE SOURCE TARGET ...]

Modes: 600, 644, 755. Exit: 0 success, 1 validation/refusal, 2 partial I/O failure.
Run from a reviewed checkout; parent directories must be administrator-controlled.
"""

import logging
import os
from pathlib import Path
import stat
import sys

LOGGER = logging.getLogger("disk-lab-create")


def refuse_existing(target: Path) -> None:
    """lstat distinguishes absence from errors and includes dangling symlinks."""
    try:
        target.lstat()
    except FileNotFoundError:
        return
    raise FileExistsError(f"Refusing existing target: {target}")


def main(argv: list[str]) -> int:
    if argv == ["--help"]:
        sys.stdout.write(__doc__ + "\n")
        return 0
    directory = len(argv) == 2 and argv[0] == "directory"
    files = len(argv) >= 4 and argv[0] == "files" and (len(argv) - 1) % 3 == 0
    if not directory and not files:
        LOGGER.error("Use --help for directory or files syntax.")
        return 1
    entries = []
    try:
        if directory:
            entries = [(Path(argv[1]), 0o700, None)]
        else:
            for index in range(1, len(argv), 3):
                mode, source, target = argv[index:index + 3]
                if mode not in {"600", "644", "755"}:
                    LOGGER.error("Modes must be 600, 644 or 755.")
                    return 1
                entries.append((Path(target), int(mode, 8), Path(source)))
        targets = [os.path.abspath(target) for target, _, _ in entries]
        if len(set(targets)) != len(targets):
            LOGGER.error("Duplicate targets are not allowed.")
            return 1
        prepared = []
        for target, mode, source in entries:
            refuse_existing(target)
            if not stat.S_ISDIR(target.parent.stat().st_mode):
                raise NotADirectoryError(str(target.parent))
            # Read all inputs before any destination is created; never log their bytes.
            content = source.read_bytes() if source is not None else None
            prepared.append((target, mode, content))
    except FileExistsError as error:
        LOGGER.error("%s", error)
        return 1
    except OSError as error:
        LOGGER.error("Preflight failed: %s", error)
        return 1

    # This is a child process; a fixed private umask cannot alter the caller's shell.
    os.umask(0o077)
    try:
        for target, mode, content in prepared:
            if directory:
                target.mkdir(mode=mode)
            else:
                # O_EXCL also refuses a target introduced after preflight.
                descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
                with os.fdopen(descriptor, "wb") as stream:
                    os.fchmod(stream.fileno(), mode)
                    stream.write(content)
            LOGGER.info("Created: %s", target)
    except OSError as error:
        # Do not remove files on failure: preserve evidence for manual recovery.
        LOGGER.error("Creation failed; review any targets already created: %s", error)
        return 2
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    sys.exit(main(sys.argv[1:]))
