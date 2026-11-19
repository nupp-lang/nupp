"""Exercise the native comment formatter on syntax absent from the tree."""

from pathlib import Path
from runpy import run_path
import unittest


ROOT = Path(__file__).resolve().parents[2]
FORMATTER = run_path(str(ROOT / "scripts" / "space-native-comments.py"))
space_comments = FORMATTER["space_comments"]
C_TOKENS = FORMATTER["C_TOKENS"]
DEF_COMMENTS = FORMATTER["DEF_COMMENTS"]


class CommentSpacingTest(unittest.TestCase):
    def assert_spacing(self, source, expected, tokens=C_TOKENS):
        formatted = space_comments(source, tokens)
        self.assertEqual(formatted, expected)
        self.assertEqual(space_comments(formatted, tokens), expected)

    def test_leading_group_after_trailing_comment(self):
        self.assert_spacing(
            b"/** File. */\nint a; /* Trailing. */\n/* Leading. */\n"
            b"// Same group.\nint b;\n/** Next. */\nint c;\n",
            b"/** File. */\nint a; /* Trailing. */\n\n/* Leading. */\n"
            b"// Same group.\nint b;\n\n/** Next. */\nint c;\n",
        )

    def test_preserves_line_endings_and_macro_continuation(self):
        macro = b"#define VALUE " + b"\\\r\n" + b"  /* macro comment */ 1\r\n"
        self.assert_spacing(
            macro + b"/* Leading. */\r\nint value = VALUE;\r\n",
            macro + b"\r\n/* Leading. */\r\nint value = VALUE;\r\n",
        )

    def test_ignores_comment_markers_in_raw_strings(self):
        raw = b'auto raw = u8R"text(\nraw\n// raw\n/* raw */\n)text";\n'
        self.assert_spacing(
            raw + b"// Leading.\nint value = 1'000;\n",
            raw + b"\n// Leading.\nint value = 1'000;\n",
        )

    def test_module_definition_comments(self):
        self.assert_spacing(
            b"; File.\nEXPORTS\n    a ; Trailing.\n    ; Leading.\n    b\n",
            b"; File.\nEXPORTS\n    a ; Trailing.\n\n    ; Leading.\n    b\n",
            DEF_COMMENTS,
        )


if __name__ == "__main__":
    unittest.main()
