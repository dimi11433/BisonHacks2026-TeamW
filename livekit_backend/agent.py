import json
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from livekit.agents import (
    Agent,
    AgentSession,
    AgentServer,
    JobContext,
    JobProcess,
    RunContext,
    cli,
    function_tool,
    get_job_context,
    room_io,
)
from livekit.plugins import google, silero

env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

if os.getenv("GEMINI_API_KEY") and not os.getenv("GOOGLE_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = os.environ["GEMINI_API_KEY"]

logger = logging.getLogger("ar-assistant")
logger.setLevel(logging.INFO)

SYSTEM_INSTRUCTIONS = """\
You are an AR assistant embedded in smart glasses (Meta Ray-Bans). You can see \
exactly what the user sees through their live camera feed.

Your job is to help users with hands-on physical tasks — assembling IKEA \
furniture, wiring up an NVIDIA Jetson Nano, cooking recipes, repairing \
electronics, or any task where spatial guidance is valuable.

IMPORTANT RULES:
- When you identify a physical object or part the user should interact with, \
ALWAYS call the draw_bounding_box tool with the object label and its \
normalized coordinates in the video frame (values between 0.0 and 1.0).
- You may call draw_bounding_box multiple times in one turn to highlight \
several parts simultaneously.
- Be concise and conversational — your responses are spoken aloud.
- Give step-by-step guidance. After each step, wait for the user to confirm \
before moving on.
- If you cannot clearly see an object, ask the user to adjust the camera angle.\
"""


class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=SYSTEM_INSTRUCTIONS)
        
    @function_tool()
    async def show_ar_step(
        self,
        context: RunContext,
        step: int,
        animation: str,
        instruction: str,
    ) -> str:
        """Show an AR animation overlay guiding the user through the current tourniquet step.

        Args:
            step: The current step number (1-5).
            animation: The animation name to display. One of: position_tourniquet, pull_strap, twist_windlass, lock_windlass, note_time.
            instruction: The instruction text to show on screen.
        """
        payload = json.dumps({
            "type": "ar_step",
            "step": step,
            "animation": animation,
            "instruction": instruction,
        })

        room = get_job_context().room
        await room.local_participant.publish_data(
            payload=payload.encode("utf-8"),
            topic="ar_step",
            reliable=True,
        )

        logger.info(f"Published AR step {step}: {animation}")
        return f"AR step {step} shown to user."

    @function_tool()
    async def draw_bounding_box(
        self,
        context: RunContext,
        label: str,
        y_min: float,
        x_min: float,
        y_max: float,
        x_max: float,
    ) -> str:
        """Draw an AR bounding box overlay on the user's video feed to highlight
        a physical object or part.

        Args:
            label: Human-readable name of the object or part (e.g. "cam lock screw").
            y_min: Top edge of the bounding box, normalized 0.0-1.0 from top of frame.
            x_min: Left edge of the bounding box, normalized 0.0-1.0 from left of frame.
            y_max: Bottom edge of the bounding box, normalized 0.0-1.0 from top of frame.
            x_max: Right edge of the bounding box, normalized 0.0-1.0 from left of frame.
        """
        payload = json.dumps({
            "type": "bounding_box",
            "label": label,
            "y_min": round(y_min, 4),
            "x_min": round(x_min, 4),
            "y_max": round(y_max, 4),
            "x_max": round(x_max, 4),
        })

        room = get_job_context().room
        await room.local_participant.publish_data(
            payload=payload.encode("utf-8"),
            topic="bounding_box",
            reliable=True,
        )

        logger.info(f"Published bounding box: {label} [{y_min:.2f},{x_min:.2f},{y_max:.2f},{x_max:.2f}]")
        return f"Bounding box for '{label}' sent to the user's display."


server = AgentServer()


def prewarm(proc: JobProcess):
    proc.userdata["vad"] = silero.VAD.load(
        activation_threshold=0.65,
        min_silence_duration=0.5,
    )


server.setup_fnc = prewarm


@server.rtc_session(agent_name="ar-assistant")
async def entrypoint(ctx: JobContext):
    session = AgentSession(
        llm=google.beta.realtime.RealtimeModel(
            model="gemini-2.5-flash-native-audio-preview-12-2025",
            voice="Puck",
            temperature=0.7,
            proactivity=True,
            enable_affective_dialog=True,
        ),
        vad=ctx.proc.userdata["vad"],
    )

    await session.start(
        room=ctx.room,
        agent=Assistant(),
        room_options=room_io.RoomOptions(
            video_input=True,
        ),
    )

    await ctx.connect()
    await session.generate_reply(
        instructions="Greet the user. Let them know you can see what they see and are ready to help with their task."
    )


if __name__ == "__main__":
    cli.run_app(server)
