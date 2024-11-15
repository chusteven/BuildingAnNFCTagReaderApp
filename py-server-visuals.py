from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
from socketserver import ThreadingMixIn

import typing as t

import argparse
import json
import time
from pythonosc import udp_client


madmapper_port: int = 0


def play_fish_effect(client: t.Any, clip_length: int) -> None:
    client.send_message(f"/medias/<TODO>/play_forward", "true")
    time.sleep(clip_length)
    client.send_message(f"/medias/<TODO>/pause", "true")
    client.send_message(f"/medias/<TODO>/restart", "")


ID_TO_EFFECT_MAPPING: t.Dict[int, t.Callable] = {
    1: play_fish_effect,
    5: play_fish_effect,
}


class VideoRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, client: t.Any, **kwargs):
        self.client = client
        super().__init__(*args, **kwargs)

    def log_message(self, format, *args) -> None:
        pass

    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello, world! This is a GET response.")

    def do_POST(self) -> None:
        content_length = int(self.headers["Content-Length"])
        data = json.loads(self.rfile.read(content_length))
        id = data["id"]

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"message": "POST request received successfully"}
        self.wfile.write(json.dumps(response).encode("utf-8"))


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass


def create_handler(client: t.Any) -> t.Callabale:
    def handler(*args, **kwargs):
        return VideoRequestHandler(*args, client=client, **kwargs)

    return handler


def main(port: int, madmapper_port: int) -> None:
    client = udp_client.SimpleUDPClient(args.ip, args.port)

    handler = create_handler(client)
    httpd = ThreadedHTTPServer(("", port), handler)
    print(f"Serving HTTP on port {port}...")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print("Server stopped and finally called")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--port", type=int, default=8002, help="The port to serve requests from"
    )
    parser.add_argument(
        "--madmapper-port",
        type=int,
        default=8010,
        help="The port where MadMapper OSC is listening",
    )
    args = parser.parse_args()
    main(args.port, args.madmapper_port)
