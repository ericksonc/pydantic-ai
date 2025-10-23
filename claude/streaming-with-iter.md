# Streaming Everything with Pydantic AI: A Comprehensive Guide

**Goal:** Stream not just text deltas, but also tool calls and their arguments to a FastAPI endpoint for web client consumption.

## Quick Summary

Pydantic AI provides **three levels** of streaming control:

1. **High-level:** `agent.run_stream()` → stream text/structured output easily
2. **Mid-level:** Event stream handlers → capture all events without manual iteration
3. **Low-level:** `agent.iter()` → node-by-node control with complete event access

For streaming to FastAPI with tool calls, you'll typically use either:
- **Option A:** `run_stream()` + event_stream_handler (recommended)
- **Option B:** `agent.iter()` with manual node streaming (advanced)

---

## 1. Understanding the Streaming Architecture

### The Event Types

Located in: `pydantic_ai_slim/pydantic_ai/messages.py:1600-1750`

**Model Response Events** (text and tool call streaming):
```python
# When a new part begins (text, tool call, thinking, etc.)
PartStartEvent
  - index: int
  - part: ModelResponsePart (TextPart | ToolCallPart | ThinkingPart)

# Incremental updates (deltas)
PartDeltaEvent
  - index: int
  - delta: ModelResponsePartDelta
    - TextPartDelta(content_delta='The ')  # Text streaming
    - ToolCallPartDelta(args_delta='{"qu')  # Tool args streaming
    - ThinkingPartDelta(thinking_delta='...')

# Final result indicator
FinalResultEvent
  - tool_name: str | None
  - tool_call_id: str | None
```

**Tool Execution Events**:
```python
# Before tool execution
FunctionToolCallEvent
  - part: ToolCallPart
  - tool_call_id: str

# After tool execution
FunctionToolResultEvent
  - result: ToolReturnPart | RetryPromptPart
  - content: list[UserContent] | None
```

**Combined Type**:
```python
AgentStreamEvent = ModelResponseStreamEvent | HandleResponseEvent
# This union includes all the above events
```

### The Flow

```
User Prompt
    ↓
Agent Graph Iteration
    ↓
UserPromptNode (sync, no streaming)
    ↓
ModelRequestNode ──→ Streams: PartStartEvent, PartDeltaEvent, FinalResultEvent
    ↓                (Text chunks, tool call args appear here)
CallToolsNode ──→ Streams: FunctionToolCallEvent, FunctionToolResultEvent
    ↓                (Tool execution happens here)
[Loop until final result]
    ↓
Final Result
```

---

## 2. Option A: Using `run_stream()` + Event Handler (RECOMMENDED)

**Location:** `pydantic_ai_slim/pydantic_ai/agent/abstract.py:394-582`

This is the cleanest approach for FastAPI endpoints.

### Basic Pattern

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
import json

@app.post('/chat/')
async def chat_endpoint(prompt: str):
    async def stream_events():
        async with agent.run_stream(prompt) as result:
            # Option 1: Stream text only
            async for text in result.stream_text(debounce_by=0.01):
                yield json.dumps({'type': 'text', 'content': text}).encode() + b'\n'

    return StreamingResponse(stream_events(), media_type='application/x-ndjson')
```

### Advanced: Capturing Tool Calls + Text

```python
async def stream_with_tools():
    """Stream both text and tool execution events."""

    # Event buffer to emit from handler
    event_queue = asyncio.Queue()

    # Event stream handler captures all events
    async def event_stream_handler(
        ctx: RunContext[None],
        stream: AsyncIterable[AgentStreamEvent]
    ):
        async for event in stream:
            # Text streaming
            if isinstance(event, PartStartEvent) and isinstance(event.part, TextPart):
                await event_queue.put({
                    'type': 'text_start',
                    'content': event.part.content,
                    'index': event.index
                })

            elif isinstance(event, PartDeltaEvent) and isinstance(event.delta, TextPartDelta):
                await event_queue.put({
                    'type': 'text_delta',
                    'content': event.delta.content_delta,
                    'index': event.index
                })

            # Tool call streaming
            elif isinstance(event, PartStartEvent) and isinstance(event.part, ToolCallPart):
                await event_queue.put({
                    'type': 'tool_call_start',
                    'tool_name': event.part.tool_name,
                    'tool_call_id': event.part.tool_call_id,
                    'index': event.index
                })

            elif isinstance(event, PartDeltaEvent) and isinstance(event.delta, ToolCallPartDelta):
                await event_queue.put({
                    'type': 'tool_args_delta',
                    'args_delta': event.delta.args_delta,
                    'index': event.index
                })

            # Tool execution
            elif isinstance(event, FunctionToolCallEvent):
                await event_queue.put({
                    'type': 'tool_executing',
                    'tool_name': event.part.tool_name,
                    'tool_call_id': event.tool_call_id,
                    'args': event.part.args_as_dict()  # Full args
                })

            elif isinstance(event, FunctionToolResultEvent):
                await event_queue.put({
                    'type': 'tool_result',
                    'result': str(event.result)  # Serialize appropriately
                })

            # Final result
            elif isinstance(event, FinalResultEvent):
                await event_queue.put({
                    'type': 'final_result',
                    'from_tool': event.tool_name
                })

        # Signal completion
        await event_queue.put(None)

    # Run agent with handler
    async with agent.run_stream(
        prompt,
        event_stream_handler=event_stream_handler
    ) as result:
        # Emit events from queue
        while True:
            event = await event_queue.get()
            if event is None:
                break
            yield json.dumps(event).encode() + b'\n'

        # Optionally emit final structured result
        final_data = await result.data()
        yield json.dumps({
            'type': 'complete',
            'data': final_data
        }).encode() + b'\n'
```

**FastAPI Integration:**
```python
@app.post('/chat/')
async def chat_with_tools(prompt: str):
    return StreamingResponse(
        stream_with_tools(),
        media_type='application/x-ndjson'
    )
```

---

## 3. Option B: Using `agent.iter()` for Maximum Control

**Location:** `pydantic_ai_slim/pydantic_ai/agent/__init__.py:451-694`

For when you need node-by-node control.

### Basic Pattern

```python
async def stream_with_iter(prompt: str):
    """Low-level streaming with agent.iter()."""

    async with agent.iter(prompt) as agent_run:
        # Iterate through graph nodes
        async for node in agent_run:
            # Model request node - streams model output
            if agent.is_model_request_node(node):
                async with node.stream(agent_run.ctx) as stream:
                    # Access raw events
                    async for event in stream:
                        if isinstance(event, PartStartEvent):
                            yield json.dumps({
                                'type': 'part_start',
                                'part_type': type(event.part).__name__,
                                'index': event.index
                            }).encode() + b'\n'

                        elif isinstance(event, PartDeltaEvent):
                            if isinstance(event.delta, TextPartDelta):
                                yield json.dumps({
                                    'type': 'text_delta',
                                    'content': event.delta.content_delta
                                }).encode() + b'\n'

                            elif isinstance(event.delta, ToolCallPartDelta):
                                yield json.dumps({
                                    'type': 'tool_args_delta',
                                    'args': event.delta.args_delta
                                }).encode() + b'\n'

            # Tool execution node - streams tool events
            elif agent.is_call_tools_node(node):
                async with node.stream(agent_run.ctx) as stream:
                    async for event in stream:
                        if isinstance(event, FunctionToolCallEvent):
                            yield json.dumps({
                                'type': 'tool_call',
                                'tool_name': event.part.tool_name,
                                'args': event.part.args_as_dict()
                            }).encode() + b'\n'

                        elif isinstance(event, FunctionToolResultEvent):
                            yield json.dumps({
                                'type': 'tool_result',
                                'result': str(event.result)
                            }).encode() + b'\n'

        # Get final result
        result = agent_run.result()
        yield json.dumps({
            'type': 'complete',
            'data': result.data
        }).encode() + b'\n'
```

**FastAPI Integration:**
```python
@app.post('/chat/advanced/')
async def chat_with_iter(prompt: str):
    return StreamingResponse(
        stream_with_iter(prompt),
        media_type='application/x-ndjson'
    )
```

---

## 4. Streaming Methods Reference

**Location:** `pydantic_ai_slim/pydantic_ai/result.py:61-250`

### Available on `StreamedRunResult` (from `run_stream()`):

```python
# Stream text deltas
async for text in result.stream_text(delta=True, debounce_by=0.01):
    # delta=True: yields only new text chunks ["The ", "cat "]
    # delta=False: yields accumulated text ["The ", "The cat "]
    # debounce_by: groups tokens within time window (reduces overhead)
    pass

# Stream validated structured output (uses Pydantic partial validation)
async for partial_output in result.stream_output(debounce_by=0.01):
    # Yields validated OutputDataT as it becomes available
    pass

# Stream ModelResponse objects
async for response in result.stream_responses(debounce_by=0.01):
    # Yields ModelResponse with all parts accumulated so far
    pass
```

### Available on `AgentStream` (from node.stream()):

```python
async with node.stream(agent_run.ctx) as stream:
    # Raw event iteration (PartStartEvent, PartDeltaEvent, etc.)
    async for event in stream:
        pass

    # Or use high-level methods
    async for text in stream.stream_text():
        pass
```

---

## 5. Customization Options

### Debouncing

Control how tokens are grouped:
```python
# No debouncing - emit every token immediately
stream_text(debounce_by=None)

# Group tokens within 10ms window
stream_text(debounce_by=0.01)

# Group tokens within 100ms window (fewer emissions)
stream_text(debounce_by=0.1)
```

**Trade-off:** Lower debounce = more responsive, higher overhead. Higher debounce = less overhead, slightly delayed.

### Delta vs Accumulated

```python
# Delta mode - only new content
async for text in result.stream_text(delta=True):
    print(text)  # "The ", "cat ", "sat"

# Accumulated mode - full content so far
async for text in result.stream_text(delta=False):
    print(text)  # "The ", "The cat ", "The cat sat"
```

### End Strategy

Controls when agent stops:
```python
# Stop after first final result (default)
agent = Agent(model, end_strategy='early')

# Execute all tools before stopping
agent = Agent(model, end_strategy='exhaustive')
```

---

## 6. Complete FastAPI Example

**Based on:** `examples/pydantic_ai_examples/chat_app.py:109-139`

```python
from fastapi import FastAPI, Depends
from fastapi.responses import StreamingResponse
from pydantic_ai import Agent
from pydantic_ai.messages import ModelResponse, TextPart, AgentStreamEvent
import json

app = FastAPI()
agent = Agent('openai:gpt-4', tools=[...])

@app.post('/chat/')
async def chat(prompt: str):
    """Stream text and tool events to client as NDJSON."""

    async def stream_response():
        # Emit user prompt immediately
        yield json.dumps({
            'role': 'user',
            'content': prompt
        }).encode() + b'\n'

        # Event handler to capture everything
        events = asyncio.Queue()

        async def handler(ctx, stream: AsyncIterable[AgentStreamEvent]):
            async for event in stream:
                # Process and queue events
                if isinstance(event, PartDeltaEvent) and isinstance(event.delta, TextPartDelta):
                    await events.put({
                        'type': 'text',
                        'content': event.delta.content_delta
                    })
                elif isinstance(event, FunctionToolCallEvent):
                    await events.put({
                        'type': 'tool_call',
                        'tool': event.part.tool_name,
                        'args': event.part.args_as_dict()
                    })
                elif isinstance(event, FunctionToolResultEvent):
                    await events.put({
                        'type': 'tool_result',
                        'result': str(event.result)
                    })
            await events.put(None)  # Signal completion

        # Run agent
        async with agent.run_stream(prompt, event_stream_handler=handler) as result:
            # Emit queued events
            while True:
                event = await events.get()
                if event is None:
                    break
                yield json.dumps(event).encode() + b'\n'

            # Final message
            yield json.dumps({
                'role': 'assistant',
                'complete': True,
                'timestamp': result.timestamp().isoformat()
            }).encode() + b'\n'

    return StreamingResponse(
        stream_response(),
        media_type='application/x-ndjson'
    )
```

---

## 7. Summary: Which Approach to Use?

| Scenario | Recommended Approach | Why |
|----------|---------------------|-----|
| Text-only streaming | `run_stream()` + `stream_text()` | Simplest, built-in |
| Text + basic tool info | `run_stream()` + event handler | Clean separation, easy to extend |
| Full control over execution | `agent.iter()` with manual streaming | Access to node-level details |
| Server-Sent Events (SSE) | `run_stream()` + event handler | Natural mapping to event types |
| WebSocket streaming | `agent.iter()` | Fine-grained control for bidirectional |
| Structured output streaming | `run_stream()` + `stream_output()` | Pydantic partial validation |

---

## 8. Key Files Reference

| Component | File | Lines |
|-----------|------|-------|
| `agent.iter()` implementation | `pydantic_ai_slim/pydantic_ai/agent/__init__.py` | 451-694 |
| Event type definitions | `pydantic_ai_slim/pydantic_ai/messages.py` | 1602-1750 |
| AgentStream & streaming methods | `pydantic_ai_slim/pydantic_ai/result.py` | 45-530 |
| `run_stream()` implementation | `pydantic_ai_slim/pydantic_ai/agent/abstract.py` | 394-582 |
| FastAPI chat example | `examples/pydantic_ai_examples/chat_app.py` | 109-139 |
| Streaming documentation | `docs/agents.md` | 117-561 |

---

## Final Recommendation

For your use case (streaming text, tool calls, and arguments to FastAPI):

**Use `agent.run_stream()` with an event stream handler.**

Why:
1. Clean separation between event capture and response streaming
2. Access to all event types (text deltas, tool calls, tool results)
3. Works naturally with FastAPI's `StreamingResponse`
4. Easy to extend with new event types
5. Less boilerplate than manual `iter()` usage

The event handler pattern gives you complete visibility into the agent's execution while keeping the streaming logic simple and maintainable.
