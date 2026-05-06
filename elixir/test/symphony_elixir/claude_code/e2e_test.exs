defmodule SymphonyElixir.ClaudeCode.E2ETest do
  use ExUnit.Case, async: false
  @moduletag :live_claude

  test "ClaudeCode.AppServer connects to shim and runs a trivial turn" do
    # Requires: ANTHROPIC_API_KEY env, claude CLI installed, shim pip-installed
    # Run with: mix test --include live_claude test/symphony_elixir/claude_code/e2e_test.exs
    Application.put_env(:symphony_elixir, :agent_kind_override, "claude_code")
    Application.put_env(:symphony_elixir, :test_config, %{
      app_server: %{kind: "claude_code", command: "claude-app-server",
                    approval_policy: "never", thread_sandbox: "workspace-write",
                    turn_sandbox_policy: %{}, max_turns: 1}
    })

    workspace = System.tmp_dir!()
    assert {:ok, session} = SymphonyElixir.ClaudeCode.AppServer.start_session(workspace, [])
    assert is_map(session)
    SymphonyElixir.ClaudeCode.AppServer.stop_session(session)
  after
    Application.delete_env(:symphony_elixir, :agent_kind_override)
    Application.delete_env(:symphony_elixir, :test_config)
  end
end
