import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// Use the installed Higgsfield local AE bridge. No network uploads are needed.
const bridge = process.env.AE_MCP_PACKAGE || path.join(process.env.LOCALAPPDATA,
  'Higgsfield/ae-mcp/node_modules/fnf-after-effects-mcp');
const sdk = path.join(bridge, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client');
const { Client } = await import(pathToFileURL(path.join(sdk, 'index.js')));
const { StdioClientTransport } = await import(pathToFileURL(path.join(sdk, 'stdio.js')));
const client = new Client({ name: 'aiquiz-result-ceremony', version: '1.0.0' });
const transport = new StdioClientTransport({ command: process.execPath,
  args: [path.join(bridge, 'dist/index.js')], env: { ...process.env }, stderr: 'pipe' });
try {
  await client.connect(transport);
  const requests = JSON.parse(await fs.readFile(process.argv[2], 'utf8'));
  const results = [];
  for (const request of requests) {
    const result = await client.callTool(request, undefined, { timeout: 180000 });
    results.push({ name: request.name, result });
    // Keep completed chunks if a later native request is interrupted.
    if (process.argv[3]) await fs.writeFile(process.argv[3], JSON.stringify(results, null, 2));
    if (result.isError || result.structuredContent?.ok === false) {
      if (process.argv[3]) await fs.writeFile(process.argv[3], JSON.stringify(results, null, 2));
      throw Error(`AE operation failed: ${request.name}`);
    }
  }
  await fs.writeFile(process.argv[3], JSON.stringify(results, null, 2));
  console.log(`Completed ${results.length} local AE calls`);
} finally {
  await client.close();
}
