"""Codex app-server protocol shim — JSON-RPC 2.0 over stdio."""
from __future__ import annotations
import asyncio
import json
import sys
import uuid

from .protocol import parse_request, encode_response, encode_notification, JsonRpcError
from .session import SessionRegistry

CLAUDE_COMMAND = "claude"


def _extract_prompt(params: dict) -> str:
    raw = params.get("input")
    if isinstance(raw, list):
        parts = []
        for block in raw:
            if isinstance(block, dict) and block.get("type") == "text":
                text = block.get("text")
                if isinstance(text, str):
                    parts.append(text)
        if parts:
            return "\n".join(parts)
    if isinstance(raw, str):
        return raw
    fallback = params.get("prompt")
    return fallback if isinstance(fallback, str) else ""


async def dispatch(request: dict, registry: SessionRegistry, emit) -> None:
    req_id = request.get("id")
    method = request.get("method", "")
    params = request.get("params") or {}
    is_notification = req_id is None

    try:
        if method == "initialize":
            await emit(encode_response(id=req_id, result={
                "protocol": "symphony-claude-shim/1",
                "capabilities": {},
            }))

        elif method == "initialized":
            return

        elif method == "thread/start":
            workspace = params.get("cwd") or params.get("workspace") or "/tmp"
            command = params.get("command") or CLAUDE_COMMAND
            tid = registry.create(workspace=workspace, command=command)
            await emit(encode_response(id=req_id, result={"thread": {"id": tid}}))

        elif method == "turn/start":
            tid = params.get("threadId") or params.get("thread_id") or ""
            turn_id = params.get("turnId") or params.get("turn_id") or str(uuid.uuid4())
            prompt = _extract_prompt(params)

            session = registry.get(tid)
            if session is None:
                await emit(encode_response(id=req_id,
                    error=JsonRpcError(code=-32600, message=f"unknown thread_id: {tid}")))
                return

            await emit(encode_response(id=req_id, result={"turn": {"id": turn_id}}))

            failure: str | None = None
            try:
                async for event in session.run_turn(prompt):
                    ev_type = event.get("type")
                    if ev_type == "assistant":
                        for block in event.get("content") or []:
                            btype = block.get("type")
                            if btype == "text":
                                await emit(encode_notification("agent/message", {
                                    "threadId": tid,
                                    "turnId": turn_id,
                                    "text": block.get("text", ""),
                                }))
                            elif btype == "tool_use":
                                await emit(encode_notification("agent/tool_call", {
                                    "threadId": tid,
                                    "turnId": turn_id,
                                    "name": block.get("name", ""),
                                    "callId": block.get("id", ""),
                                    "arguments": block.get("input", {}),
                                }))
                    elif ev_type == "result":
                        session._session_id = event.get("session_id")
                        if event.get("subtype") not in (None, "success"):
                            failure = event.get("subtype")
            except Exception as exc:
                failure = str(exc)

            if failure is None:
                await emit(encode_notification("turn/completed", {
                    "threadId": tid,
                    "turnId": turn_id,
                }))
            else:
                await emit(encode_notification("turn/failed", {
                    "threadId": tid,
                    "turnId": turn_id,
                    "error": failure,
                }))

        elif method == "shutdown":
            tid = params.get("threadId") or params.get("thread_id")
            if tid:
                registry.remove(tid)
            await emit(encode_response(id=req_id, result={}))

        elif is_notification:
            return

        else:
            await emit(encode_response(id=req_id,
                error=JsonRpcError(code=-32601, message=f"method not found: {method}")))

    except Exception as e:
        if not is_notification:
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
