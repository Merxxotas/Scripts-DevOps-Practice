"""Webhook Server trigger module for EventOps daemon."""

import http.server
import json
import logging
import socketserver
import threading

from executor import execute_async
from rule_engine import RuleEngine

logger = logging.getLogger("eventops.webhook_server")


class EventOpsHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    """Custom HTTP request handler for incoming webhook triggers."""

    rule_engine: RuleEngine | None = None

    def log_message(self, format: str, *args) -> None:
        """Override default logging to pipe through central logger."""
        logger.debug("[HTTP] " + format, *args)

    def _send_json_response(self, status_code: int, payload: dict) -> None:
        """Helper to send JSON HTTP response."""
        response_data = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response_data)))
        self.end_headers()
        self.wfile.write(response_data)

    def do_POST(self) -> None:
        """Handles incoming POST requests to webhook endpoints."""
        if not self.rule_engine:
            logger.error("Rule engine not initialized on HTTP request handler.")
            self._send_json_response(
                500, {"status": "error", "message": "Server configuration error"}
            )
            return

        endpoint_path = self.path.split("?")[0]
        logger.info("Received POST request on %s", endpoint_path)

        rule = self.rule_engine.match_webhook(endpoint_path)
        if not rule:
            logger.warning("No webhook rule matching endpoint '%s'", endpoint_path)
            self._send_json_response(
                404,
                {
                    "status": "error",
                    "message": f"No webhook rule matching endpoint '{endpoint_path}'",
                },
            )
            return

        logger.info("Triggering rule '%s' for endpoint '%s'", rule.name, endpoint_path)
        execute_async(rule.action, rule.name)

        self._send_json_response(
            200,
            {
                "status": "success",
                "rule": rule.name,
                "message": "Action triggered successfully",
            },
        )

    def do_GET(self) -> None:
        """Handles GET requests with 405 Method Not Allowed."""
        self._send_json_response(
            405, {"status": "error", "message": "Method Not Allowed. Use POST."}
        )


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Threaded HTTP server allowing concurrent request handling."""

    daemon_threads = True
    allow_reuse_address = True


class WebhookServer:
    """Server manager class for controlling Webhook trigger listener."""

    def __init__(
        self,
        rule_engine: RuleEngine,
        host: str = "0.0.0.0",
        port: int = 8080,
    ) -> None:
        self.rule_engine = rule_engine
        self.host = host
        self.port = port
        self.server: ThreadedHTTPServer | None = None
        self.thread: threading.Thread | None = None

    def start(self) -> None:
        """Starts the Webhook HTTP server in a background daemon thread."""
        handler_class = EventOpsHTTPRequestHandler
        handler_class.rule_engine = self.rule_engine

        self.server = ThreadedHTTPServer((self.host, self.port), handler_class)
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            daemon=True,
            name="WebhookServerThread",
        )
        self.thread.start()
        logger.info("Webhook Server listening on http://%s:%d", self.host, self.port)

    def stop(self) -> None:
        """Stops the Webhook HTTP server cleanly."""
        if self.server:
            logger.info("Stopping Webhook Server...")
            self.server.shutdown()
            self.server.server_close()
            logger.info("Webhook Server stopped.")
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=2.0)
