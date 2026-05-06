"""Codex app-server protocol shim — JSON-RPC 2.0 over stdio."""
from __future__ import annotations
import asyncio
import json
import sys
import uuid

from .protocol import parse_request, encode_response, encode_notification, JsonRpcError
from .session import SessionRegistry
from .events import (
    agent_message_params, function_call_params,
    function_call_output_params, turn_complete_params
)

CLAUDE_COMMAND = "claude"


async def dispatch(request: dict, registry: SessionRegistry, emit) -> None:
    req_id = request.get("id")
    method = request.get("method", "")
    params = request.get("params") or {}

    try:
        if method == "initialize":
            await emit(encode_response(id=req_id, result={
                "protocol": "symphony-claude-shim/1",
                "capabilities": {},
            }))

        elif method == "thread/start":
            workspace = params.get("workspace") or params.get("cwd") or "/tmp"
            command = params.get("command") or CLAUDE_COMMAND
            tid = registry.create(workspace=workspace, command=command)
            await emit(encode_response(id=req_id, result={"thread_id": tid}))

        elif method == "turn/start":
            tid = params.get("thread_id", "")
            turn_id = params.get("turn_id") or str(uuid.uuid4())
            prompt = params.get("prompt", "")
            session = registry.get(tid)
            if session is None:
                await emit(encode_response(id=req_id,
                    error=JsonRpcError(code=-32600, message=f"unknown thread_id: {tid}")))
                return

            async for event in session.run_turn(prompt):
                ev_type = event.get("type")
                ev_params = None
                if ev_type == "assistant" and event.get("content"):
                    for block in event["content"]:
                        if block.get("type") == "text":
                            ev_params = agent_message_params(
                                block["text"], tid, turn_id)
                        elif block.get("type") == "tool_use":
                            ev_params = function_call_params(
                                block["name"], block["id"],
                                block.get("input", {}), tid, turn_id)
                elif ev_type == "result":
                    session._session_id = event.get("session_id")
                    ev_params = turn_complete_params(tid, turn_id,
                        result=event.get("subtype", "success"))
                if ev_params:
                    await emit(encode_notification("session/event", ev_params))

            await emit(encode_response(id=req_id,
                result={"turn_id": turn_id, "session_id": tid}))

        elif method == "shutdown":
            tid = params.get("thread_id")
            if tid:
                registry.remove(tid)
            await emit(encode_response(id=req_id, result={}))

        else:
            await emit(encode_response(id=req_id,
                error=JsonRpcError(code=-32601, message=f"method not found: {method}")))

    except Exception as e:
        await emit(encode_response(id=req_id,
            error=JsonRpcError(code=-32000, message=str(e))))


async def _run() -> int:
    registry = SessionRegistry()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    loop = asyncio.get_event_loop()
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    out_lock = asyncio.Lock()

    async def emit(line: str) -> None:
        async with out_lock:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()

    while True:
        raw = await reader.readline()
        if not raw:
            break
        line = raw.decode("utf-8").strip()
        if not line:
            continue
        try:
            req = parse_request(line)
        except ValueError as e:
            await emit(encode_response(id=None,
                error=JsonRpcError(code=-32700, message=f"parse error: {e}")))
            continue
        asyncio.create_task(dispatch(
            {"id": req.id, "method": req.method, "params": req.params},
            registry, emit))

    return 0


def main() -> None:
    raise SystemExit(asyncio.run(_run()))


if __name__ == "__main__":
    main()
