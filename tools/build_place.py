"""
Builds SkyForgeTycoon.rbxlx from default.project.json without needing Rojo.
Follows Rojo's file conventions:
    *.server.lua -> Script, *.client.lua -> LocalScript, *.lua -> ModuleScript,
    directories -> Folder.

    python3 tools/build_place.py            # writes build/SkyForgeTycoon.rbxlx
Open the result in Roblox Studio (File > Open from File).
"""
import json
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ref = [0]


def ref():
    _ref[0] += 1
    return f"RBX{_ref[0]:08X}"


def cdata(s):
    return "<![CDATA[" + s.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, children="", source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{props}</Properties>{children}</Item>\n'


def from_path(path, name):
    if os.path.isdir(path):
        kids = "".join(from_path(os.path.join(path, c), None) for c in sorted(os.listdir(path)))
        return item("Folder", name or os.path.basename(path), kids)
    base = os.path.basename(path)
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for suffix, cls in ((".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript"),
                        (".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if base.endswith(suffix):
            return item(cls, name or base[: -len(suffix)], source=src)
    return ""


def node(name, spec):
    cls = spec.get("$className", name)
    if "$path" in spec:
        return from_path(os.path.join(ROOT, spec["$path"]), name)
    kids = "".join(node(k, v) for k, v in spec.items() if not k.startswith("$"))
    return item(cls, name, kids)


def main():
    with open(os.path.join(ROOT, "default.project.json")) as f:
        project = json.load(f)
    tree = project["tree"]
    body = "".join(node(k, v) for k, v in tree.items() if not k.startswith("$"))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           + body + "</roblox>\n")
    out_dir = os.path.join(ROOT, "build")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, project["name"] + ".rbxlx")
    with open(out, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", out, f"({len(xml)//1024} KB)")


if __name__ == "__main__":
    main()
