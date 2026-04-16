import { NextResponse } from 'next/server';
import fs from 'fs';

const ENV_PATH = 'C:/AIQUIZ/AIQUIZ-Godot/.env';

export async function GET() {
  try {
    if (!fs.existsSync(ENV_PATH)) {
      return NextResponse.json({ error: '.env not found' }, { status: 404 });
    }
    const data = fs.readFileSync(ENV_PATH, 'utf-8');
    const lines = data.split('\n');
    const config: Record<string, string> = {};
    
    for (const line of lines) {
      if (line.trim() && !line.startsWith('#')) {
        const [key, ...rest] = line.split('=');
        if (key && rest.length > 0) {
          // Hide actual API keys
          let value = rest.join('=').trim();
          if (key.includes('API_KEY')) {
            value = value.substring(0, 8) + '...' + value.substring(value.length - 4);
          }
          config[key.trim()] = value;
        }
      }
    }
    return NextResponse.json(config);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
