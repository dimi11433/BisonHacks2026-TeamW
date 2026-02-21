"""
AR Vision — Gemini Live API backend
────────────────────────────────────
Phone camera  →  FastAPI server  →  Gemini Live (persistent WebSocket)
                      ↓
               YOLO bounding boxes (local, real-time)
                      ↓
               Browser via WebSocket (overlays + steps)
"""

import asyncio
import base64
import json
import threading
import time

import cv2
import numpy as np
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from google import genai
from google.genai import types
from ultralytics import YOLO

# ─────────────────────────────────────────────
#  CONFIG — only edit these
# ─────────────────────────────────────────────
GEMINI_API_KEY   = "YOUR_API_KEY_HERE"   # ← paste your key
CAMERA_INDEX     = 0                     # 0 = default webcam
FRAME_INTERVAL   = 0.5                   # seconds between frames sent to Gemini Live
CHANGE_THRESHOLD = 20                    # sensitivity for scene change detection

# ─────────────────────────────────────────────
#  SYSTEM PROMPT
# ─────────────────────────────────────────────
SYSTEM_PROMPT = """You are an AR assistant embedded in smart glasses.
The user is looking at objects through their camera and wants to learn how to use them.

When you see a recognizable object, respond ONLY with a JSON object like this (no markdown, no explanation):
{
  "object": "name of object",
  "tagline": "one sentence describing what it does",
  "steps": [
    { "id": 1, "action": "short label", "detail": "one sentence instruction", "position": "top|middle|bottom|left|right" },
    { "id": 2, "action": "...", "detail": "...", "position": "..." },
    { "id": 3, "action": "...", "detail": "...", "position": "..." }
  ],
  "parts": [
    { "name": "part name", "position": "top|middle|bottom|left|right", "description": "what this part does" }
  ]
}

Position values describe WHERE on the object that step/part is physically located.
Keep steps to 3-5. Be concise.
If no clear usable object is visible, respond with exactly: {"object": null}
Never explain yourself. Always respond with only valid JSON."""

# ─────────────────────────────────────────────
#  APP + MODELS
# ─────────────────────────────────────────────
app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")

gemini_client = genai.Client(api_key=GEMINI_API_KEY)
yolo = YOLO("yolo11n.pt")

# Shared state
state = {
    "frame_b64": None,
    "detections": [],
    "instructions": None,
    "processing": False,
    "connected_to_gemini": False,
}
state_lock = threading.Lock()
frame_queue: asyncio.Queue = None


# ─────────────────────────────────────────────
#  CHANGE DETECTION
# ─────────────────────────────────────────────
_prev_gray = None

def scene_changed(frame: np.ndarray) -> bool:
    global _prev_gray
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)
    if _prev_gray is None:
        _prev_gray = gray
        return True
    diff = cv2.absdiff(_prev_gray, gray)
    score = np.mean(diff)
    if score > CHANGE_THRESHOLD:
        _prev_gray = gray
        return True
    return False


# ─────────────────────────────────────────────
#  YOLO — local real-time detection
# ─────────────────────────────────────────────
def run_yolo(frame: np.ndarray) -> list:
    results = yolo(frame, verbose=False)
    h, w = frame.shape[:2]
    detections = []
    for result in results:
        for box in result.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            detections.append({
                "label": yolo.names[int(box.cls)],
                "confidence": round(float(box.conf), 2),
                "box": {
                    "x": round(x1 / w, 4),
                    "y": round(y1 / h, 4),
                    "w": round((x2 - x1) / w, 4),
                    "h": round((y2 - y1) / h, 4),
                }
            })
    return detections


# ─────────────────────────────────────────────
#  CAMERA LOOP — background thread
# ─────────────────────────────────────────────
def camera_loop(loop: asyncio.AbstractEventLoop):
    cap = cv2.VideoCapture(CAMERA_INDEX)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    print("📷 Camera started")
    last_sent = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.05)
            continue

        detections = run_yolo(frame)

        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
        frame_b64 = base64.standard_b64encode(buf).decode("utf-8")

        with state_lock:
            state["frame_b64"] = frame_b64
            state["detections"] = detections

        # Send to Gemini Live when scene changes
        now = time.time()
        if (now - last_sent) >= FRAME_INTERVAL and scene_changed(frame):
            last_sent = now
            _, buf_hq = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            frame_bytes = buf_hq.tobytes()
            if frame_queue is not None:
                asyncio.run_coroutine_threadsafe(
                    frame_queue.put(frame_bytes), loop
                )

        time.sleep(0.033)

    cap.release()


# ─────────────────────────────────────────────
#  GEMINI LIVE SESSION
# ─────────────────────────────────────────────
async def gemini_live_loop():
    global frame_queue
    frame_queue = asyncio.Queue(maxsize=10)

    print("🤖 Connecting to Gemini Live...")

    config = types.LiveConnectConfig(
        response_modalities=["TEXT"],
        system_instruction=SYSTEM_PROMPT,
    )

    while True:  # auto-reconnect loop
        try:
            async with gemini_client.aio.live.connect(
                model="gemini-2.0-flash-live-001",
                config=config
            ) as session:

                with state_lock:
                    state["connected_to_gemini"] = True
                print("✅ Gemini Live connected!")

                # Buffer for assembling partial JSON responses
                response_buffer = ""

                async def send_frames():
                    while True:
                        frame_bytes = await frame_queue.get()
                        try:
                            await session.send(
                                input=types.LiveClientRealtimeInput(
                                    media_chunks=[
                                        types.Blob(
                                            data=frame_bytes,
                                            mime_type="image/jpeg"
                                        )
                                    ]
                                )
                            )
                            with state_lock:
                                state["processing"] = True
                        except Exception as e:
                            print(f"⚠️ Send error: {e}")

                async def receive_responses():
                    nonlocal response_buffer
                    async for response in session.receive():
                        # Extract text from response
                        text = ""
                        if hasattr(response, "text") and response.text:
                            text = response.text
                        elif hasattr(response, "server_content") and response.server_content:
                            sc = response.server_content
                            if hasattr(sc, "model_turn") and sc.model_turn:
                                for part in sc.model_turn.parts:
                                    if hasattr(part, "text") and part.text:
                                        text += part.text

                        if not text:
                            continue

                        response_buffer += text

                        # Try to parse whenever buffer looks like complete JSON
                        clean = response_buffer.strip()
                        if clean.startswith("```"):
                            for chunk in clean.split("```"):
                                if chunk.startswith("json"):
                                    clean = chunk[4:].strip()
                                    break
                                elif "{" in chunk:
                                    clean = chunk.strip()
                                    break

                        if clean.startswith("{") and clean.endswith("}"):
                            try:
                                data = json.loads(clean)
                                with state_lock:
                                    state["instructions"] = data
                                    state["processing"] = False
                                print(f"✨ Detected: {data.get('object', 'nothing')}")
                                response_buffer = ""  # reset for next response
                            except json.JSONDecodeError:
                                pass  # incomplete, keep buffering

                await asyncio.gather(send_frames(), receive_responses())

        except Exception as e:
            print(f"❌ Gemini Live error: {e}")
            with state_lock:
                state["connected_to_gemini"] = False
                state["processing"] = False
            print("🔄 Reconnecting in 3s...")
            await asyncio.sleep(3)


# ─────────────────────────────────────────────
#  WEBSOCKET — streams to browser
# ─────────────────────────────────────────────
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("🔌 Browser connected")
    try:
        while True:
            with state_lock:
                payload = {
                    "frame":        state["frame_b64"],
                    "detections":   state["detections"],
                    "instructions": state["instructions"],
                    "processing":   state["processing"],
                    "gemini_live":  state["connected_to_gemini"],
                }
            if payload["frame"]:
                await websocket.send_json(payload)
            await asyncio.sleep(0.033)
    except WebSocketDisconnect:
        print("🔌 Browser disconnected")


@app.get("/")
async def root():
    with open("static/index.html") as f:
        return HTMLResponse(f.read())


# ─────────────────────────────────────────────
#  STARTUP
# ─────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    loop = asyncio.get_event_loop()
    threading.Thread(target=camera_loop, args=(loop,), daemon=True).start()
    asyncio.create_task(gemini_live_loop())
    print("🚀 Server ready → http://localhost:8000")


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)