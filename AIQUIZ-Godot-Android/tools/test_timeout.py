import sys
from google import genai

for t in [90.0, 90000.0, 90000]:
    try:
        client = genai.Client(api_key="YOUR_API_KEY_HERE", http_options={"timeout": t})
        r = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents="Say hi",
        )
        print(f"timeout {t} works")
    except Exception as e:
        print(f"timeout {t} failed: {e}")
