# LiveKit AR Assistant — Backend Setup

## Overview

The backend consists of two services:

1. **Token Server** (`token_server.py`) — A FastAPI endpoint that generates LiveKit JWTs for the iOS client.
2. **Agent** (`agent.py`) — A LiveKit Agent that connects to Gemini's Multimodal Live API, processes the user's camera feed + audio, and sends AR bounding-box coordinates back to the iOS app via LiveKit Data Channels.

### Architecture

```
iPhone (camera + mic)
      │
      ▼  WebRTC via LiveKit Cloud
┌─────────────────────────────┐
│       LiveKit Cloud          │
│  (media routing, signaling)  │
└────────┬───────────┬────────┘
         │           │
         ▼           ▼
   Token Server    Agent
  (token_server.py) (agent.py)
                     │
                     ▼
              Gemini 2.5 Flash
          (Multimodal Live API)
```

## Prerequisites

- Python 3.10+
- A [LiveKit Cloud](https://cloud.livekit.io/) project (free tier works)
- A [Google AI Studio](https://aistudio.google.com/) API key with Gemini access

## 1. Environment Variables

Create a `.env` file in the **project root** (parent of `livekit_backend/`):

```env
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
GEMINI_API_KEY=your_gemini_key
```

Both `token_server.py` and `agent.py` read from `../.env` relative to their own location.

## 2. Install Dependencies

```bash
cd livekit_backend
pip install -r requirements.txt
```

This installs:

| Package | Purpose |
|---|---|
| `livekit-agents[silero,google,images]` | Agent framework + Silero VAD + Google/Gemini plugin + image helpers |
| `livekit-api` | Server-side token generation |
| `python-dotenv` | Loads `.env` files |
| `fastapi` | Token server HTTP framework |
| `uvicorn` | ASGI server for FastAPI |

## 3. Run the Token Server

```bash
cd livekit_backend
python token_server.py
```

This starts on **port 3001** with auto-reload enabled. It exposes a single endpoint:

### `POST /getToken`

**Request body** (JSON):

```json
{
  "participant_name": "iOS User",
  "room_name": "my-room",
  "participant_identity": "user-123"
}
```

All fields are optional — sensible defaults are generated if omitted.

**Response** (201):

```json
{
  "server_url": "wss://your-project.livekit.cloud",
  "participant_token": "<jwt>"
}
```

The generated token includes a `RoomAgentDispatch` for `"ar-assistant"`, which tells LiveKit Cloud to automatically spin up the agent when a client joins.

### Exposing to a physical device

If your phone can't reach `localhost:3001` (e.g. university WiFi with client isolation), use [ngrok](https://ngrok.com/):

```bash
ngrok http 3001
```

Then update `LiveKitManager.swift` → `tokenServerURL` with the ngrok HTTPS URL.

## 4. Run the Agent

In a **separate terminal**:

```bash
cd livekit_backend
python agent.py dev
```

The `dev` flag connects to LiveKit Cloud in development mode. The agent will automatically join any room that requests the `"ar-assistant"` dispatch.

### What the agent does

1. **Subscribes** to the iOS client's audio and video tracks via LiveKit.
2. **Streams** them to Google's Gemini 2.5 Flash Multimodal Live API in real time.
3. **Speaks** back to the user with step-by-step guidance (voice: Puck).
4. **Calls `draw_bounding_box`** when it identifies a physical object the user should interact with.
5. **Publishes** bounding-box coordinates as JSON on the `"bounding_box"` Data Channel topic:

```json
{
  "type": "bounding_box",
  "label": "cam lock screw",
  "y_min": 0.32,
  "x_min": 0.45,
  "y_max": 0.58,
  "x_max": 0.71
}
```

The iOS app receives this via LiveKit's `RoomDelegate.didReceiveData` and renders an AR overlay.

## Quick Start (both terminals)

```bash
# Terminal 1 — Token Server
cd livekit_backend
python token_server.py

# Terminal 2 — Agent
cd livekit_backend
python agent.py dev
```

Then build and run the iOS app in Xcode on a physical device.
