#!/usr/bin/env python3
"""Sample module."""
import os
from typing import Optional

LIMIT = 10


class Widget:
    """A widget."""

    def __init__(self, name: str, size: Optional[int] = None) -> None:
        self.name = name
        self.size = size or LIMIT

    def render(self) -> str:
        pad = "\t"
        return f"{pad}{self.name}: {self.size}"


def main() -> int:
    for i in range(LIMIT):
        w = Widget(f"w{i}", size=i)
        print(w.render(), os.linesep, end="")
    return 0
