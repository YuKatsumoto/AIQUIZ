const { spawn } = require('child_process');

const env = Object.assign({}, process.env, {
    GODOT_PATH: 'C:\\AIQUIZ\\Godot_v4.4-stable_win64.exe'
});

const proc = spawn('npx.cmd', ['-y', 'godot-mcp'], {
    env: env,
    shell: true
});

proc.stdout.on('data', (data) => {
    const str = data.toString();
    const lines = str.split('\n');
    for (const line of lines) {
        if (!line.trim()) continue;
        if (line.trim().startsWith('{')) {
            process.stdout.write(line + '\n');
        } else {
            process.stderr.write(line + '\n');
        }
    }
});

proc.stderr.on('data', (data) => {
    process.stderr.write(data);
});

process.stdin.pipe(proc.stdin);
