from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
from socketserver import ThreadingMixIn

import typing as t

import argparse
import json
import time
import threading
from pythonosc import udp_client


madmapper_port: int = 0

# -----------------------------------------------------------------------------
#   Visual effects:
#   1/ First create a threading.Lock()
#   2/ Define a function
#   3/ Fill out the function definition (use examples below)
#   4/ Add to mapping
# -----------------------------------------------------------------------------

sunnybubbles_lock = threading.Lock()
fish_lock = threading.Lock()
crabwalk_lock = threading.Lock()
bottleburst_lock = threading.Lock()


def play_fish_effect(client: t.Any) -> bool:
    if fish_lock.locked():
        return False

    fish_lock.acquire()

    def play_effect() -> None:
        # client.send_message(f"/medias/<TODO>/play_forward", "true")
        time.sleep(5)
        # client.send_message(f"/medias/<TODO>/pause", "true")
        # client.send_message(f"/medias/<TODO>/restart", "")
        fish_lock.release()
        return

    threading.Thread(target=play_effect).start()
    return True


def play_crabwalk_effect(client: t.Any) -> bool:
    if crabwalk_lock.locked():
        return False

    crabwalk_lock.acquire()

    def play_effect() -> None:
        # Fill this out with the STUFF
        # like this:
        print("Sleeping")
        time.sleep(5)
        print("Done sleeping, about to release lock")
        # or this: client.send_message(f"/medias/<TODO>/pause", "true")
        crabwalk_lock.release()
        return

    threading.Thread(target=play_effect).start()
    return True


def bottleburst_effect(client: t.Any) -> bool:
    if bottleburst_lock.locked():
        return False

    bottleburst_lock.acquire()

    def play_effect() -> None:
        client.send_message(f"/surfaces/bottleburst/FX/Active", "true")
        for i in range(100):
            val = 0.01 * i
            client.send_message(f"/surfaces/bottleburst/opacity", f"{val}")
            time.sleep(5 / 100)  # 5s
        time.sleep(1)
        for i in range(100):
            val = 1 - (0.01 * i)
            client.send_message(f"/surfaces/bottleburst/opacity", f"{val}")
            time.sleep(5 / 100)  # 5s
        client.send_message(f"/surfaces/bottleburst/opacity", "0.000000")
        client.send_message(f"/surfaces/bottleburst/FX/Active", "false")
        bottleburst_lock.release()
        return

    threading.Thread(target=play_effect).start()
    return True


def play_sunnybubbles_effect(client: t.Any) -> bool:
    if sunnybubbles_lock.locked():
        return False

    sunnybubbles_lock.acquire()

    def play_effect() -> None:
        client.send_message("/medias/sunnybubbblesv3.mov/play_forward", "true")
        time.sleep(14.2)
        client.send_message("/medias/sunnybubbblesv3.mov/pause", "true")
        client.send_message("/medias/sunnybubbblesv3.mov/restart", "")
        sunnybubbles_lock.release()
        return

    threading.Thread(target=play_effect).start()
    return True


ID_TO_EFFECT_MAPPING: t.Dict[int, t.Callable] = {
    1: play_fish_effect,
    5: play_sunnybubbles_effect,
    6: play_crabwalk_effect,
    7: bottleburst_effect,
}


# -----------------------------------------------------------------------------
#   Handlers
# -----------------------------------------------------------------------------


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

        func = ID_TO_EFFECT_MAPPING.get(id)
        if not func:
            self.send_response(400)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            response = {"error": "Could not find effect with given ID"}
            self.wfile.write(json.dumps(response).encode("utf-8"))
            return

        successful_return = func(self.client)
        if not successful_return:
            self.send_response(400)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            response = {"error": "Calling func failed -- probably locked"}
            self.wfile.write(json.dumps(response).encode("utf-8"))
            return

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"message": "POST request received successfully"}
        self.wfile.write(json.dumps(response).encode("utf-8"))


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass


def create_handler(client: t.Any) -> t.Callable:
    def handler(*args, **kwargs):
        return VideoRequestHandler(*args, client=client, **kwargs)

    return handler


# -----------------------------------------------------------------------------
#   Main
# -----------------------------------------------------------------------------


def main(port: int, madmapper_host: str, madmapper_port: int) -> None:
    client = udp_client.SimpleUDPClient(madmapper_host, madmapper_port)

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
        "--madmapper-host",
        type=str,
        default="127.0.0.1",
        help="The host where MadMapper OSC is running",
    )
    parser.add_argument(
        "--madmapper-port",
        type=int,
        default=8010,
        help="The port where MadMapper OSC is listening",
    )
    args = parser.parse_args()
    main(args.port, args.madmapper_host, args.madmapper_port)
