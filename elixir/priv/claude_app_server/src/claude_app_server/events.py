"""Map Anthropic SDK events to Codex session/event notification params."""
from __future__ import annotations
from typing import Any


def make_event_params(kind: str, thread_id: str, turn_id: str, **kwargs) -> dict:
    return {"thread_id": thread_id, "turn_id": turn_id, "kind": kind, **kwargs}


def agent_message_params(text: str, thread_id: str, turn_id: str) -> dict:
    return make_event_params("agent_message", thread_id, turn_id, text=text)


def function_call_params(name: str, call_id: str, arguments: dict,
                          thread_id: str, turn_id: str) -> dict:
    return make_event_params("function_call", thread_id, turn_id,
                              name=name, call_id=call_id, arguments=arguments)


def function_call_output_params(call_id: str, output: str,
                                 thread_id: str, turn_id: str) -> dict:
    return make_event_params("function_call_output", thread_id, turn_id,
                              call_id=call_id, output=output)


def turn_complete_params(thread_id: str, turn_id: str,
                          result: str = "success") -> dict:
    return make_event_params("turn_complete", thread_id, turn_id, result=result)
