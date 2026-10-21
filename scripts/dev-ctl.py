#!/usr/bin/env python3
"""Sends one request to the Android Webcam dev instance's control socket and prints the JSON reply.

    dev-ctl.py DIR OP [key=value ...]     key=value is a string field, key:=json is a JSON field (key:=true, key:=3)
    dev-ctl.py DIR '{"op": "state"}'      or pass the request as JSON

Exit status is 0 when the reply has "ok": true, 1 when it has "ok": false, 2 when the socket can't be reached.
Run through scripts/dev.sh, which finds DIR. See docs/dev-automation.md.
"""
import json
import socket
import sys


def build(arguments):
    if len(arguments) == 1 and arguments[0].lstrip().startswith("{"):
        return json.loads(arguments[0])
    request = {"op": arguments[0]}
    for pair in arguments[1:]:
        key, separator, value = pair.partition("=")
        if not separator:
            raise SystemExit(f"dev-ctl: expected key=value or key:=json, got {pair!r}")
        if key.endswith(":"):
            request[key[:-1]] = json.loads(value)
        else:
            request[key] = value
    return request


def send(directory, request, timeout=20):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(timeout)
    connection.connect(f"{directory}/control.sock")
    connection.sendall(json.dumps(request).encode() + b"\n")
    data = b""
    while not data.endswith(b"\n"):
        chunk = connection.recv(65536)
        if not chunk:
            break
        data += chunk
    connection.close()
    return json.loads(data)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    try:
        reply = send(sys.argv[1], build(sys.argv[2:]))
    except (OSError, ValueError) as error:
        print(f"dev-ctl: no answer from {sys.argv[1]}/control.sock ({error})", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(reply, indent=2, ensure_ascii=False, sort_keys=True))
    sys.exit(0 if reply.get("ok") else 1)


if __name__ == "__main__":
    main()
