import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('browser_toolchain', Path(__file__).resolve().parents[2] / 'scripts/browser-toolchain.py')
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


class Provisioning(unittest.TestCase):
    def test_offline_digest_is_checked_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            supplied = root / 'supplied'
            supplied.mkdir()
            (supplied / 'input.tar.gz').write_bytes(b'wrong input')
            record = {'archive': 'input.tar.gz', 'sha256': hashlib.sha256(b'correct input').hexdigest(), 'url': 'https://invalid.invalid/source'}
            with patch.dict(os.environ, {'NUPP_HOST_OFFLINE': '1', 'NUPP_HOST_SOURCE_DIR': str(supplied)}):
                with self.assertRaisesRegex(RuntimeError, 'digest mismatch'):
                    toolchain.archive(root / 'cache', record)
                self.assertFalse((root / 'cache/archives/input.tar.gz').exists())
                (supplied / 'input.tar.gz').write_bytes(b'correct input')
                self.assertEqual(toolchain.archive(root / 'cache', record).read_bytes(), b'correct input')

    def test_archive_traversal_cannot_write_outside_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'input.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                entry = tarfile.TarInfo('../../escaped')
                entry.size = 4
                output.addfile(entry, io.BytesIO(b'evil'))
            record = {'directory': 'source', 'marker': 'marker', 'sha256': toolchain.digest(archive)}
            with self.assertRaises(tarfile.FilterError):
                toolchain.extract(archive, root / 'destination', record)
            self.assertFalse((root / 'escaped').exists())
            self.assertFalse((root / 'destination').exists())

    def test_missing_source_marker_does_not_publish_a_cache_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'empty.tar.gz'
            with tarfile.open(archive, 'w:gz'):
                pass
            with self.assertRaisesRegex(RuntimeError, 'missing expected source marker'):
                toolchain.extract(archive, root / 'destination', {'directory': 'source', 'marker': 'marker', 'sha256': toolchain.digest(archive)})
            self.assertFalse((root / 'destination').exists())


if __name__ == '__main__':
    unittest.main()
