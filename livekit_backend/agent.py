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
You are an AR assistant that sees through the user's camera and draws visual \
overlays to guide them through ANY physical task. You help with everything: \
car repairs, furniture assembly, electronics, cooking, plumbing, first aid, \
gardening, crafts, and anything else that requires hands-on guidance.

HOW TO USE OVERLAYS WHILE TALKING:
You are like a teacher who points at things while explaining. Whenever you \
mention a physical object, part, tool, or location in conversation, you MUST \
simultaneously draw an overlay on it so the user can see exactly what you mean.

Examples of what you should do:
- You say "see that bolt right there?" → call draw_circle on the bolt
- You say "grab the side panel" → call draw_region around the panel
- You say "you'll need a wrench for this" → call draw_icon "wrench.fill" \
next to the fastener
- You say "turn it clockwise" → call draw_arrow showing the rotation
- You say "that's your oil filter" → call draw_label "Oil Filter" on it
- You say "careful, that's hot" → call draw_icon \
"exclamationmark.triangle.fill" with color "#FF3B30" on the hot part
- You say "nice, that looks right" → call draw_icon "checkmark.circle.fill" \
with color "#34C759" on the correct placement

NEVER just talk without drawing. If you reference anything physical, DRAW ON \
IT. The user's screen is your whiteboard — use it constantly. Think of yourself \
as someone pointing at things in the real world while explaining.

When you move to a new topic or step, call clear_overlays first to wipe the \
screen, then draw fresh overlays for what you're now discussing.

DRAWING TOOLS:
- draw_icon: Place an icon at (x, y). Use for tools, hands, warnings, objects.
- draw_circle: Pulsing circle to mark an exact spot. Screws, buttons, ports, \
wounds, pour-points, connection points.
- draw_region: Highlight a rectangular area. Outline parts, components, \
ingredients, panels, zones.
- draw_arrow: Arrow from A to B. Direction of movement, rotation, insertion, \
wire routing, flow direction.
- draw_label: Floating text. Name parts, annotate, show measurements or specs.
- play_animation: Trigger a rich animation. Supported: "cpr_compressions".
- clear_overlays: Wipe the screen. Call before drawing for a new topic/step.

COORDINATES: 0.0 to 1.0, (0,0) = top-left, (1,1) = bottom-right. Estimate \
carefully by examining the video feed.

SF SYMBOL ICON LIBRARY — pick the best icon for the situation:

Tools & Hardware: "wrench.fill", "hammer.fill", "screwdriver", "scissors", \
"paintbrush.fill", "eyedropper.full", "ruler", "level", "gear"

Automotive & Engine: "car.fill", "car.side", "engine.combustion", \
"oilcan.fill", "bolt.fill", "gauge", "speedometer", "battery.100", \
"fanblades.fill", "gear", "fuelpump.fill", "key.fill"

Electronics & Wiring: "bolt.fill", "bolt.horizontal.fill", "cpu.fill", \
"cable.connector", "powerplug.fill", "lightbulb.fill", "battery.25", \
"antenna.radiowaves.left.and.right", "memorychip.fill", "desktopcomputer"

Plumbing & Water: "drop.fill", "drop.triangle.fill", "wrench.fill", \
"spigot.fill"

Cooking & Kitchen: "flame.fill", "timer", "thermometer", "fork.knife", \
"cup.and.saucer.fill", "oven.fill", "refrigerator.fill", "drop.fill"

First Aid & Medical: "cross.circle.fill", "bandage.fill", "heart.fill", \
"staroflife.fill", "pills.fill", "syringe.fill", "stethoscope", \
"lungs.fill", "waveform.path.ecg"

Furniture & Assembly: "wrench.fill", "hammer.fill", "screwdriver", \
"ruler", "square.grid.2x2.fill", "cube.fill", "shippingbox.fill"

Gardening & Outdoor: "leaf.fill", "tree.fill", "sun.max.fill", \
"drop.fill", "scissors"

Safety & Warnings: "exclamationmark.triangle.fill", "xmark.octagon.fill", \
"nosign", "flame.fill", "bolt.fill", "lock.fill", "shield.fill"

Navigation & Arrows: "location.fill", "arrow.up", "arrow.down", \
"arrow.left", "arrow.right", "arrow.turn.right.down", "arrow.uturn.left", \
"mappin.circle.fill", "arrowtriangle.down.fill", "arrow.clockwise", \
"arrow.counterclockwise"

Measurement: "ruler", "gauge", "speedometer", "thermometer", "timer", \
"clock.fill", "stopwatch.fill"

Status & Confirmation: "checkmark.circle.fill", "xmark.circle.fill", \
"questionmark.circle.fill", "info.circle.fill", "star.fill", \
"checkmark.seal.fill", "hand.thumbsup.fill"

Hands & Body: "hand.raised.fill", "hand.point.right.fill", \
"hand.point.left.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill", \
"hand.draw.fill", "eye.fill", "ear"

General Objects: "lightbulb.fill", "camera.fill", "briefcase.fill", \
"bag.fill", "cart.fill", "house.fill", "key.fill", "lock.fill", \
"lock.open.fill", "pin.fill", "mappin", "tag.fill", "bell.fill"

OVERLAY PATTERNS BY TASK:

Furniture Assembly:
- draw_region to outline the part to grab
- draw_circle to mark screw holes or connection points
- draw_arrow for insertion direction or alignment
- draw_icon "wrench.fill" or "screwdriver" where a tool is needed
- draw_label to name each part ("side panel", "cam lock")

Car / Engine Repair:
- draw_region to outline the component (alternator, filter, belt)
- draw_icon "oilcan.fill" for fluid-related, "bolt.fill" for fasteners, \
"gear" for mechanical parts, "engine.combustion" for engine
- draw_arrow for bolt rotation direction (clockwise/counter-clockwise)
- draw_label to name parts and specs ("10mm bolt", "oil filter")
- draw_icon "exclamationmark.triangle.fill" for hot/dangerous parts

Electronics & Wiring:
- draw_circle to mark pins, ports, solder points
- draw_arrow for wire routing direction
- draw_icon "bolt.fill" for power connections, "cpu.fill" for processors
- draw_label for pin names, voltage, polarity ("GPIO 17", "+5V", "GND")

Cooking:
- draw_icon "flame.fill" near the stove + draw_label for heat level
- draw_region to outline ingredients to prep
- draw_circle where to pour, place, or stir
- draw_arrow for stirring direction or pouring path
- draw_icon "timer" when timing matters, "thermometer" for temperature

First Aid & CPR:
- draw_circle on the wound or chest center
- draw_icon "hand.raised.fill" for hand placement
- draw_icon "bandage.fill" for bandaging, "cross.circle.fill" for medical
- play_animation "cpr_compressions" for CPR rhythm demo
- draw_icon "exclamationmark.triangle.fill" for danger/urgency

Plumbing:
- draw_region to outline the pipe or fixture
- draw_icon "wrench.fill" for where to tighten
- draw_arrow for water flow direction
- draw_icon "drop.fill" to mark leak locations

Gardening:
- draw_region to outline planting areas
- draw_circle for where to dig or plant
- draw_icon "leaf.fill" for plant care, "drop.fill" for watering
- draw_arrow for pruning direction

CONVERSATIONAL OVERLAY RULES:
1. BEFORE or AS you say something about a physical object, call a draw tool.
2. Every noun you mention that exists in the camera should have an overlay.
3. If you're describing a sequence ("first this, then that"), draw on "this" \
first, then clear_overlays and draw on "that".
4. If a user asks "what's that?" — immediately draw_region around it and \
draw_label to name it.
5. If a user says "show me" — draw overlays on everything relevant you can see.
6. If you're warning about something dangerous, draw_icon with \
"exclamationmark.triangle.fill" in red on it.
7. If the user did something correctly, draw_icon "checkmark.circle.fill" \
in green as positive feedback.
8. Speak in short sentences. Your voice is heard aloud — be concise and clear.
9. Wait for user confirmation before moving to the next step.

COLOR GUIDE: Use "#00FFFF" (cyan) as default. Use "#FF3B30" (red) for \
danger/warnings/critical spots. Use "#34C759" (green) for success/correct. \
Use "#FF9500" (orange) for caution. Use "#FFFFFF" (white) for neutral.\
"""


async def _publish_overlay(overlays: list[dict], instruction: str = ""):
    """Publish overlay commands to the iOS app via data channel."""
    payload = json.dumps({
        "overlays": overlays,
        "instruction": instruction,
    })
    room = get_job_context().room
    await room.local_participant.publish_data(
        payload=payload.encode("utf-8"),
        topic="ar_overlay",
        reliable=True,
    )


class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=SYSTEM_INSTRUCTIONS)

    @function_tool()
    async def draw_icon(
        self,
        context: RunContext,
        asset: str,
        x: float,
        y: float,
        label: str = "",
        color: str = "#00FFFF",
        scale: float = 2.0,
        pulse: bool = True,
    ) -> str:
        """Draw an SF Symbol icon on the user's screen at position (x, y).

        Use this to show WHERE to place hands, tools, or objects. Call this
        every time you reference a location.

        Args:
            asset: SF Symbol name. Pick from these by domain:
                Tools: "wrench.fill", "hammer.fill", "screwdriver", "scissors",
                    "paintbrush.fill", "ruler", "level", "gear".
                Automotive: "car.fill", "engine.combustion", "oilcan.fill",
                    "bolt.fill", "gauge", "speedometer", "fuelpump.fill",
                    "fanblades.fill", "battery.100", "key.fill".
                Electronics: "cpu.fill", "bolt.horizontal.fill",
                    "cable.connector", "powerplug.fill", "lightbulb.fill",
                    "memorychip.fill", "antenna.radiowaves.left.and.right".
                Cooking: "flame.fill", "timer", "thermometer", "fork.knife",
                    "cup.and.saucer.fill", "oven.fill", "drop.fill".
                Medical: "cross.circle.fill", "bandage.fill", "heart.fill",
                    "staroflife.fill", "pills.fill", "syringe.fill",
                    "stethoscope", "waveform.path.ecg", "lungs.fill".
                Safety: "exclamationmark.triangle.fill", "xmark.octagon.fill",
                    "nosign", "shield.fill", "lock.fill", "flame.fill".
                Hands: "hand.raised.fill", "hand.point.right.fill",
                    "hand.point.left.fill", "hand.thumbsup.fill",
                    "hand.draw.fill", "eye.fill".
                Navigation: "location.fill", "arrow.up", "arrow.down",
                    "arrow.turn.right.down", "mappin.circle.fill".
                Status: "checkmark.circle.fill", "xmark.circle.fill",
                    "questionmark.circle.fill", "info.circle.fill".
                General: "lightbulb.fill", "tag.fill", "pin.fill",
                    "bell.fill", "house.fill", "briefcase.fill", "star.fill".
            x: Horizontal position, 0.0 (left) to 1.0 (right).
            y: Vertical position, 0.0 (top) to 1.0 (bottom).
            label: Optional text shown below the icon.
            color: Hex color, default cyan "#00FFFF".
            scale: Size multiplier, default 2.0.
            pulse: Whether the icon pulses to attract attention, default true.
        """
        overlay = {
            "type": "icon",
            "asset": asset,
            "x": round(x, 4),
            "y": round(y, 4),
            "label": label,
            "color": color,
            "scale": scale,
            "pulse": pulse,
        }
        await _publish_overlay([overlay], label)
        logger.info(f"draw_icon: {asset} at ({x:.2f},{y:.2f}) label={label}")
        return f"Icon '{asset}' drawn at ({x:.2f},{y:.2f})."

    @function_tool()
    async def draw_circle(
        self,
        context: RunContext,
        x: float,
        y: float,
        label: str = "",
        color: str = "#FF3B30",
        radius: float = 0.05,
        pulse: bool = True,
    ) -> str:
        """Draw a pulsing circle marker on the user's screen to mark an exact spot.

        Use this for "press here", "this screw", "this port", "pour here",
        "insert here", "this button", "solder point" type guidance.

        Args:
            x: Horizontal center, 0.0 (left) to 1.0 (right).
            y: Vertical center, 0.0 (top) to 1.0 (bottom).
            label: Optional text shown below the circle.
            color: Hex color, default red "#FF3B30".
            radius: Circle radius in normalized units, default 0.05.
            pulse: Whether the circle pulses, default true.
        """
        overlay = {
            "type": "circle",
            "x": round(x, 4),
            "y": round(y, 4),
            "label": label,
            "color": color,
            "radius": radius,
            "pulse": pulse,
        }
        await _publish_overlay([overlay], label)
        logger.info(f"draw_circle at ({x:.2f},{y:.2f}) label={label}")
        return f"Circle drawn at ({x:.2f},{y:.2f})."

    @function_tool()
    async def draw_region(
        self,
        context: RunContext,
        x_min: float,
        y_min: float,
        x_max: float,
        y_max: float,
        label: str = "",
        color: str = "#00FFFF",
    ) -> str:
        """Highlight a rectangular area on the user's screen.

        Use to outline objects, parts, components, panels, ingredients, or
        any area the user should focus on.

        Args:
            x_min: Left edge, 0.0 to 1.0.
            y_min: Top edge, 0.0 to 1.0.
            x_max: Right edge, 0.0 to 1.0.
            y_max: Bottom edge, 0.0 to 1.0.
            label: Optional text label shown above the region.
            color: Hex color, default cyan "#00FFFF".
        """
        overlay = {
            "type": "region",
            "x_min": round(x_min, 4),
            "y_min": round(y_min, 4),
            "x_max": round(x_max, 4),
            "y_max": round(y_max, 4),
            "label": label,
            "color": color,
        }
        await _publish_overlay([overlay], label)
        logger.info(f"draw_region [{x_min:.2f},{y_min:.2f}]-[{x_max:.2f},{y_max:.2f}] label={label}")
        return f"Region drawn: [{x_min:.2f},{y_min:.2f}]-[{x_max:.2f},{y_max:.2f}]."

    @function_tool()
    async def draw_arrow(
        self,
        context: RunContext,
        from_x: float,
        from_y: float,
        to_x: float,
        to_y: float,
        color: str = "#FFFFFF",
    ) -> str:
        """Draw a directional arrow from one point to another.

        Use to show movement direction, rotation, insertion path, wire routing,
        flow direction, where to push/pull, or which way to turn.

        Args:
            from_x: Start horizontal position, 0.0 to 1.0.
            from_y: Start vertical position, 0.0 to 1.0.
            to_x: End horizontal position, 0.0 to 1.0.
            to_y: End vertical position, 0.0 to 1.0.
            color: Hex color, default white "#FFFFFF".
        """
        overlay = {
            "type": "arrow",
            "from_x": round(from_x, 4),
            "from_y": round(from_y, 4),
            "to_x": round(to_x, 4),
            "to_y": round(to_y, 4),
            "color": color,
        }
        await _publish_overlay([overlay])
        logger.info(f"draw_arrow ({from_x:.2f},{from_y:.2f})->({to_x:.2f},{to_y:.2f})")
        return f"Arrow drawn from ({from_x:.2f},{from_y:.2f}) to ({to_x:.2f},{to_y:.2f})."

    @function_tool()
    async def draw_label(
        self,
        context: RunContext,
        text: str,
        x: float,
        y: float,
        color: str = "#FFFFFF",
    ) -> str:
        """Place floating text on the user's screen at a position.

        Use for annotations, part names, measurements, specs, pin labels,
        temperatures, or any text callout.

        Args:
            text: The text to display.
            x: Horizontal position, 0.0 to 1.0.
            y: Vertical position, 0.0 to 1.0.
            color: Hex color, default white "#FFFFFF".
        """
        overlay = {
            "type": "label",
            "x": round(x, 4),
            "y": round(y, 4),
            "label": text,
            "color": color,
        }
        await _publish_overlay([overlay], text)
        logger.info(f"draw_label '{text}' at ({x:.2f},{y:.2f})")
        return f"Label '{text}' placed at ({x:.2f},{y:.2f})."

    @function_tool()
    async def play_animation(
        self,
        context: RunContext,
        name: str,
        instruction: str,
    ) -> str:
        """Play a rich animation overlay on the user's screen.

        Args:
            name: Animation identifier. Currently: "cpr_compressions".
            instruction: Text shown alongside the animation.
        """
        payload = json.dumps({
            "animation": name,
            "instruction": instruction,
            "x": 0.5,
            "y": 0.5,
        })

        room = get_job_context().room
        await room.local_participant.publish_data(
            payload=payload.encode("utf-8"),
            topic="ar_animation",
            reliable=True,
        )

        logger.info(f"play_animation: {name}")
        return f"Animation '{name}' is now playing."

    @function_tool()
    async def clear_overlays(
        self,
        context: RunContext,
    ) -> str:
        """Remove all overlays and animations from the user's screen.

        Call this before drawing new overlays for a different step.
        """
        room = get_job_context().room
        await room.local_participant.publish_data(
            payload=b"{}",
            topic="ar_clear",
            reliable=True,
        )

        logger.info("clear_overlays")
        return "All overlays cleared."


server = AgentServer()


def prewarm(proc: JobProcess):
    proc.userdata["vad"] = silero.VAD.load(
        activation_threshold=0.6,
        min_silence_duration=0.3,
    )


server.setup_fnc = prewarm


@server.rtc_session(agent_name="ar-assistant")
async def entrypoint(ctx: JobContext):
    session = AgentSession(
        llm=google.beta.realtime.RealtimeModel(
            model="gemini-2.5-flash-native-audio-preview-12-2025",
            voice="Puck",
            temperature=0.5,
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
        instructions="Greet the user warmly. Tell them you can see what they "
        "see and can help with any hands-on task — car repair, furniture "
        "assembly, cooking, electronics, first aid, plumbing, or anything "
        "else. Ask what they need help with today. If you can already see "
        "something in the camera, call draw_region or draw_circle to "
        "highlight it as a quick demo of your visual guidance ability."
    )


if __name__ == "__main__":
    cli.run_app(server)
