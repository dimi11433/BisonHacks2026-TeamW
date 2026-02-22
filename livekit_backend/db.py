import os
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient

env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

logger = logging.getLogger("wvision-db")

MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
DB_NAME = "wvision"

_client: AsyncIOMotorClient | None = None


def get_client() -> AsyncIOMotorClient:
    global _client
    if _client is None:
        _client = AsyncIOMotorClient(MONGODB_URI)
    return _client


def get_db():
    return get_client()[DB_NAME]


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

def sessions_col():
    return get_db()["sessions"]


def conversations_col():
    return get_db()["conversations"]


def preferences_col():
    return get_db()["user_preferences"]


# ---------------------------------------------------------------------------
# Session helpers
# ---------------------------------------------------------------------------

async def create_session(
    room_name: str,
    participant_identity: str,
    voice_provider: str = "gemini",
    voice_id: str = "Puck",
    metadata: dict[str, Any] | None = None,
) -> str:
    doc = {
        "room_name": room_name,
        "participant_identity": participant_identity,
        "voice_provider": voice_provider,
        "voice_id": voice_id,
        "started_at": datetime.now(timezone.utc),
        "ended_at": None,
        "metadata": metadata or {},
    }
    result = await sessions_col().insert_one(doc)
    logger.info("Session created: %s (room=%s)", result.inserted_id, room_name)
    return str(result.inserted_id)


async def end_session(session_id: str):
    from bson import ObjectId

    await sessions_col().update_one(
        {"_id": ObjectId(session_id)},
        {"$set": {"ended_at": datetime.now(timezone.utc)}},
    )
    logger.info("Session ended: %s", session_id)


async def list_sessions(limit: int = 50) -> list[dict]:
    cursor = sessions_col().find().sort("started_at", -1).limit(limit)
    results = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        results.append(doc)
    return results


async def get_session(session_id: str) -> dict | None:
    from bson import ObjectId

    doc = await sessions_col().find_one({"_id": ObjectId(session_id)})
    if doc:
        doc["_id"] = str(doc["_id"])
    return doc


# ---------------------------------------------------------------------------
# Conversation helpers
# ---------------------------------------------------------------------------

async def log_message(
    session_id: str,
    role: str,
    content: str,
    metadata: dict[str, Any] | None = None,
):
    doc = {
        "session_id": session_id,
        "role": role,
        "content": content,
        "timestamp": datetime.now(timezone.utc),
        "metadata": metadata or {},
    }
    await conversations_col().insert_one(doc)


async def get_conversation(session_id: str) -> list[dict]:
    cursor = conversations_col().find(
        {"session_id": session_id}
    ).sort("timestamp", 1)
    results = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        results.append(doc)
    return results


# ---------------------------------------------------------------------------
# User preference helpers
# ---------------------------------------------------------------------------

async def get_user_preferences(user_id: str) -> dict:
    doc = await preferences_col().find_one({"user_id": user_id})
    if doc:
        doc["_id"] = str(doc["_id"])
        return doc
    return {
        "user_id": user_id,
        "voice_provider": "gemini",
        "voice_id": "Puck",
    }


async def update_user_preferences(
    user_id: str,
    voice_provider: str | None = None,
    voice_id: str | None = None,
) -> dict:
    update_fields: dict[str, Any] = {}
    if voice_provider is not None:
        update_fields["voice_provider"] = voice_provider
    if voice_id is not None:
        update_fields["voice_id"] = voice_id

    if not update_fields:
        return await get_user_preferences(user_id)

    await preferences_col().update_one(
        {"user_id": user_id},
        {"$set": update_fields, "$setOnInsert": {"user_id": user_id}},
        upsert=True,
    )
    return await get_user_preferences(user_id)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

async def close():
    global _client
    if _client is not None:
        _client.close()
        _client = None
