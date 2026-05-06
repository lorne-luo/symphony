"""Run Claude Code CLI as subprocess, parse stream-json output."""
from __future__ import annotations
import asyncio
import json
import uuid
from typing import AsyncIterator


class Session:
    def __init__(self, workspace: str, command: str = "claude"):
        self.workspace = workspace
        self.command = command
        self.thread_id = str(uuid.uuid4())
        self._session_id: str | None = None

    async def run_turn(self, prompt: str) -> AsyncIterator[dict]:
        """Run one turn, yielding raw SDK event dicts."""
        cmd = self._build_command(prompt)
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=self.workspace,
        )
        assert proc.stdout is not None
        async for line in proc.stdout:
            stripped = line.strip()
            if not stripped:
                continue
            try:
                event = json.loads(stripped)
                yield event
            except json.JSONDecodeError:
                continue
        await proc.wait()

    def _build_command(self, prompt: str) -> list[str]:
        parts = [self.command, "-p", prompt, "--output-format", "stream-json",
                 "--permission-mode", "acceptEdits"]
        if self._session_id:
            parts += ["--resume", self._session_id]
        return parts


class SessionRegistry:
    def __init__(self):
        self._sessions: dict[str, Session] = {}

    def create(self, workspace: str, command: str = "claude") -> str:
        s = Session(workspace=workspace, command=command)
        self._sessions[s.thread_id] = s
        return s.thread_id

    def get(self, thread_id: str) -> Session | None:
        return self._sessions.get(thread_id)

    def remove(self, thread_id: str) -> None:
        self._sessions.pop(thread_id, None)
