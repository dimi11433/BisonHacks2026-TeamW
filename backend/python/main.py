"""
AR Vision — Dual-model backend
  • gemini-2.5-flash-native-audio-preview-12-2025  →  voice conversation (mic in / speaker out)
  • gemini-2.5-flash                               →  AR overlay JSON (camera snapshots)
"""

import asyncio
import base64
import json
import threading
import time

import cv2
import numpy as np
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from google import genai
from google.genai import types
from ultralytics import YOLO

# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
GEMINI_API_KEY   = "AIzaSyDK6jsEOZ7fAFWC5qkUuETeKlZj7F9EqqA"
CAMERA_INDEX     = 0
FRAME_INTERVAL   = 2.0
CHANGE_THRESHOLD = 20

VOICE_MODEL   = "gemini-2.5-flash-native-audio-preview-12-2025"
OVERLAY_MODEL = "gemini-2.5-flash"

VOICE_SYSTEM_PROMPT = """You are an AR assistant embedded in smart glasses helping the user 
interact with objects in their environment. You can see what the user sees through their camera.
Be concise, helpful, and conversational. When you identify an object, briefly tell the user 
what it is and how to use it. Keep responses short since they'll be spoken aloud."""

OVERLAY_SYSTEM_PROMPT = """You are an AR assistant embedded in smart glasses.
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

Keep steps to 3-5. Be concise.
If no clear usable object is visible, respond with exactly: {"object": null}
Never explain yourself. Always respond with only valid JSON."""

# ─────────────────────────────────────────────
#  INIT
# ─────────────────────────────────────────────
gemini_client = genai.Client(api_key=GEMINI_API_KEY)
yolo = YOLO("yolo11n.pt")

state = {
    "frame_b64": None,
    "detections": [],
    "instructions": None,
    "processing": False,
    "voice_connected": False,
    "overlay_connected": False,
}
state_lock = threading.Lock()

overlay_frame_queue: asyncio.Queue = None
mic_audio_queue: asyncio.Queue = None
speaker_audio_queue: asyncio.Queue = None


# ─────────────────────────────────────────────
#  CHANGE DETECTION
# ─────────────────────────────────────────────
_prev_gray = None
_prev_shape = None

def scene_changed(frame: np.ndarray) -> bool:
    global _prev_gray, _prev_shape
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)
    if _prev_gray is None or _prev_shape != gray.shape:
        _prev_gray = gray
        _prev_shape = gray.shape
        return True
    diff = cv2.absdiff(_prev_gray, gray)
    if np.mean(diff) > CHANGE_THRESHOLD:
        _prev_gray = gray
        return True
    return False


# ─────────────────────────────────────────────
#  YOLO
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
                "box": {"x": round(x1/w,4), "y": round(y1/h,4),
                        "w": round((x2-x1)/w,4), "h": round((y2-y1)/h,4)}
            })
    return detections


# ─────────────────────────────────────────────
#  CAMERA LOOP
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

        now = time.time()
        if (now - last_sent) >= FRAME_INTERVAL and scene_changed(frame):
            last_sent = now
            _, buf_hq = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if overlay_frame_queue is not None:
                asyncio.run_coroutine_threadsafe(
                    overlay_frame_queue.put(buf_hq.tobytes()), loop
                )
        time.sleep(0.033)
    cap.release()


# ─────────────────────────────────────────────
#  OVERLAY LOOP — gemini-2.5-flash snapshots → JSON
# ─────────────────────────────────────────────
async def overlay_loop():
    global overlay_frame_queue
    overlay_frame_queue = asyncio.Queue(maxsize=5)
    print("🔍 AR overlay loop started")

    while True:
        try:
            frame_bytes = await overlay_frame_queue.get()
            with state_lock:
                state["processing"] = True

            image_b64 = base64.standard_b64encode(frame_bytes).decode("utf-8")

            response = await gemini_client.aio.models.generate_content(
                model=OVERLAY_MODEL,
                contents=[
                    types.Content(role="user", parts=[
                        types.Part(text=OVERLAY_SYSTEM_PROMPT),
                        types.Part(inline_data=types.Blob(
                            mime_type="image/jpeg",
                            data=image_b64
                        )),
                        types.Part(text="What object is this and how do I use it? JSON only.")
                    ])
                ]
            )

            text = response.text.strip() if response.text else ""
            if "```" in text:
                for chunk in text.split("```"):
                    c = chunk.strip().lstrip("json").strip()
                    if c.startswith("{"):
                        text = c
                        break

            if text.startswith("{") and text.endswith("}"):
                try:
                    data = json.loads(text)
                    with state_lock:
                        state["instructions"] = data
                        state["processing"] = False
                        state["overlay_connected"] = True
                    print(f"✨ AR overlay: {data.get('object', 'nothing')}")
                except json.JSONDecodeError:
                    with state_lock:
                        state["processing"] = False
            else:
                with state_lock:
                    state["processing"] = False

        except Exception as e:
            print(f"❌ Overlay error: {e}")
            with state_lock:
                state["processing"] = False
            await asyncio.sleep(1)


# ─────────────────────────────────────────────
#  VOICE LOOP — native-audio Live (mic ↔ speaker)
# ─────────────────────────────────────────────
async def voice_loop():
    global mic_audio_queue, speaker_audio_queue
    mic_audio_queue = asyncio.Queue(maxsize=20)
    speaker_audio_queue = asyncio.Queue(maxsize=50)
    print("🎙️ Voice loop started")

    config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=VOICE_SYSTEM_PROMPT,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Aoede")
            )
        ),
    )

    while True:
        try:
            async with gemini_client.aio.live.connect(
                model=VOICE_MODEL, config=config
            ) as session:

                with state_lock:
                    state["voice_connected"] = True
                print("✅ Voice connected!")

                async def send_mic():
                    while True:
                        chunk = await mic_audio_queue.get()
                        try:
                            await session.send(input=types.LiveClientRealtimeInput(
                                media_chunks=[types.Blob(data=chunk, mime_type="audio/pcm;rate=16000")]
                            ))
                        except Exception as e:
                            print(f"⚠️ Mic send: {e}")
                            break

                async def send_camera():
                    """Periodically give Gemini a visual context frame"""
                    while True:
                        await asyncio.sleep(4)
                        with state_lock:
                            fb64 = state.get("frame_b64")
                        if fb64:
                            try:
                                await session.send(input=types.LiveClientRealtimeInput(
                                    media_chunks=[types.Blob(
                                        data=base64.standard_b64decode(fb64),
                                        mime_type="image/jpeg"
                                    )]
                                ))
                            except Exception:
                                pass

                async def recv_audio():
                    async for response in session.receive():
                        try:
                            sc = response.server_content
                            if sc and sc.model_turn:
                                for part in sc.model_turn.parts:
                                    if hasattr(part, "inline_data") and part.inline_data:
                                        audio_b64 = base64.standard_b64encode(
                                            part.inline_data.data
                                        ).decode()
                                        if not speaker_audio_queue.full():
                                            await speaker_audio_queue.put(audio_b64)
                        except Exception as e:
                            print(f"⚠️ Audio recv: {e}")

                await asyncio.gather(send_mic(), send_camera(), recv_audio())

        except Exception as e:
            print(f"❌ Voice error: {e}")
            with state_lock:
                state["voice_connected"] = False
            print("🔄 Voice reconnecting in 3s...")
            await asyncio.sleep(3)


# ─────────────────────────────────────────────
#  FASTAPI + WEBSOCKET
# ─────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    loop = asyncio.get_event_loop()
    threading.Thread(target=camera_loop, args=(loop,), daemon=True).start()
    asyncio.create_task(overlay_loop())
    asyncio.create_task(voice_loop())
    print("🚀 AR Vision ready → http://localhost:8000")
    yield

app = FastAPI(lifespan=lifespan)
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("🔌 Browser connected")

    async def send_state():
        while True:
            with state_lock:
                payload = {
                    "frame":        state["frame_b64"],
                    "detections":   state["detections"],
                    "instructions": state["instructions"],
                    "processing":   state["processing"],
                    "voice_live":   state["voice_connected"],
                    "overlay_live": state["overlay_connected"],
                    "audio":        None,
                }
            if speaker_audio_queue and not speaker_audio_queue.empty():
                try:
                    payload["audio"] = speaker_audio_queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            if payload["frame"]:
                await websocket.send_json(payload)
            await asyncio.sleep(0.033)

    async def recv_mic():
        while True:
            try:
                msg = await websocket.receive()
                if "bytes" in msg and mic_audio_queue and not mic_audio_queue.full():
                    await mic_audio_queue.put(msg["bytes"])
                elif "text" in msg:
                    data = json.loads(msg["text"])
                    if data.get("type") == "mic_audio" and mic_audio_queue:
                        raw = base64.standard_b64decode(data["data"])
                        if not mic_audio_queue.full():
                            await mic_audio_queue.put(raw)
            except WebSocketDisconnect:
                raise
            except Exception:
                await asyncio.sleep(0.01)

    try:
        await asyncio.gather(send_state(), recv_mic())
    except WebSocketDisconnect:
        print("🔌 Browser disconnected")


@app.get("/")
async def root():
    with open("static/index.html") as f:
        return HTMLResponse(f.read())


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)