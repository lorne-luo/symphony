# claude-app-server

A Python shim that speaks the Codex app-server JSON-RPC 2.0 protocol over stdio,
but runs prompts through the Claude Code CLI (`claude`) as a subprocess.

## What this is

Symphony's Elixir orchestrator spawns an "app-server" process and communicates with it
via newline-delimited JSON-RPC 2.0 on stdin/stdout. This shim implements that protocol,
forwarding each `turn/start` prompt to `claude -p <prompt> --output-format stream-json`,
then translating the Claude Code stream-json events back into Codex `session/event`
notifications.

## Requirements

- Python 3.11+
- Claude Code CLI: `npm install -g @anthropic-ai/claude-code`
- `ANTHROPIC_API_KEY` environment variable set

## Install

```bash
pip install -e "elixir/priv/claude_app_server"
```

For development (includes pytest):

```bash
pip install -e "elixir/priv/claude_app_server[dev]"
```

## Run tests

```bash
cd elixir/priv/claude_app_server
python -m pytest -q
```

## Symphony configuration

In your Symphony `config.exs` or runtime config:

```elixir
config :symphony, :app_server,
  kind: "claude_code",
  command: "claude-app-server"
```

## How it works

1. The Elixir process spawns `claude-app-server` and writes JSON-RPC requests to its stdin.
2. On `thread/start`, the shim creates a `Session` object (holding workspace path and optional `--resume` session ID).
3. On `turn/start`, the shim runs `claude -p "<prompt>" --output-format stream-json` as a subprocess, parses each line of stream-json output, and emits `session/event` JSON-RPC notifications (agent messages, tool calls, turn completion) back to stdout before sending the final `turn/start` response.

## Protocol summary

| Method | Description |
|--------|-------------|
| `initialize` | Handshake; returns `{"protocol": "symphony-claude-shim/1"}` |
| `thread/start` | Creates a session; returns `{"thread_id": "..."}` |
| `turn/start` | Runs prompt; streams `session/event` notifications then responds |
| `shutdown` | Cleans up session |
