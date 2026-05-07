"""JSON-RPC 2.0 framing helpers."""
from __future__ import annotations
import json
from dataclasses import dataclass, field
from typing import Any


@dataclass
class JsonRpcError:
    code: int
    message: str
    data: Any = None

    def to_dict(self) -> dict:
        d = {"code": self.code, "message": self.message}
        if self.data is not None:
            d["data"] = self.data
        return d


@dataclass
class JsonRpcRequest:
    id: int | str | None
    method: str
    params: Any


def parse_request(line: str) -> JsonRpcRequest:
    try:
        obj = json.loads(line)
    except json.JSONDecodeError as e:
        raise ValueError(f"invalid JSON: {e}") from e
    return JsonRpcRequest(
        id=obj.get("id"),
        method=obj.get("method", ""),
        params=obj.get("params") or {},
    )


def encode_response(*, id, result=None, error: JsonRpcError | None = None) -> str:
    if (result is None) == (error is None):
        raise ValueError("exactly one of result/error required")
    payload: dict = {"jsonrpc": "2.0", "id": id}
    if error is not None:
        payload["error"] = error.to_dict()
    else:
        payload["result"] = result
    return json.dumps(payload)


def encode_notification(method: str, params: Any) -> str:
    return json.dumps({"jsonrpc": "2.0", "method": method, "params": params})
