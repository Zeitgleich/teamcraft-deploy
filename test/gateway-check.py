#!/usr/bin/env python3
"""Checks the realtime gateway through the reverse proxy (test/dry-run.sh, external proxy variant).

  gateway-check.py <base url> <access token> [idle seconds]

Registers a throwaway device for the token's user, opens wss://<host>/api/v1/gateway, identifies, then
stays silent for the idle time (default 75 s: longer than nginx's default read timeout of 60 s, shorter
than the server's heartbeat timeout of 90 s) and expects the connection to still answer a heartbeat.
Needs the Python package "websockets" (>= 13); the CA comes from SSL_CERT_FILE.
"""
import base64
import json
import os
import secrets
import ssl
import sys
import time
import urllib.request

from websockets.sync.client import connect


def main() -> None:
  if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
  base, token = sys.argv[1].rstrip("/"), sys.argv[2]
  idle = int(sys.argv[3]) if len(sys.argv) == 4 else 75
  context = ssl.create_default_context(cafile=os.environ.get("SSL_CERT_FILE"))

  # The server stores device keys without checking them (clients verify the cross signature).
  body = json.dumps({
    "name": "dry-run gateway check",
    "public_key": base64.b64encode(secrets.token_bytes(32)).decode(),
    "cross_signature": base64.b64encode(secrets.token_bytes(64)).decode(),
  }).encode()
  request = urllib.request.Request(f"{base}/api/v1/devices", data=body, method="POST", headers={
    "Authorization": f"Bearer {token}", "Content-Type": "application/json"})
  with urllib.request.urlopen(request, context=context) as response:
    device_id = json.load(response)["id"]

  url = base.replace("https://", "wss://", 1) + "/api/v1/gateway"
  # No keepalive pings of the library (websockets >= 15 sends them; older sync clients don't know the
  # option): the connection has to stay silent.
  try:
    client = connect(url, ssl=context, open_timeout=10, ping_interval=None)
  except TypeError:
    client = connect(url, ssl=context, open_timeout=10)
  with client as socket:
    hello = json.loads(socket.recv(timeout=10))
    assert hello["type"] == "hello", hello
    socket.send(json.dumps({"type": "identify", "token": token, "device_id": device_id}))
    ready = json.loads(socket.recv(timeout=10))
    assert ready["type"] == "ready", ready
    print(f"ready (session {ready['session_id']}), silent for {idle} s", flush=True)
    time.sleep(idle)
    socket.send(json.dumps({"type": "heartbeat"}))
    while True:
      frame = json.loads(socket.recv(timeout=10))
      if frame["type"] == "heartbeat_ack":
        break
  print("heartbeat answered after the silence")


if __name__ == "__main__":
  main()
