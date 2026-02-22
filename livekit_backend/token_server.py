import json
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from livekit.api import AccessToken, VideoGrants
from livekit.protocol.room import RoomConfiguration
from livekit.protocol.agent_dispatch import RoomAgentDispatch
from pydantic import BaseModel

import db

env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET")
LIVEKIT_URL = os.getenv("LIVEKIT_URL")

if not all([LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL]):
    raise RuntimeError("Missing LIVEKIT_API_KEY, LIVEKIT_API_SECRET, or LIVEKIT_URL in .env")


@asynccontextmanager
async def lifespan(application: FastAPI):
    yield
    await db.close()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class TokenRequest(BaseModel):
    room_name: str | None = None
    participant_identity: str | None = None
    participant_name: str | None = None
    voice_provider: str | None = None
    voice_id: str | None = None


class PreferenceUpdate(BaseModel):
    voice_provider: str | None = None
    voice_id: str | None = None


# ---------------------------------------------------------------------------
# Token endpoint
# ---------------------------------------------------------------------------

@app.post("/getToken", status_code=201)
async def get_token(body: TokenRequest):
    try:
        room_name = body.room_name or f"ar-room-{int(time.time())}"
        identity = body.participant_identity or f"ios-user-{int(time.time())}"
        name = body.participant_name or "iOS User"

        voice_provider = body.voice_provider
        voice_id = body.voice_id

        if voice_provider is None or voice_id is None:
            prefs = await db.get_user_preferences(identity)
            voice_provider = voice_provider or prefs.get("voice_provider", "gemini")
            voice_id = voice_id or prefs.get("voice_id", "Puck")

        room_metadata = json.dumps({
            "voice_provider": voice_provider,
            "voice_id": voice_id,
        })

        token = (
            AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
            .with_identity(identity)
            .with_name(name)
            .with_grants(
                VideoGrants(
                    room_join=True,
                    room=room_name,
                    can_publish=True,
                    can_subscribe=True,
                )
            )
            .with_room_config(
                RoomConfiguration(
                    agents=[
                        RoomAgentDispatch(agent_name="ar-assistant")
                    ],
                    metadata=room_metadata,
                )
            )
        )

        return {
            "server_url": LIVEKIT_URL,
            "participant_token": token.to_jwt(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Session endpoints
# ---------------------------------------------------------------------------

@app.get("/sessions")
async def list_sessions(limit: int = 50):
    return await db.list_sessions(limit=limit)


@app.get("/sessions/{session_id}")
async def get_session(session_id: str):
    session = await db.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    conversation = await db.get_conversation(session_id)
    return {**session, "conversation": conversation}


# ---------------------------------------------------------------------------
# Preference endpoints
# ---------------------------------------------------------------------------

@app.get("/preferences/{user_id}")
async def get_preferences(user_id: str):
    return await db.get_user_preferences(user_id)


@app.put("/preferences/{user_id}")
async def update_preferences(user_id: str, body: PreferenceUpdate):
    return await db.update_user_preferences(
        user_id=user_id,
        voice_provider=body.voice_provider,
        voice_id=body.voice_id,
    )


if __name__ == "__main__":
    uvicorn.run("token_server:app", host="0.0.0.0", port=3001, reload=True)
