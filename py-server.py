from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
from socketserver import ThreadingMixIn

import datetime
import json
import sqlite3
import uuid


DB_FILE = "db.db"
db_connection = None
PROGRAM_UUID = str(uuid.uuid4())


class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args) -> None:
        pass

    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello, world! This is a GET response.")

    def do_POST(self) -> None:
        global db_connection

        content_length = int(self.headers["Content-Length"])
        data = json.loads(self.rfile.read(content_length))
        role = data["role"]
        now = datetime.datetime.now()

        cursor = db_connection.cursor()
        cursor.execute(
            "INSERT INTO sessions (session, role, ts) VALUES (?, ?, ?)",
            (PROGRAM_UUID, role, now),
        )
        db_connection.commit()

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"message": "POST request received successfully"}
        self.wfile.write(json.dumps(response).encode("utf-8"))


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass


def initialize_db():
    global db_connection
    db_connection = sqlite3.connect(DB_FILE, check_same_thread=False)
    cursor = db_connection.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS sessions (
            session TEXT,
            role TEXT,
            ts TIMESTAMP
        )
        """
    )
    # cursor.execute(
    #     """
    #     CREATE INDEX idx_session_role ON sessions (session, role)
    #     """
    # )
    db_connection.commit()


def main() -> None:
    global db_connection
    initialize_db()

    port = 8001
    httpd = ThreadedHTTPServer(("", port), SimpleHTTPRequestHandler)
    print(f"Serving HTTP on port {port}...")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if db_connection:
            db_connection.close()
        print("Server stopped and database connection closed.")


if __name__ == "__main__":
    main()
