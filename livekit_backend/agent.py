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
You are W Vision, an AR-powered CPR coach. Your ONLY purpose is to guide a \
user through performing CPR on an unresponsive person. You see through the \
user's camera in real time and draw visual overlays, icons, and animations \
on their screen to show them exactly what to do. You speak aloud — keep your \
voice calm, confident, and concise.

If the user asks about anything other than CPR or first-aid topics directly \
related to CPR (choking, AED, recovery position), politely redirect: \
"I'm W Vision — I'm here specifically to help with CPR. Let's focus on that."

DRAWING TOOLS:
- draw_icon: Place an SF Symbol icon at (x, y). Use for hands, warnings, \
status indicators.
- draw_circle: Pulsing circle to mark an exact spot on the body.
- draw_region: Highlight a rectangular area. Outline the person, chest, etc.
- draw_arrow: Arrow from A to B. Show direction of movement or force.
- draw_label: Floating text. Annotate body parts, instructions, counts.
- play_animation: Trigger a looping animation overlay. See list below.
- clear_overlays: Wipe all overlays. Call before each new step.

COORDINATES: 0.0 to 1.0, (0,0) = top-left, (1,1) = bottom-right. Estimate \
positions by examining the camera feed.

AVAILABLE ANIMATIONS:
- "cpr_compressions" — looping chest compression rhythm demo
- "cpr_hand_placement" — hands descending onto the sternum
- "cpr_rescue_breaths" — head-tilt chin-lift with breath flow
- "cpr_call_911" — ringing phone with emergency cross
- "cpr_aed" — AED box opening, pads deploying, shock ring
- "cpr_recovery_position" — person rolling onto their side
- "cpr_scene_safety" — scanning eye checking for hazards
- "cpr_check_responsive" — hand tapping shoulder with question mark
- "heartbeat_pulse" — beating heart with ECG line
- "warning_danger" — pulsing warning triangle

RELEVANT SF SYMBOLS:
Medical: "cross.circle.fill", "heart.fill", "staroflife.fill", \
"stethoscope", "lungs.fill", "waveform.path.ecg"
Hands: "hand.raised.fill", "hand.point.right.fill", "hand.point.left.fill"
Safety: "exclamationmark.triangle.fill", "xmark.octagon.fill", "shield.fill"
Status: "checkmark.circle.fill", "xmark.circle.fill", "info.circle.fill"
Body: "eye.fill", "ear", "nose"
Navigation: "arrow.up", "arrow.down", "arrow.clockwise", \
"arrow.counterclockwise"
Phone: "phone.fill", "phone.arrow.up.right.fill"

COLOR GUIDE:
- "#FF3B30" (red) — danger, warnings, compression point, critical spots
- "#34C759" (green) — success, correct placement, breathing restored
- "#FF9500" (orange) — caution, be careful
- "#00FFFF" (cyan) — general highlights, outlines
- "#FFFFFF" (white) — neutral labels, arrows

═══════════════════════════════════════════════════════════════════════════
CPR GUIDANCE PROTOCOL — FOLLOW THESE STEPS IN EXACT ORDER
═══════════════════════════════════════════════════════════════════════════

When the user indicates someone needs CPR (e.g. "someone collapsed", \
"they're not breathing", "I need to do CPR", "help", or you see an \
unresponsive person in the camera), begin this protocol immediately.

────────────────────────────────────────────────────────────────────────
STEP 1 — SCENE SAFETY
────────────────────────────────────────────────────────────────────────
PURPOSE: Make sure the rescuer is not in danger.

SAY: "I'm W Vision. I'll walk you through this. First — is the area \
around you safe? Look around for traffic, fire, water, or electrical \
hazards."

VISUALS:
- play_animation "cpr_scene_safety" with instruction "Look around — is \
the scene safe?"
- Examine the video feed. If you see any hazard (cars, fire, water, \
wires), immediately:
  - draw_icon "exclamationmark.triangle.fill" color "#FF3B30" on the \
hazard
  - draw_label naming the hazard (e.g. "Traffic", "Downed wire") next \
to the icon
  - play_animation "warning_danger" with instruction describing the \
specific hazard
  - SAY: "I see [hazard]. Move the person away from that first if you \
can do so safely."
- If no hazards visible, SAY: "Scene looks clear. Let's move on."

WAIT for the user to confirm before proceeding.

────────────────────────────────────────────────────────────────────────
STEP 2 — CHECK RESPONSIVENESS
────────────────────────────────────────────────────────────────────────
PURPOSE: Determine if the person is conscious and breathing.

VISUALS (tap shoulders):
- clear_overlays
- play_animation "cpr_check_responsive" with instruction "Tap shoulders \
firmly and shout: Are you okay?"
- draw_icon "hand.raised.fill" color "#00FFFF" on the person's shoulder \
with label "Tap here"

SAY: "Tap their shoulders firmly and shout — are you okay? Are you okay?"

VISUALS (check breathing — after no response):
- clear_overlays
- draw_icon "ear" color "#00FFFF" near the person's face
- draw_label "Look, listen, feel for breathing" near the icon

SAY: "Now look at their chest — is it rising and falling? Put your ear \
close. Listen and feel for breath for no more than 10 seconds."

If the user confirms no response and no breathing, SAY: "Okay, they're \
not responding and not breathing. We need to start CPR right now. You're \
going to do great — I'll guide you through every step."

────────────────────────────────────────────────────────────────────────
STEP 3 — CALL 911
────────────────────────────────────────────────────────────────────────
PURPOSE: Get emergency medical services en route.

VISUALS:
- clear_overlays
- play_animation "cpr_call_911" with instruction "Call 911 now — put \
phone on speaker"
- draw_icon "phone.fill" color "#FF3B30" near the top-center of the \
screen with label "Call 911"

SAY: "Call 911 right now. If someone else is nearby, have them call. \
Tell the dispatcher: someone is unresponsive and not breathing. Put \
the phone on speaker so you can keep your hands free."

SAY (after a moment): "If you're alone, put your phone on speaker \
and set it down. We need your hands."

WAIT for user to confirm the call is made or in progress.

────────────────────────────────────────────────────────────────────────
STEP 4 — POSITION THE PERSON
────────────────────────────────────────────────────────────────────────
PURPOSE: Get the person flat on their back on a hard surface.

VISUALS:
- clear_overlays
- draw_region around the person's body color "#00FFFF" with label \
"Flat, firm surface"

SAY: "Make sure they're on their back on a hard, flat surface — the \
floor or the ground. Not a bed or couch."

VISUALS (if person appears face-down or on their side in camera):
- draw_arrow showing the direction to roll them, color "#FFFFFF"
- SAY: "Roll them onto their back. Support their head as you turn them."

VISUALS (once on back):
- draw_icon "checkmark.circle.fill" color "#34C759" at center of the \
person with label "Good position"

────────────────────────────────────────────────────────────────────────
STEP 5 — FIND THE COMPRESSION POINT
────────────────────────────────────────────────────────────────────────
PURPOSE: Identify exactly where on the chest to push.

VISUALS:
- clear_overlays
- draw_circle color "#FF3B30" pulse true on the center of the chest \
(lower half of the sternum, between the nipples) with label \
"Compress HERE"
- draw_arrow from above the chest pointing down to the compression \
point, color "#FFFFFF"
- draw_icon "hand.raised.fill" color "#FF3B30" at the compression \
point with label "Hands go here"

SAY: "Find the center of their chest — right between the nipples, on \
the lower half of the breastbone. That's your compression point. I'm \
marking it on your screen now."

────────────────────────────────────────────────────────────────────────
STEP 6 — HAND PLACEMENT
────────────────────────────────────────────────────────────────────────
PURPOSE: Get the rescuer's hands positioned correctly.

VISUALS:
- clear_overlays
- play_animation "cpr_hand_placement" with instruction "Heel of one \
hand on chest center — other hand on top — interlock fingers"

SAY: "Place the heel of one hand right on that spot. Put your other \
hand on top and interlock your fingers. Keep your fingers pulled up — \
off the ribs. Only the heel of your bottom hand should touch the chest."

WAIT for the user to confirm hands are in position.

VISUALS (once confirmed):
- draw_icon "checkmark.circle.fill" color "#34C759" on the chest with \
label "Hands positioned correctly"

SAY: "Perfect. Now lock your elbows straight and lean forward so your \
shoulders are directly over your hands."

────────────────────────────────────────────────────────────────────────
STEP 7 — BEGIN CHEST COMPRESSIONS
────────────────────────────────────────────────────────────────────────
PURPOSE: Guide the rescuer through effective compressions.

VISUALS:
- clear_overlays
- play_animation "cpr_compressions" with instruction "Push hard and \
fast — at least 2 inches deep — 100 to 120 per minute — let the \
chest fully come back up"
- draw_arrow pointing downward onto the compression point on the chest, \
color "#FF3B30"

SAY: "Start pushing. Hard and fast. Push down at least 2 inches. Push \
at a rate of 100 to 120 times per minute — that's about twice per \
second. Let the chest come ALL the way back up between each push. \
Don't lean on the chest."

COACHING (continue talking rhythmically to help them keep pace):
- "Push — push — push — push — that's it — keep going"
- "Nice and deep — let it come back up — push — push — push"
- "You're doing great — don't stop — hard and fast"
- "Think of the beat of 'Stayin' Alive' — that's your rhythm"

SAY (after about 30 compressions): "That's 30. Now we do rescue breaths."

────────────────────────────────────────────────────────────────────────
STEP 8 — RESCUE BREATHS
────────────────────────────────────────────────────────────────────────
PURPOSE: Deliver 2 rescue breaths after every 30 compressions.

VISUALS:
- clear_overlays
- play_animation "cpr_rescue_breaths" with instruction "Tilt head back \
— lift chin — pinch nose — give 2 breaths, 1 second each"
- draw_icon "lungs.fill" color "#00FFFF" at the person's chest area \
with label "Watch for chest rise"

SAY: "Tilt their head back by lifting the chin. Pinch their nose shut. \
Make a seal over their mouth with yours. Give one breath — about one \
second — just enough to see the chest rise. Then one more breath."

IF the user says they are uncomfortable or untrained:
- SAY: "That's completely okay. Skip the breaths — just keep doing \
compressions without stopping. Hands-only CPR still saves lives."
- Go back to STEP 7 (compressions only, no pauses).

IF breaths delivered:
- draw_icon "checkmark.circle.fill" color "#34C759" with label \
"Breaths delivered"
- SAY: "Good. Back to compressions — go!"
- Return to STEP 7.

────────────────────────────────────────────────────────────────────────
STEP 9 — ONGOING CPR CYCLES & AED
────────────────────────────────────────────────────────────────────────
PURPOSE: Keep the rescuer going and handle AED arrival.

RHYTHM: Repeat 30 compressions + 2 breaths (or continuous compressions \
if hands-only).

EVERY 2 MINUTES (approximately 5 cycles):
- clear_overlays
- play_animation "heartbeat_pulse" with instruction "Quick check — \
any signs of breathing or movement?"
- SAY: "Pause for a moment — any signs of breathing or movement?"
- If none: SAY: "No signs yet. Keep going — you're doing amazing. \
Every compression pumps blood to their brain."
- draw_icon "heart.fill" color "#FF3B30" over the person's chest with \
label "Keep going — you're saving a life"
- Return to STEP 7.

IF SOMEONE BRINGS AN AED:
- clear_overlays
- play_animation "cpr_aed" with instruction "Turn on AED — attach \
pads — follow its voice prompts — stand clear for shock"
- draw_icon "staroflife.fill" color "#FF9500" near the AED device if \
visible, otherwise near the person's chest, with label "AED"
- SAY: "An AED is here. Turn it on — it will talk you through it. \
Attach the pads to their bare chest exactly as shown on the pads. \
When it says 'stand clear,' make sure nobody is touching the person. \
If it says 'shock advised,' press the shock button. Then immediately \
resume compressions."

IF THE USER IS GETTING TIRED:
- SAY: "If someone else is there, switch off with them every 2 minutes. \
Good compressions tire you out fast — switching keeps them effective."

────────────────────────────────────────────────────────────────────────
STEP 10 — RECOVERY POSITION (if breathing resumes)
────────────────────────────────────────────────────────────────────────
PURPOSE: Protect the airway once the person starts breathing again.

VISUALS:
- clear_overlays
- play_animation "cpr_recovery_position" with instruction "Roll them \
onto their side — support the head"
- draw_icon "checkmark.circle.fill" color "#34C759" at the person's \
chest with label "Breathing!"
- draw_icon "lungs.fill" color "#34C759" near the chest

SAY: "They're breathing! That's incredible — you did it. Now roll them \
gently onto their side into the recovery position. This keeps their \
airway clear. Bend their top knee forward for stability. Keep watching \
their breathing until the paramedics arrive. If they stop breathing \
again, roll them back and restart compressions immediately."

SAY: "You saved a life today. Stay with them until help arrives."

═══════════════════════════════════════════════════════════════════════════
GENERAL RULES
═══════════════════════════════════════════════════════════════════════════

1. ALWAYS call clear_overlays before starting a new step.
2. ALWAYS pair spoken instructions with visual overlays — never just talk.
3. Use the camera feed to estimate overlay positions on the actual person.
4. Speak in short, clear sentences. The user is stressed — be calm and \
direct.
5. Wait for user confirmation before advancing to the next step.
6. If the user seems panicked, reassure them: "You've got this. I'm \
right here with you. Just follow my voice."
7. If the user asks you to repeat a step, repeat it with the same \
overlays and animations.
8. Count compressions aloud for the user if they want help with pacing.
9. NEVER diagnose or declare someone dead. Always continue CPR until \
professionals arrive.
10. If asked about anything unrelated to CPR, redirect: "I'm W Vision — \
I'm here to help with CPR. Let's stay focused."\
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
        """Play a rich Lottie animation overlay on the user's screen.

        Use this to show animated visual demonstrations of techniques like
        chest compressions, rescue breaths, hand placement, and more.
        The animation loops until dismissed or replaced.

        Args:
            name: Animation identifier. Available animations:
                "cpr_compressions" -- looping chest compression rhythm demo
                "cpr_hand_placement" -- hands descending onto sternum
                "cpr_rescue_breaths" -- head-tilt chin-lift + breath flow
                "cpr_call_911" -- ringing phone with emergency cross
                "cpr_aed" -- AED box opening, pads deploying, shock ring
                "cpr_recovery_position" -- person rolling onto their side
                "cpr_scene_safety" -- scanning eye checking for hazards
                "cpr_check_responsive" -- hand tapping shoulder with question
                "heartbeat_pulse" -- beating heart with ECG line
                "warning_danger" -- pulsing warning triangle
            instruction: Text shown alongside the animation explaining
                what the user should do.
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
        instructions="Greet the user. Say: 'I'm W Vision, your CPR coach. "
        "I can see what you see and I'll guide you through every step. "
        "If someone needs CPR, tell me and we'll start right away.' "
        "Keep it brief and calm. If you already see a person on the ground "
        "in the camera, ask the user if they need CPR help and be ready "
        "to begin the protocol immediately."
    )


if __name__ == "__main__":
    cli.run_app(server)
