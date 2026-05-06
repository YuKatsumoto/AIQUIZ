import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import path from 'path';
import util from 'util';

const execPromise = util.promisify(exec);

export async function POST(req: NextRequest) {
  try {
    const { subject, grade, count, difficulty } = await req.json();

    if (!subject || !grade || !count) {
      return NextResponse.json({ error: "Missing required parameters" }, { status: 400 });
    }

    const scriptPath = path.join(process.cwd(), '../AIQUIZ-Godot/tools/generate_quality_quiz.py');
    const proxyUrl = process.env.PROXY_URL || '';
    const appSecret = process.env.APP_SECRET || '';
    const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || '';

    // Python実行コマンドの組み立て。パスや引数を適切にエスケープ
    let cmd = `python "${scriptPath}" --subject "${subject}" --grade "${grade}" --count ${count}`;
    if (difficulty) {
      cmd += ` --difficulty "${difficulty}"`;
    }
    
    console.log(`Executing: ${cmd}`);

    const { stdout, stderr } = await execPromise(cmd, {
      env: {
        ...process.env,
        PROXY_URL: proxyUrl,
        APP_SECRET: appSecret,
        GEMINI_API_KEY: apiKey,
        PYTHONUTF8: '1' // Force UTF-8 for Python execution to avoid encoding issues
      }
    });

    // 標準出力の最後の行がJSON結果となる想定
    try {
      const lines = stdout.trim().split('\n');
      const resultJson = JSON.parse(lines[lines.length - 1]);
      return NextResponse.json(resultJson);
    } catch (parseError) {
      console.warn("Failed to parse python output as JSON:", stdout);
      return NextResponse.json({ 
        success: true, 
        message: "Script finished, but output was not JSON",
        stdout 
      });
    }

  } catch (error: any) {
    console.error("Generation execution error:", error);
    return NextResponse.json({ 
      error: error.message || "Failed to execute generation script", 
      stderr: error.stderr 
    }, { status: 500 });
  }
}
