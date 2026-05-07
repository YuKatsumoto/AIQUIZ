import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import path from 'path';
import util from 'util';

const execPromise = util.promisify(exec);

export async function POST(req: NextRequest) {
  try {
    const { subject, grade, originalText } = await req.json();

    if (!subject || !grade || !originalText) {
      return NextResponse.json({ error: "Missing required parameters" }, { status: 400 });
    }

    const scriptPath = path.join(process.cwd(), '../AIQUIZ-Godot/tools/refine_single_quiz.py');
    const proxyUrl = process.env.PROXY_URL || '';
    const appSecret = process.env.APP_SECRET || '';
    const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || '';

    // Pythonスクリプトへの引数をエスケープ
    // Windows環境ではエスケープに注意が必要です
    const escapedSubject = subject.replace(/"/g, '\\"');
    const escapedGrade = grade.replace(/"/g, '\\"');
    const escapedText = originalText.replace(/"/g, '\\"');

    let cmd = `python "${scriptPath}" --subject "${escapedSubject}" --grade "${escapedGrade}" --text "${escapedText}"`;
    
    console.log(`Executing refine script for: ${subject} Grade ${grade}`);

    const { stdout, stderr } = await execPromise(cmd, {
      env: {
        ...process.env,
        PROXY_URL: proxyUrl,
        APP_SECRET: appSecret,
        GEMINI_API_KEY: apiKey,
        PYTHONUTF8: '1' // Force UTF-8 for Python execution
      }
    });

    try {
      // 最後の行がJSONのはず
      const lines = stdout.trim().split('\n');
      const resultJson = JSON.parse(lines[lines.length - 1]);
      
      if (resultJson.error) {
        return NextResponse.json({ error: resultJson.error }, { status: 500 });
      }
      
      return NextResponse.json(resultJson);
    } catch (parseError) {
      console.warn("Failed to parse python output as JSON:", stdout);
      return NextResponse.json({ 
        error: "Script finished, but output was not valid JSON",
        stdout 
      }, { status: 500 });
    }

  } catch (error: any) {
    console.error("Refine execution error:", error);
    return NextResponse.json({ 
      error: error.message || "Failed to execute refine script", 
      stderr: error.stderr 
    }, { status: 500 });
  }
}
