from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer

import datetime
import json
import threading
import time


first_ts = None
last_ts = None


class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args) -> None:
        pass

    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello, world! This is a GET response.")

    def do_POST(self) -> None:
        content_length = int(self.headers["Content-Length"])
        data = self.rfile.read(content_length)
        now = datetime.datetime.now()
        print(f"[{now}] POST request data: {data.decode('utf-8')}")

        global first_ts
        if first_ts is None:
            first_ts = now
        global last_ts
        last_ts = now

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"message": "POST request received successfully"}
        self.wfile.write(json.dumps(response).encode("utf-8"))


def report_status() -> None:
    while True:
        global first_ts
        global last_ts
        print(f"First timestamp: {first_ts}; last timestamp: {last_ts}")
        time.sleep(30)


def main() -> None:
    port = 8001
    server_address = ("", port)
    httpd = HTTPServer(server_address, SimpleHTTPRequestHandler)
    print(f"Serving HTTP on port {port}...")
    rt = threading.Thread(target=report_status, daemon=True)
    rt.start()
    httpd.serve_forever()


if __name__ == "__main__":
    main()
