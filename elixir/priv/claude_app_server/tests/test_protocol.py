import json, pytest
from claude_app_server.protocol import (
    encode_response, encode_notification, parse_request, JsonRpcError
)

def test_encode_response_success():
    out = json.loads(encode_response(id=1, result={"ok": True}))
    assert out == {"jsonrpc": "2.0", "id": 1, "result": {"ok": True}}

def test_encode_response_error():
    out = json.loads(encode_response(id=2, error=JsonRpcError(code=-32601, message="nope")))
    assert out["error"] == {"code": -32601, "message": "nope"}

def test_encode_notification():
    out = json.loads(encode_notification("session/event", {"kind": "agent_message"}))
    assert out["method"] == "session/event"
    assert "id" not in out

def test_parse_request():
    r = parse_request('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
    assert r.id == 1 and r.method == "initialize"

def test_parse_request_bad_json():
    with pytest.raises(ValueError):
        parse_request("{bad")
