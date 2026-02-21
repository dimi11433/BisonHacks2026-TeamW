# AR Vision — Setup & Run Guide

## 1. Install dependencies
```bash
pip install -r requirements.txt
```

## 2. Add your API key
Open `main.py` and replace:
```python
ANTHROPIC_API_KEY = "YOUR_API_KEY_HERE"
```
with your actual Anthropic API key from https://console.anthropic.com

## 3. Run the server
```bash
python main.py
```

## 4. Open in browser
Go to: http://localhost:8000

## 5. Use your phone as camera (optional)
Install ngrok: https://ngrok.com
```bash
ngrok http 8000
```
Then open the ngrok URL on your phone browser.

---

## How it works

```
Phone/Webcam
    ↓
YOLO (fast local detection — draws yellow boxes)
    ↓
Frame change detection (don't spam the API)
    ↓
Claude Vision API (identifies object + generates steps)
    ↓
SVG overlay (blue arrows + step labels on camera feed)
    ↓
Three.js (floating particles for visual flair)
```

## Controls
- Click steps in sidebar to jump to that step
- Arrow keys ← → to navigate steps
- NEXT / PREV buttons

## Tuning
- `FRAME_CHANGE_THRESHOLD = 25` — lower = more sensitive to change
- `AI_COOLDOWN_SECONDS = 3` — min time between Claude API calls
- `CAMERA_INDEX = 0` — change if wrong camera is used