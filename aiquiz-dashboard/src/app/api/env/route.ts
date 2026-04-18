import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

const ENV_PATH = path.join(process.cwd(), '../AIQUIZ-Godot/.env');

export async function GET() {
  try {
    if (!fs.existsSync(ENV_PATH)) {
      return NextResponse.json({ error: '.env not found at ' + ENV_PATH }, { status: 404 });
    }
    const data = fs.readFileSync(ENV_PATH, 'utf-8');
    const lines = data.split('\n');
    const config: Record<string, string> = {};
    
    for (const line of lines) {
      if (line.trim() && !line.startsWith('#')) {
        const [key, ...rest] = line.split('=');
        if (key && rest.length > 0) {
          let value = rest.join('=').trim();
          // Strip surrounding quotes
          if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
            value = value.slice(1, -1);
          }
          // Mask API keys for security
          if (key.includes('API_KEY') || key.includes('SECRET')) {
            value = value.length > 12 ? value.substring(0, 8) + '••••' + value.substring(value.length - 4) : '••••••••';
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
