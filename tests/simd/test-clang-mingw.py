"""Check compiler argument boundaries, using the real CRT on Windows."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
EMIT = r"""
#include <stdio.h>
static void emit(const char *value) {
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p)
        printf("%02x", (unsigned)*p);
    putchar('\n');
}
"""


class CompilerArguments(unittest.TestCase):
    def test_preserve_spaces_quotes_empty_arguments_and_backslashes(self):
        compiler = os.environ.get("NUPP_CC", "gcc" if os.name == "nt" else "cc")
        with tempfile.TemporaryDirectory(prefix="simd compiler args ") as temporary:
            directory = Path(temporary)
            wrapper = directory / "wrapper.exe"
            flags = [compiler, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror"]
            sources = [str(ROOT / "tests/simd/clang-mingw.c")]
            if os.name == "nt":
                probe = directory / "compiler with spaces.exe"
                source = directory / "probe.c"
                source.write_text(EMIT + "int main(int n, char **v) { for (int i=0;i<n;++i) emit(v[i]); return 0; }\n")
                subprocess.run(flags + [str(source), "-o", str(probe)], check=True)
            else:
                # Observe exactly what is passed to the Windows CRT. Expected
                # command-line fragments below are literal regression cases.
                probe = Path(r"C:\Program Files\LLVM\bin\clang.exe")
                (directory / "process.h").write_text(
                    "#include <stdint.h>\n#define _P_WAIT 0\n"
                    "intptr_t _spawnv(int, const char *, const char *const *);\n"
                )
                shim = directory / "spawn.c"
                shim.write_text(EMIT + '#include "process.h"\n'
                    'intptr_t _spawnv(int mode, const char *file, const char *const *args) {'
                    '(void)mode; (void)file; for (; *args; ++args) emit(*args); return 0; }\n')
                flags += ["-I", str(directory)]
                sources.append(str(shim))
            subprocess.run(flags + sources + ["-o", str(wrapper)], check=True)
            arguments = ["", "plain", "two words", 'a"b', "a\\", "two words\\", 'a\\"b', "\ttab\t"]
            environment = dict(os.environ, NUPP_SIMD_CLANG=str(probe),
                               NUPP_SIMD_GNU_ROOT="C:\\GNU tools\\",
                               NUPP_SIMD_GNU_TARGET="x86_64-w64-mingw32")
            output = subprocess.check_output([str(wrapper), *arguments], env=environment, text=True)
            actual = [bytes.fromhex(line).decode() for line in output.splitlines()]
            if os.name == "nt":
                expected = [str(probe), "--target=x86_64-w64-mingw32", "--sysroot=C:\\GNU tools\\", *arguments]
            else:
                expected = [
                    r'"C:\Program Files\LLVM\bin\clang.exe"',
                    '"--target=x86_64-w64-mingw32"',
                    '"--sysroot=C:\\GNU tools\\\\"',
                    '""', '"plain"', '"two words"', '"a\\"b"',
                    '"a\\\\"', '"two words\\\\"', '"a\\\\\\"b"', '"\ttab\t"',
                ]
            self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
