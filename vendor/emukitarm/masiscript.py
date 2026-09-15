#!/usr/bin/env python3
"""Compatibility entry — use emukitarm.py / EmuKitARM."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parent / "emukitarm.py"), run_name="__main__")
