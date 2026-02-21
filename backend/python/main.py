import cv2
import numpy as np
import base64
import json
import time
import threading
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import google.generativeai as genai
import uvicorn
from ultralytics import YOLO

# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
GEMINI_API_KEY = "YOUR_API_KEY_HERE"       # <-- paste your Gemini key
FRAME_CHANGE_THRESHOLD = 25               # sensitivity for change detection
AI_COOLDOWN_SECONDS = 3                   # min seconds between AI calls
CAMERA_INDEX = 0                          # 0 = default webcam

# ─────────────────────────────────────────────
#  INIT
# ─────────────────────────────────────────────
app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")

genai.configure(api_key=GEMINI_API_KEY)
gemini = genai.GenerativeModel("gemini-1.5-flash")
yolo = YOLO("yolo11n.pt")  # downloads automatically on first run

# Shared state between camera thread and websocket
state = {
    "latest_frame": None,
    "latest_detections": [],
    "latest_instructions": None,
    "last_ai_call": 0,
    "prev_gray": None,
    "is_processing": False,
}
state_lock = threading.Lock()


# ─────────────────────────────────────────────
#  FRAME CHANGE DETECTION
# ─────────────────────────────────────────────
def scene_changed(frame: np.ndarray) -> bool:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)

    with state_lock:
        prev = state["prev_gray"]
        if prev is None:
            state["prev_gray"] = gray
            return True
        diff = cv2.absdiff(prev, gray)
        score = np.mean(diff)
        if score > FRAME_CHANGE_THRESHOLD:
            state["prev_gray"] = gray
            return True
    return False


# ─────────────────────────────────────────────
#  CLAUDE VISION — identify object + get steps
# ─────────────────────────────────────────────
def ask_gemini(frame: np.ndarray) -> dict:
    _, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
    b64 = base64.standard_b64encode(buffer).decode("utf-8")

    prompt = """You are an AR assistant. Look at this image and respond ONLY with valid JSON (no markdown, no explanation).

If you see a recognizable object that someone might want to learn to use, return:
{
  "object": "name of object",
  "tagline": "one sentence what it does",
  "steps": [
    { "id": 1, "action": "short action label", "detail": "one sentence instruction", "position": "top|middle|bottom|left|right" },
    { "id": 2, "action": "...", "detail": "...", "position": "..." },
    { "id": 3, "action": "...", "detail": "...", "position": "..." }
  ],
  "parts": [
    { "name": "part name", "position": "top|middle|bottom|left|right", "description": "what this part does" }
  ]
}

If no clear object, return: { "object": null }

Keep steps to 3-5. Position values describe where on the object that step/part is located."""

    image_part = {"mime_type": "image/jpeg", "data": b64}
    response = gemini.generate_content([prompt, image_part])

    raw = response.text.strip()
    # Strip markdown code fences if Gemini adds them
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw.strip())


# ─────────────────────────────────────────────
#  YOLO DETECTION
# ─────────────────────────────────────────────
def run_yolo(frame: np.ndarray) -> list:
    results = yolo(frame, verbose=False)
    detections = []
    h, w = frame.shape[:2]

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
#  CAMERA LOOP (runs in background thread)
# ─────────────────────────────────────────────
def camera_loop():
    cap = cv2.VideoCapture(CAMERA_INDEX)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    print("📷 Camera started")

    while True:
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.05)
            continue

        # Always run YOLO (fast, local)
        detections = run_yolo(frame)

        # Encode frame as base64 JPEG for browser
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
        frame_b64 = base64.standard_b64encode(buf).decode("utf-8")

        with state_lock:
            state["latest_frame"] = frame_b64
            state["latest_detections"] = detections

        # Only call Claude if scene changed + cooldown passed + not already processing
        now = time.time()
        cooldown_ok = (now - state["last_ai_call"]) > AI_COOLDOWN_SECONDS

        if cooldown_ok and not state["is_processing"] and scene_changed(frame):
            state["is_processing"] = True
            state["last_ai_call"] = now

            def call_claude():
                try:
                    print("🤖 Calling Claude...")
                    result = ask_gemini(frame)
                    with state_lock:
                        state["latest_instructions"] = result
                    print(f"✅ Detected: {result.get('object', 'nothing')}")
                except Exception as e:
                    print(f"❌ Claude error: {e}")
                finally:
                    with state_lock:
                        state["is_processing"] = False

            threading.Thread(target=call_claude, daemon=True).start()

        time.sleep(0.033)  # ~30fps

    cap.release()


# ─────────────────────────────────────────────
#  WEBSOCKET — streams everything to browser
# ─────────────────────────────────────────────
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("🔌 Browser connected")

    try:
        while True:
            with state_lock:
                frame = state["latest_frame"]
                detections = state["latest_detections"]
                instructions = state["latest_instructions"]
                processing = state["is_processing"]

            if frame:
                await websocket.send_json({
                    "frame": frame,
                    "detections": detections,
                    "instructions": instructions,
                    "processing": processing,
                })

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
import asyncio

@app.on_event("startup")
async def startup():
    t = threading.Thread(target=camera_loop, daemon=True)
    t.start()


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)