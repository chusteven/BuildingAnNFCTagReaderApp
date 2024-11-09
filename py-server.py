from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        # Respond to GET requests
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Hello, world! This is a GET response.")

    def do_POST(self):
        # Respond to POST requests
        content_length = int(self.headers['Content-Length'])  # Get the length of the data
        post_data = self.rfile.read(content_length)  # Read the data
        print(f"Received POST data: {post_data.decode('utf-8')}")  # Print the data

        # Respond with a success message
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {"message": "POST request received successfully"}
        self.wfile.write(json.dumps(response).encode('utf-8'))

# Start the server
server_address = ('', 8000)  # Listen on all available interfaces, port 8000
httpd = HTTPServer(server_address, SimpleHTTPRequestHandler)
print("Serving HTTP on port 8000...")
httpd.serve_forever()

