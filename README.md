# W Vision

An AR assistant for iOS that sees what you see and guides you through hands-on physical tasks — assembling furniture, wiring hardware, applying first aid, or anything that benefits from spatial, step-by-step guidance.

Built at BisonHacks 2026.

---

## What it does

- Streams live video and audio from an iPhone (or paired Meta Ray-Ban smart glasses) to a Gemini 2.5 Flash multimodal AI agent via LiveKit.
- The AI speaks back with step-by-step instructions and draws labeled bounding boxes directly over objects it wants you to interact with.
- Supports AR animation overlays for structured workflows (e.g., tourniquet application steps).
- Voice-activated and hands-free — no tapping required once the session is live.

---

## Architecture

```
iPhone / Meta Ray-Ban glasses (camera + mic)
           |
           | WebRTC (LiveKit SDK)
           v
     LiveKit Cloud
     (media routing)
      /          \
     v            v
Token Server    AR Agent
(FastAPI)       (agent.py)
                    |
                    v
           Gemini 2.5 Flash
        (Multimodal Live API)
                    |
            draw_bounding_box()
            show_ar_step()
                    |
                    v
         LiveKit Data Channel
                    |
                    v
         iOS app renders AR overlay
```

---

## Project Structure

```
BisonHacks2026-TeamW/
  Frontend/               iOS SwiftUI app (Xcode)
  livekit_backend/        Python backend (token server + agent)
  backend/                Legacy web prototype (unused)
```

---

## Prerequisites

- Xcode 16+ and a physical iOS device (camera access required)
- Python 3.10+
- A LiveKit Cloud project (free tier works): https://cloud.livekit.io
- A Google AI Studio API key with Gemini access: https://aistudio.google.com
- Meta AI app installed on the same phone (only needed for Ray-Ban glasses)

---

## Backend Setup

### 1. Create a .env file in the project root

```
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
GEMINI_API_KEY=your_gemini_key
```

### 2. Install dependencies

```bash
cd livekit_backend
pip install -r requirements.txt
```

### 3. Run the token server (Terminal 1)

```bash
cd livekit_backend
python token_server.py
```

Starts on port 3001. Exposes `POST /getToken` which returns a LiveKit JWT and server URL.

### 4. Run the AI agent (Terminal 2)

```bash
cd livekit_backend
python agent.py dev
```

The agent joins any LiveKit room that requests the `ar-assistant` dispatch. It subscribes to the iOS client's video and audio, streams them to Gemini, and sends bounding-box coordinates and AR step instructions back via LiveKit Data Channels.

### 5. Expose to a physical device (if needed)

If the phone cannot reach localhost (e.g., university WiFi with client isolation):

```bash
ngrok http 3001
```

Update `tokenServerURL` in `Frontend/Services/LiveKitManager.swift` with the ngrok HTTPS URL.

---

## iOS App Setup

1. Open `W.xcodeproj` in Xcode.
2. Set your development team under Signing and Capabilities.
3. Build and run on a physical iOS device.

On first launch, tap the Meta Ray-Ban status row to pair glasses via the Meta AI app. If glasses are not connected, the app falls back to the iPhone's rear camera automatically.

Tap "Start Live" to begin a session. The app connects to LiveKit, the agent joins, and you can start talking.

---

## How the AR overlay works

The AI agent calls two tools during a session:

- `draw_bounding_box` — sends normalized coordinates (0.0 to 1.0) for an object label. The iOS app renders a labeled rectangle over that region of the live video feed.
- `show_ar_step` — sends a step number, animation name, and instruction text. The iOS app plays the corresponding AR animation and displays the instruction on screen.

Data is delivered over LiveKit's reliable Data Channel, not audio, so overlays stay in sync with the video frame.
