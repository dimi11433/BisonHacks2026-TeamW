import asyncio
import json
import re
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions
from livekit.plugins import google

SYSTEM_PROMPT = """You are an AR assistant guiding someone through applying a tourniquet in an emergency.

Watch the camera feed carefully to see which step the user is on. Speak the instruction out loud clearly and concisely.

After EVERY response you must also output a JSON tag on its own line in this exact format:
<step>{"step": 1, "animation": "position_tourniquet", "instruction": "Place tourniquet 2 inches above the wound"}</step>

The 5 steps and their animation names are:
1. {"step": 1, "animation": "position_tourniquet", "instruction": "Place tourniquet 2 inches above the wound"}
2. {"step": 2, "animation": "pull_strap", "instruction": "Pull the strap tight through the buckle"}
3. {"step": 3, "animation": "twist_windlass", "instruction": "Twist the windlass rod until bleeding stops"}
4. {"step": 4, "animation": "lock_windlass", "instruction": "Lock the windlass rod into the clip"}
5. {"step": 5, "animation": "note_time", "instruction": "Mark the time the tourniquet was applied"}

Look at the camera to determine which step the user is currently on and emit the correct JSON tag.
Only advance to the next step when you can see the previous one is complete.
"""

async def entrypoint(ctx: agents.JobContext):
    await ctx.connect()

    session = AgentSession(
        llm=google.beta.realtime.RealtimeModel(
            model="gemini-2.5-flash-native-audio-preview-12-2025",
            voice="Aoede",
            system_instruction=SYSTEM_PROMPT,
        )
    )

    # Hook into text responses to extract and publish step JSON
    @session.on("agent_message")
    def on_agent_message(message):
        text = message.content if hasattr(message, "content") else str(message)
        # Extract <step>{...}</step> tags
        match = re.search(r'<step>(\{.*?\})</step>', text)
        if match:
            try:
                step_data = json.loads(match.group(1))
                asyncio.ensure_future(publish_step(ctx, step_data))
                print(f"📡 Publishing step: {step_data}")
            except json.JSONDecodeError:
                print("⚠️ Could not parse step JSON")

    await session.start(
        room=ctx.room,
        agent=Agent(instructions=""),
        room_input_options=RoomInputOptions(video_enabled=True),
    )

async def publish_step(ctx: agents.JobContext, step_data: dict):
    try:
        await ctx.room.local_participant.publish_data(
            json.dumps(step_data).encode(),
            reliable=True
        )
    except Exception as e:
        print(f"⚠️ Failed to publish step: {e}")

if __name__ == "__main__":
    agents.cli.run_app(
        agents.WorkerOptions(entrypoint_fnc=entrypoint)
    )