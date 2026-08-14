"""Loopback HTTP/1.1 server used by the native HTTP provider tests."""

import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header(
                "Location",
                f"http://localhost:{self.server.server_port}/authorization",
            )
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/authorization":
            body = self.headers.get("authorization", "none").encode("ascii")
        elif self.path == "/large":
            body = b"0123456789abcdef" * (4 * 1024 * 1024 // 16)
        else:
            body = b"small response\n"
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Repeated", "one")
        self.send_header("X-Repeated", "two")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == "/early":
            self.send_response(413)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.flush()
            # The point of this route is to answer without consuming the upload, and
            # the client is expected to stop sending once it sees the answer. What it
            # must not do is close on top of a receive buffer that still has bytes in
            # it: the kernel answers that with RST rather than FIN, and a reset
            # discards the response the client had already parsed. Half-close the
            # write side to signal the end, then read until the client's own close,
            # bounded so a client that ignores the answer cannot hang the server.
            try:
                self.connection.shutdown(socket.SHUT_WR)
                self.connection.settimeout(5)
                while self.rfile.read(65536):
                    pass
            except OSError:
                pass
            self.close_connection = True
            return
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="ascii") as port_file:
    port_file.write(str(server.server_address[1]))
server.serve_forever()
