import http.server, socketserver, sys, threading

BODY = b"rsharp-http-ok\n"

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(BODY)))
        self.send_header("X-Test", "yes")
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *a):
        pass

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    with S(("127.0.0.1", port), H) as srv:
        open(f'http_{port}.pid', 'w').write(str(__import__('os').getpid()))
        print("listening", port, flush=True)
        srv.serve_forever()
