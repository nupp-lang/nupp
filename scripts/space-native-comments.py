"""Separate leading comment groups from the preceding line of native code."""

import re
import sys
from pathlib import Path


# Match literals as tokens so their contents cannot be mistaken for comments.
# The assembler sources use the same comment syntax as their C preprocessor.
C_TOKENS = re.compile(
    rb'(?<!\w)(?:u8|[LuU])?R"(?P<delimiter>[^\s()\\]{0,16})\(.*?\)(?P=delimiter)"'
    rb'|"(?:\\(?:\r\n|.)|[^"\\\r\n])*"'
    rb"|(?<!\w)(?:u8|[LuU])?'(?:\\(?:\r\n|.)|[^'\\\r\n])*'"
    rb'|(?P<comment>//(?:\\\r?\n|[^\r\n])*|/\*.*?\*/)',
    re.DOTALL,
)
DEF_COMMENTS = re.compile(rb"(?P<comment>;[^\r\n]*)")
WHITESPACE = re.compile(rb"\s*")


def space_comments(source, tokens):
    chunks = []
    copied = 0
    previous_comment_end = 0

    for token in tokens.finditer(source):
        if token.lastgroup != "comment":
            continue

        start = token.start()
        line = source.rfind(b"\n", 0, start) + 1
        follows_comment = WHITESPACE.fullmatch(source, previous_comment_end, start)
        if source[line:start].strip() and not follows_comment:
            continue
        previous_comment_end = token.end()
        if not line or follows_comment:
            continue

        previous_line = source.rfind(b"\n", 0, line - 1) + 1
        previous = source[previous_line:line].rstrip(b"\r\n")
        # A blank here would terminate the continued preprocessing line.
        if not previous.strip() or previous.rstrip().endswith(b"\\"):
            continue

        newline = source[previous_line + len(previous):line]
        chunks.extend((source[copied:line], newline))
        copied = line

    return b"".join(chunks + [source[copied:]])


def main():
    for name in sys.argv[1:]:
        path = Path(name)
        source = path.read_bytes()
        tokens = DEF_COMMENTS if path.suffix == ".def" else C_TOKENS
        formatted = space_comments(source, tokens)
        if source != formatted:
            path.write_bytes(formatted)


if __name__ == "__main__":
    main()
