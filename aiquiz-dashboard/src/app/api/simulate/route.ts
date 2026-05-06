import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  try {
    const { systemInstruction, prompt } = await req.json();

    const proxyUrl = process.env.PROXY_URL;
    const appSecret = process.env.APP_SECRET;
    const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;

    if (!proxyUrl && !apiKey) {
      return NextResponse.json({ error: "APIキーまたはプロキシURLが設定されていません。" }, { status: 500 });
    }

    const payload = {
      contents: [{ parts: [{ text: prompt }] }],
      systemInstruction: systemInstruction ? { parts: [{ text: systemInstruction }] } : undefined,
      generationConfig: {
        temperature: 0.7,
        responseMimeType: "application/json"
      }
    };

    let fetchUrl = "";
    const fetchHeaders: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (proxyUrl) {
      fetchUrl = `${proxyUrl.replace(/\/$/, '')}/gemini?model=gemini-2.5-flash`;
      if (appSecret) {
        fetchHeaders['x-app-secret'] = appSecret;
      }
    } else {
      fetchUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    }

    const response = await fetch(fetchUrl, {
      method: 'POST',
      headers: fetchHeaders,
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const errorData = await response.text();
      return NextResponse.json({ error: "生成エラー", details: errorData }, { status: response.status });
    }

    const data = await response.json();
    const textResp = data.candidates?.[0]?.content?.parts?.[0]?.text || "[]";
    
    try {
      const parsed = JSON.parse(textResp);
      return NextResponse.json({ result: parsed, raw: textResp });
    } catch {
      return NextResponse.json({ error: "Failed to parse JSON", raw: textResp }, { status: 500 });
    }
  } catch (err: unknown) {
    if (err instanceof Error) {
      return NextResponse.json({ error: err.message }, { status: 500 });
    }
    return NextResponse.json({ error: "Unknown error occurred" }, { status: 500 });
  }
}
