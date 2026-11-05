from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('browser_toolchain', Path(__file__).resolve().parents[4] / 'scripts/browser-toolchain.py')
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


@contextmanager
def interrupted_download(payload):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.server.attempts += 1
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload[:4] if self.server.attempts <= 2 else payload)
            self.close_connection = True

        def log_message(self, *args):
            pass

    with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        server.attempts = 0
        worker = Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield server
        finally:
            server.shutdown()
            worker.join()


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

    def test_interrupted_downloads_retry_and_still_require_the_pinned_digest(self):
        expected = b'verified source archive'
        for payload in (expected, b'unexpected source archive'):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                record = {'archive': 'input.tar.gz', 'sha256': hashlib.sha256(expected).hexdigest(),
                          'url': 'https://invalid.invalid/source'}
                with interrupted_download(payload) as server:
                    mirror = f'http://127.0.0.1:{server.server_port}'
                    with patch.dict(os.environ, {'NUPP_HOST_OFFLINE': '0',
                                                 'NUPP_HOST_SOURCE_DIR': str(root / 'missing'),
                                                 'NUPP_HOST_SOURCE_BASE_URL': mirror,
                                                 'NO_PROXY': '127.0.0.1'}):
                        if payload == expected:
                            self.assertEqual(toolchain.archive(root / 'cache', record).read_bytes(), expected)
                            self.assertEqual(toolchain.archive(root / 'cache', record).read_bytes(), expected)
                        else:
                            with self.assertRaisesRegex(RuntimeError, 'digest mismatch'):
                                toolchain.archive(root / 'cache', record)
                            self.assertFalse((root / 'cache/archives/input.tar.gz').exists())
                    self.assertEqual(server.attempts, 3)
                self.assertFalse((root / 'cache/archives/input.tar.gz.lock').exists())

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
