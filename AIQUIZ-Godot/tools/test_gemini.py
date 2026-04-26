from google import genai
from google.genai import types
import sys

client = genai.Client(api_key="YOUR_API_KEY_HERE")
print("Client created", flush=True)
try:
    r = client.models.generate_content(
        model="gemini-3.1-pro-preview",
        contents='Return a JSON object with key "msg" and value "hello"',
        config=types.GenerateContentConfig(temperature=0.1, response_mime_type="application/json"),
    )
    print(f"Response: {r.text[:300]}", flush=True)
except Exception as e:
    print(f"Error: {type(e).__name__}: {e}", flush=True)
    sys.exit(1)
