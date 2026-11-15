"""Voices the demo clip's lines with openai/gpt-audio via OpenRouter.

python3 voice.py <voice> <out-dir>   (needs OPENROUTER_API_KEY in ~/.env)
Writes line1.wav … line4.wav (24 kHz mono 16-bit).
"""
import base64, json, os, sys, urllib.request, wave

LINES = [
    ("You're watching this on mute, aren't you?", "knowing and unbothered, like you've caught someone out and find it mildly amusing"),
    ("That's fine. I get it.", "dry and magnanimous, a shrug in the voice, short pause between the two sentences"),
    ("That's why I brought subtitles.", "matter-of-fact, quietly pleased with yourself, a slight lean on 'subtitles'"),
    ("Capisce?", "low, slow and final, one word, like closing a deal"),
]

def key():
    for line in open(os.path.expanduser("~/.env")):
        if line.startswith("OPENROUTER_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("no OPENROUTER_API_KEY in ~/.env")

def speak(text, delivery, voice, api_key):
    body = {
        "model": "openai/gpt-audio",
        "modalities": ["text", "audio"],
        "audio": {"voice": voice, "format": "pcm16"},
        "stream": True,
        "messages": [
            {"role": "system", "content":
                "You are a voice actor for a short cartoon about a speech-bubble character called Subby: a "
                "laid-back New York wiseguy type, with a thick, gravelly New York Italian-American accent, "
                "deadpan and street-smart, talking straight to the viewer. Don't imitate any real actor. "
                "Say exactly the line the user gives, word for word, and nothing else: no greeting, no "
                "commentary. Natural, warm, human comic timing; clear diction. Delivery: " + delivery},
            {"role": "user", "content": text},
        ],
    }
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + api_key,
                                          "Content-Type": "application/json"})
    pcm, said = bytearray(), []
    with urllib.request.urlopen(req, timeout=120) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data:") or line == "data: [DONE]":
                continue
            chunk = json.loads(line[5:])
            for choice in chunk.get("choices", []):
                audio = (choice.get("delta") or {}).get("audio") or {}
                if audio.get("data"):
                    pcm += base64.b64decode(audio["data"])
                if audio.get("transcript"):
                    said.append(audio["transcript"])
    return bytes(pcm), "".join(said)

def main():
    voice, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    api_key = key()
    for i, (text, delivery) in enumerate(LINES, 1):
        pcm, said = speak(text, delivery, voice, api_key)
        path = os.path.join(out, f"line{i}.wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(pcm)
        print(f"{path}: {len(pcm) / 48000:.2f} s, said: {said!r}")

main()
