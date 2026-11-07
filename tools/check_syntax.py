"""
Approximate Luau syntax check without the Luau toolchain: rewrites the
Luau-only syntax this project uses (type annotations, compound assignment,
`type` declarations) into plain Lua, then parses every file with a real Lua
parser (pip install lupa). Catches unbalanced blocks, typos, bad tokens.

    python3 tools/check_syntax.py
"""
import os
import re
import sys

import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPE_CHARS = r"[\w\.\?\{\}\[\]\(\)\|:, ]+?"


def strip_types(src):
    # multi-line `type X = { ... }`
    src = re.sub(r"^type \w+ = \{.*?^\}\n", "", src, flags=re.S | re.M)
    out = []
    for line in src.split("\n"):
        s = line
        # function signatures: params and return type
        m = re.match(r"^(\s*(?:local\s+)?function\s*[\w\.:]*\s*)\((.*)\)\s*(:\s*[^\n]+)?$", s)
        if not m:
            m = re.match(r"^(.*function\s*)\((.*?)\)\s*(:\s*[\w\?\.]+)?(.*)$", s)
        if m:
            params = re.sub(r"(\w+)\s*:\s*[\w\.\?\{\}\[\] ]+", r"\1", m.group(2))
            rest = m.group(4) if m.lastindex and m.lastindex >= 4 and m.group(4) else ""
            s = f"{m.group(1)}({params}){rest}"
        # local annotations
        s = re.sub(r"^(\s*local\s+\w+)\s*:\s*[^=]+?(\s*=)", r"\1\2", s)
        s = re.sub(r"^(\s*local\s+\w+)\s*:\s*[\w\.\?]+\s*$", r"\1", s)
        # compound assignment
        m = re.match(r"^(\s*)([\w\.\[\]\"']+)\s*([+\-*/])=\s*(.+)$", s)
        if m:
            s = f"{m.group(1)}{m.group(2)} = {m.group(2)} {m.group(3)} ({m.group(4)})"
        out.append(s)
    return "\n".join(out)


def main():
    lua = lupa.LuaRuntime()
    load = lua.eval("function(s, n) local f, e = load(s, n) return e end")
    bad = 0
    files = 0
    for d, _, fs in os.walk(os.path.join(ROOT, "src")):
        for f in fs:
            if f.endswith(".lua"):
                p = os.path.join(d, f)
                files += 1
                err = load(strip_types(open(p).read()), "=" + os.path.relpath(p, ROOT))
                if err:
                    bad += 1
                    print("FAIL", err)
    print(f"{files} files checked, {bad} with errors")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
