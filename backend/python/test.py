"""
mic + camera frames → Gemini Live native audio → speaker
"""
import asyncio, base64, json, threading, time
import cv2, uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from google import genai
from google.genai import types

GEMINI_API_KEY = "AIzaSyDK6jsEOZ7fAFWC5qkUuETeKlZj7F9EqqA"
MODEL = "gemini-2.5-flash-native-audio-preview-12-2025"
SYSTEM = "You are an AR assistant in smart glasses. The user will talk to you and you can see their camera feed. Describe what you see and answer their questions. Be concise since you're speaking aloud."

client = genai.Client(api_key=GEMINI_API_KEY)
mic_q = speaker_q = None
latest_frame = {"b64": None}
frame_lock = threading.Lock()
connected = {"v": False}


def camera_thread():
    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    while True:
        ret, frame = cap.read()
        if not ret: time.sleep(0.05); continue
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        with frame_lock:
            latest_frame["b64"] = base64.b64encode(buf).decode()
        time.sleep(0.1)


async def gemini_loop():
    global mic_q, speaker_q
    mic_q     = asyncio.Queue(maxsize=50)
    speaker_q = asyncio.Queue(maxsize=100)

    config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=SYSTEM,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Aoede")
            )
        ),
    )

    while True:
        try:
            async with client.aio.live.connect(model=MODEL, config=config) as session:
                connected["v"] = True
                print("✅ Gemini Live connected")

                async def send_inputs():
                    last_frame_time = 0
                    while True:
                        now = time.time()

                        # Send all available mic chunks immediately
                        while not mic_q.empty():
                            try:
                                chunk = mic_q.get_nowait()
                                await session.send_realtime_input(
                                    audio=types.Blob(data=chunk, mime_type="audio/pcm;rate=16000")
                                )
                            except asyncio.QueueEmpty:
                                break

                        # Send camera frame every 1 second
                        if now - last_frame_time >= 1.0:
                            with frame_lock:
                                fb64 = latest_frame["b64"]
                            if fb64:
                                await session.send_realtime_input(
                                    media=types.Blob(data=base64.b64decode(fb64), mime_type="image/jpeg")
                                )
                                last_frame_time = now

                        await asyncio.sleep(0.02)
                        
                async def recv_outputs():
                    async for response in session.receive():
                        try:
                            sc = response.server_content
                            if sc:
                                print(f"📩 server_content: turn_complete={sc.turn_complete}, has_audio={sc.model_turn is not None}")
                                if sc.model_turn:
                                    for part in sc.model_turn.parts:
                                        if hasattr(part, "inline_data") and part.inline_data:
                                            print(f"🔊 audio chunk: {len(part.inline_data.data)} bytes")
                                            b64 = base64.b64encode(part.inline_data.data).decode()
                                            if not speaker_q.full():
                                                await speaker_q.put(b64)
                        except Exception as e:
                            print(f"recv err: {e}")

                # async def recv_outputs():
                #     async for response in session.receive():
                #         try:
                #             sc = response.server_content
                #             if sc and sc.model_turn:
                #                 for part in sc.model_turn.parts:
                #                     if hasattr(part, "inline_data") and part.inline_data:
                #                         b64 = base64.b64encode(part.inline_data.data).decode()
                #                         if not speaker_q.full():
                #                             await speaker_q.put(b64)
                #         except Exception as e:
                #             print(f"recv err: {e}")

                await asyncio.gather(send_inputs(), recv_outputs())

        except Exception as e:
            connected["v"] = False
            print(f"❌ {e}\n🔄 Reconnecting in 3s...")
            await asyncio.sleep(3)


@asynccontextmanager
async def lifespan(app: FastAPI):
    threading.Thread(target=camera_thread, daemon=True).start()
    asyncio.create_task(gemini_loop())
    print("🚀 http://localhost:8000")
    yield

app = FastAPI(lifespan=lifespan)

@app.websocket("/ws")
async def ws(websocket: WebSocket):
    await websocket.accept()

    async def push():
        while True:
            try:
                with frame_lock:
                    fb64 = latest_frame["b64"]
                payload = {"connected": connected["v"], "audio": None, "frame": fb64}
                if speaker_q and not speaker_q.empty():
                    try: payload["audio"] = speaker_q.get_nowait()
                    except: pass
                await websocket.send_json(payload)
            except WebSocketDisconnect:
                raise
            except Exception:
                raise WebSocketDisconnect()
            await asyncio.sleep(0.033)

    async def pull():
        while True:
            try:
                msg = await websocket.receive()
                if "text" in msg:
                    d = json.loads(msg["text"])
                    if d.get("type") == "mic" and mic_q and not mic_q.full():
                        await mic_q.put(base64.b64decode(d["data"]))
            except WebSocketDisconnect: raise
            except: await asyncio.sleep(0.01)

    try:
        await asyncio.gather(push(), pull())
    except WebSocketDisconnect:
        pass

@app.get("/")
async def root():
    return HTMLResponse(open("index.html").read())

if __name__ == "__main__":
    uvicorn.run("test:app", host="0.0.0.0", port=8000, reload=False)