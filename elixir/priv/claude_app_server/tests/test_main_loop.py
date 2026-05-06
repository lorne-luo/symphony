import json
import pytest
from claude_app_server.__main__ import dispatch
from claude_app_server.session import SessionRegistry


@pytest.mark.asyncio
async def test_initialize():
    registry = SessionRegistry()
    out = []
    async def emit(line): out.append(json.loads(line))
    await dispatch({"id": 1, "method": "initialize", "params": {}}, registry, emit)
    assert len(out) == 1
    assert out[0]["result"]["protocol"] == "symphony-claude-shim/1"


@pytest.mark.asyncio
async def test_thread_start():
    registry = SessionRegistry()
    out = []
    async def emit(line): out.append(json.loads(line))
    await dispatch({"id": 2, "method": "thread/start",
                    "params": {"workspace": "/tmp"}}, registry, emit)
    assert len(out) == 1
    assert "thread_id" in out[0]["result"]


@pytest.mark.asyncio
async def test_shutdown():
    registry = SessionRegistry()
    tid = registry.create(workspace="/tmp")
    out = []
    async def emit(line): out.append(json.loads(line))
    await dispatch({"id": 3, "method": "shutdown",
                    "params": {"thread_id": tid}}, registry, emit)
    assert out[0]["result"] == {}
    assert registry.get(tid) is None


@pytest.mark.asyncio
async def test_unknown_method():
    registry = SessionRegistry()
    out = []
    async def emit(line): out.append(json.loads(line))
    await dispatch({"id": 4, "method": "bogus", "params": {}}, registry, emit)
    assert "error" in out[0]
    assert out[0]["error"]["code"] == -32601
