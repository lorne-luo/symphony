import asyncio
import pytest
from claude_app_server.session import Session, SessionRegistry


def test_session_creates_thread_id():
    s = Session(workspace="/tmp")
    assert len(s.thread_id) == 36  # UUID format


def test_registry_create_and_get():
    reg = SessionRegistry()
    tid = reg.create(workspace="/tmp")
    session = reg.get(tid)
    assert session is not None
    assert session.workspace == "/tmp"


def test_registry_remove():
    reg = SessionRegistry()
    tid = reg.create(workspace="/tmp")
    reg.remove(tid)
    assert reg.get(tid) is None


def test_session_build_command_first_turn():
    s = Session(workspace="/tmp", command="claude")
    cmd = s._build_command("hello")
    assert cmd[:5] == ["claude", "-p", "hello", "--output-format", "stream-json"]
    assert "--resume" not in cmd


def test_session_build_command_with_session_id():
    s = Session(workspace="/tmp")
    s._session_id = "sess-123"
    cmd = s._build_command("next")
    assert "--resume" in cmd
    assert "sess-123" in cmd
