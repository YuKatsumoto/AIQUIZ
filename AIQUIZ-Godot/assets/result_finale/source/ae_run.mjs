// Run an ExtendScript function body in the open After Effects through the local
// Higgsfield AE bridge (eval.run). Usage:
//   node ae_run.mjs <script.jsx> [out.json]
// The .jsx is a function body ending with `return <JSON-serializable>;`.
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const bridge = process.env.AE_MCP_PACKAGE || path.join(process.env.LOCALAPPDATA,
  'Higgsfield/ae-mcp/node_modules/fnf-after-effects-mcp');
const sdk = path.join(bridge, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client');
const { Client } = await import(pathToFileURL(path.join(sdk, 'index.js')));
const { StdioClientTransport } = await import(pathToFileURL(path.join(sdk, 'stdio.js')));

const code = await fs.readFile(process.argv[2], 'utf8');
const client = new Client({ name: 'aiquiz-score-tower-finale', version: '1.0.0' });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(bridge, 'dist/index.js')],
  env: {
    ...process.env,
    AE_MCP_ENABLE_EVAL: '1',
    AE_MCP_EXE: process.env.AE_MCP_EXE || 'G:/adobe/Adobe After Effects 2026/Support Files/AfterFX.exe',
  },
  stderr: 'pipe',
});
try {
  await client.connect(transport);
  const result = await client.callTool({ name: 'ae_do', arguments: { operation: 'eval.run', args: { code } } },
    undefined, { timeout: 600000 });
  const text = result.content?.[0]?.text ?? JSON.stringify(result);
  if (process.argv[3]) await fs.writeFile(process.argv[3], text);
  console.log(text.length > 4000 ? text.slice(0, 4000) + '\n…(' + text.length + ' chars)' : text);
  if (result.isError) process.exitCode = 1;
} finally {
  await client.close();
}
