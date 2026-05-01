import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

// Absolute path to the Godot offline bank file relative to the dashboard directory
const BANK_PATH = path.join(process.cwd(), '../AIQUIZ-Godot/offline_bank.json');

export async function GET() {
  try {
    if (!fs.existsSync(BANK_PATH)) {
      return NextResponse.json({ error: 'offline_bank.json not found' }, { status: 404 });
    }
    const data = fs.readFileSync(BANK_PATH, 'utf-8');
    const json = JSON.parse(data);
    return NextResponse.json(json);
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const newData = await req.json();
    fs.writeFileSync(BANK_PATH, JSON.stringify(newData, null, 2), 'utf-8');
    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
