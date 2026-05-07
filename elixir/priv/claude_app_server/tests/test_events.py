from claude_app_server.events import (
    agent_message_params, function_call_params,
    function_call_output_params, turn_complete_params
)

def test_agent_message():
    p = agent_message_params("hello", "t1", "u1")
    assert p == {"kind": "agent_message", "thread_id": "t1",
                 "turn_id": "u1", "text": "hello"}

def test_function_call():
    p = function_call_params("Bash", "tc1", {"cmd": "ls"}, "t1", "u1")
    assert p["kind"] == "function_call"
    assert p["name"] == "Bash"
    assert p["arguments"] == {"cmd": "ls"}

def test_turn_complete():
    p = turn_complete_params("t1", "u1")
    assert p["kind"] == "turn_complete"
    assert p["result"] == "success"
