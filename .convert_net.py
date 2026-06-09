#!/usr/bin/env python3
"""One-shot converter: umsg/usermessage -> net library, plus misc GM13+ API fixes."""
import os
import re
import sys

ROOT = "gamemodes/noxctf"

WRITE_SIMPLE = {
    "Entity": "WriteEntity",
    "String": "WriteString",
    "Float": "WriteFloat",
    "Vector": "WriteVector",
    "VectorNormal": "WriteNormal",
    "Angle": "WriteAngle",
    "Bool": "WriteBool",
}
WRITE_INT = {"Long": 32, "Short": 16, "Char": 8}

READ_SIMPLE = {
    "ReadEntity": "net.ReadEntity()",
    "ReadString": "net.ReadString()",
    "ReadFloat": "net.ReadFloat()",
    "ReadVector": "net.ReadVector()",
    "ReadVectorNormal": "net.ReadNormal()",
    "ReadAngle": "net.ReadAngle()",
    "ReadBool": "net.ReadBool()",
}
READ_INT = {"ReadLong": 32, "ReadShort": 16, "ReadChar": 8}

UM_VARS = r"(?:um|message|data)"


def find_balanced(s, start):
    """start = index of '('. Returns index of matching ')'."""
    depth = 0
    for i in range(start, len(s)):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def convert_senders(text):
    # umsg.Start("name"[, recipient]) ... umsg.End()
    recipients = []  # stack of recipient expressions (None = broadcast)
    out = []
    i = 0
    while True:
        m = re.search(r"umsg\.(Start|End|" + "|".join(list(WRITE_SIMPLE) + list(WRITE_INT)) + r")\(", text[i:])
        if not m:
            out.append(text[i:])
            break
        abs_open = i + m.end() - 1
        close = find_balanced(text, abs_open)
        assert close != -1, "unbalanced parens near: " + text[i + m.start():i + m.start() + 80]
        out.append(text[i:i + m.start()])
        kind = m.group(1)
        args = text[abs_open + 1:close]
        if kind == "Start":
            name_m = re.match(r'\s*("(?:[^"\\]|\\.)*")\s*(?:,\s*(.+))?$', args, re.S)
            assert name_m, "non-literal umsg.Start name: " + args
            name, recip = name_m.group(1), name_m.group(2)
            recipients.append(recip.strip() if recip else None)
            out.append("net.Start(%s)" % name)
        elif kind == "End":
            recip = recipients.pop() if recipients else None
            out.append("net.Send(%s)" % recip if recip else "net.Broadcast()")
        elif kind in WRITE_INT:
            out.append("net.WriteInt(%s, %d)" % (args, WRITE_INT[kind]))
        else:
            out.append("net.%s(%s)" % (WRITE_SIMPLE[kind], args))
        i = close + 1
    return "".join(out)


def convert_receivers(text):
    text = re.sub(r"usermessage\.Hook\(", "net.Receive(", text)
    # inline handlers: net.Receive("X", function(um)  ->  function()
    text = re.sub(r'(net\.Receive\("[^"]+",\s*function)\(' + UM_VARS + r"\)", r"\1()", text)
    # read calls
    for old, new in READ_SIMPLE.items():
        text = re.sub(r"\b" + UM_VARS + r":" + old + r"\(\)", new, text)
    for old, bits in READ_INT.items():
        text = re.sub(r"\b" + UM_VARS + r":" + old + r"\(\)", "net.ReadInt(%d)" % bits, text)
    return text


def convert_misc(text):
    # deprecated/removed APIs
    text = re.sub(r"\bself\.Entity\b", "self", text)
    text = re.sub(r"\bValidPanel\(", "IsValid(", text)
    text = re.sub(r"\b(Set|Get)Networked(Int|Float|String|Entity|Bool|Vector|Angle)\b", r"\1NW\2", text)
    return text


def main():
    changed = []
    for dirpath, _, files in os.walk(ROOT):
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
                orig = f.read()
            text = orig
            if "umsg." in text:
                text = convert_senders(text)
            if "usermessage." in text or re.search(r"\b" + UM_VARS + r":Read", text):
                text = convert_receivers(text)
            text = convert_misc(text)
            if text != orig:
                with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
                    f.write(text)
                changed.append(path)
    print("changed %d files" % len(changed))
    for p in changed:
        print("  " + p)


if __name__ == "__main__":
    sys.exit(main())
