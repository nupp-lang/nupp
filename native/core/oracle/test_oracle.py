#!/usr/bin/env python3
"""Tooling tests; fake targets exercise transport, never core semantics."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import oracle


class GeneratorTests(unittest.TestCase):
    def test_reproducible_bounded_programs_and_coverage(self):
        coverage = set()
        for seed in range(64):
            source, manifest = oracle.generate(seed, 64)
            self.assertEqual((source, manifest), oracle.generate(seed, 64))
            self.assertLess(len(source), 16000)
            self.assertEqual(manifest["sourceSha256"], oracle.digest(source))
            coverage.update(manifest["coverage"])
        self.assertEqual(len(coverage), 12)
        self.assertNotEqual(oracle.generate(0), oracle.generate(1))

    def test_invalid_seed_steps_and_command_refuse(self):
        for seed in (-1, 2**32, True, "1", None):
            with self.assertRaises(ValueError):
                oracle.generate(seed)
        for steps in (0, 65, 1.5, True, None):
            with self.assertRaises(ValueError):
                oracle.generate(1, steps)
        for command in ([], "echo", ["echo"], ["echo", "{bad}", "{output}", "{program}"],
                        ["echo", "prefix{program}", "{output}"]):
            with self.assertRaises(ValueError):
                oracle.target_argv(command, Path("case.json"), Path("out"))

    def test_replay_rejects_source_metadata_and_version_changes(self):
        with tempfile.TemporaryDirectory(prefix="core-oracle-unit-", dir=oracle.ROOT / "build") as directory:
            root = Path(directory)
            path = oracle.generate_case(root / "case", 42, 24)
            original = path.read_bytes()
            oracle.validate_case(path)
            for field, value in (("seed", 1), ("format", "unknown"), ("extra", 1)):
                manifest = json.loads(original)
                manifest[field] = value
                oracle.save(path, manifest)
                with self.assertRaises(ValueError):
                    oracle.validate_case(path)
            path.write_bytes(original)
            with (path.parent / "program.lua").open("ab") as output:
                output.write(b"-- mutation\n")
            with self.assertRaises(ValueError):
                oracle.validate_case(path)


class ReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = os.environ.get("CORE_ORACLE_REFERENCE")
        if not path:
            raise RuntimeError("CORE_ORACLE_REFERENCE is required; reference tests never silently skip")
        cls.ref = oracle.reference(path)
        output = os.environ.get("CORE_ORACLE_TEST_OUTPUT")
        if not output:
            raise RuntimeError("CORE_ORACLE_TEST_OUTPUT is required for retained evidence")
        cls.root = oracle.fresh_output(output)
        cls.counter = 0

    def directory(self):
        type(self).counter += 1
        path = self.root / f"probe-{self.counter:03}"
        path.mkdir()
        return path

    def observe(self, source):
        path = self.directory()
        program, output = path / "program.lua", path / "output.bin"
        program.write_text(source)
        result = oracle.execute(
            [self.ref["binary"], oracle.HERE / "reference.lua", program, output],
            path, "observe", watched=(output,),
        )
        oracle.save(path / "receipt.json", result)
        return result, output.read_bytes() if output.exists() else None

    def test_exact_scalar_tags_integer_boundaries_and_nils(self):
        result, value = self.observe('return nil, false, "", true, 9007199254740993, 9223372036854775807, -9223372036854775807-1')
        self.assertEqual(result["status"], "ok")
        self.assertEqual(value, b"R7:N;B0;S0:;B1;I9007199254740993;I9223372036854775807;I-9223372036854775808;\n")

    def test_canonical_table_order_independent_of_insertion(self):
        left, a = self.observe('local t={}; t.z=1; t[true]="t"; t[-1]=false; t[false]="f"; t.a=""; return t')
        right, b = self.observe('local t={a="",[false]="f",[-1]=false,[true]="t",z=1}; return t')
        self.assertEqual(left["status"], "ok")
        self.assertEqual(right["status"], "ok")
        self.assertEqual(a, b)
        self.assertEqual(a, b"R1:T5:{B0;S1:66;B1;S1:74;I-1;B0;S1:61;S0:;S1:7a;I1;}\n")

    def test_floor_division_and_closure_alias_semantics(self):
        result, value = self.observe('local n=0; local function f() n=n+1; return n end; local a=f(); local t={}; local u=t; u.x=f(); return -7//3,-7%3,a,n,t.x,u==t')
        self.assertEqual(result["status"], "ok")
        self.assertEqual(value, b"R6:I-3;I2;I1;I2;I2;B1;\n")

    def test_unknown_observation_types_and_cycles_refuse_without_output(self):
        for source, reason in (
            ("return 1.5", "unsupported observation: float"),
            ("return function() end", "unsupported observation type: function"),
            ("local t={}; t.self=t; return t", "unsupported observation: cycle"),
            ("local t={}; t[{}]=1; return t", "unsupported table key type"),
        ):
            result, value = self.observe(source)
            self.assertEqual(result["status"], "exit")
            self.assertIsNone(value)
            self.assertIn(reason, Path(result["stderr"]["path"]).read_text())

    def test_generated_cases_reference_only_and_replay_exact(self):
        for seed in range(16):
            root = self.directory()
            case = oracle.generate_case(root / "case", seed, 64)
            first = oracle.run_case(case, self.ref, root / "first")
            replay = oracle.run_case(case, self.ref, root / "replay")
            self.assertEqual(first["status"], "oracle-only")
            self.assertFalse(first["coreAcceptance"])
            self.assertEqual(first["expectedSha256"], replay["expectedSha256"])

    def test_target_matching_mismatch_refusal_and_timeout_receipts(self):
        root = self.directory()
        case = oracle.generate_case(root / "case", 42, 24)
        # Reusing the reference here tests adapter wiring only, not a core.
        command = [self.ref["binary"], str(oracle.HERE / "reference.lua"), "{program}", "{output}"]
        matched = oracle.run_case(case, self.ref, root / "match", command)
        self.assertEqual(matched["status"], "matched")
        self.assertFalse(matched["coreAcceptance"])
        adapter = root / "adapter.py"
        adapter.write_text('import pathlib,sys,time\nmode,program,output=sys.argv[1:]\nif mode=="refuse": sys.exit(77)\nif mode=="timeout": time.sleep(10)\nif mode=="mismatch": pathlib.Path(output).write_bytes(b"wrong")\n')
        for mode, expected in (("mismatch", "mismatch"), ("refuse", "target-refused"), ("timeout", "target-timeout")):
            result = oracle.run_case(case, self.ref, root / mode,
                                     [sys.executable, str(adapter), mode, "{program}", "{output}"], timeout=0.5)
            self.assertEqual(result["status"], expected)
            self.assertTrue((root / mode / "receipt.json").is_file())

    def test_canonical_output_flood_is_truncated_and_never_compared(self):
        root = self.directory()
        case = oracle.generate_case(root / "case", 42, 24)
        adapter = root / "flood.py"
        adapter.write_text(
            'import pathlib,sys\n'
            'pathlib.Path(sys.argv[2]).write_bytes(b"x" * 2000000)\n'
        )
        result = oracle.run_case(
            case, self.ref, root / "target",
            [sys.executable, str(adapter), "{program}", "{output}"],
        )
        self.assertEqual(result["status"], "target-output-limit")
        self.assertNotIn("actualSha256", result)
        output = root / "target" / "actual.bin"
        self.assertEqual(output.stat().st_size, oracle.OUTPUT_LIMIT)
        retained = result["target"]["watchedOutputs"]
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0]["bytes"], 2000000)
        self.assertEqual(retained[0]["retainedBytes"], oracle.OUTPUT_LIMIT)
        self.assertTrue(retained[0]["truncated"])
        self.assertEqual(retained[0]["sha256"], oracle.digest(output.read_bytes()))
        # The same retention contract protects the reference expected file.
        expected = root / "expected.bin"
        reference = oracle.execute(
            [sys.executable, str(adapter), str(case.parent / "program.lua"), str(expected)],
            root, "reference-flood", watched=(expected,),
        )
        oracle.save(root / "reference-flood.json", reference)
        self.assertEqual(reference["status"], "output-limit")
        self.assertEqual(expected.stat().st_size, oracle.OUTPUT_LIMIT)
        self.assertTrue(reference["watchedOutputs"][0]["truncated"])

    def test_binary_hash_and_output_extent_refusals(self):
        root = self.directory()
        fake = dict(self.ref, binarySha256="0" * 64)
        oracle.save(root / "reference.json", fake)
        with self.assertRaisesRegex(ValueError, "binary hash"):
            oracle.reference(root / "reference.json")
        result = oracle.execute([sys.executable, "-c", 'import sys; sys.stdout.write("x"*2000000)'], root, "flood")
        self.assertEqual(result["status"], "output-limit")
        self.assertLessEqual((root / "flood.out").stat().st_size, oracle.OUTPUT_LIMIT)
        oracle.save(root / "flood.json", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
