#!/usr/bin/env python3
"""Launcher script for EventOps daemon from top of folder 11."""

import os
import sys

# Add EventOps directory to sys.path
current_dir = os.path.dirname(os.path.abspath(__file__))
eventops_dir = os.path.join(current_dir, "EventOps")
if eventops_dir not in sys.path:
    sys.path.insert(0, eventops_dir)

os.chdir(eventops_dir)

from eventops import main

if __name__ == "__main__":
    main()
