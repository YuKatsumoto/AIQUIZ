import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const pkg=path.join(process.env.LOCALAPPDATA,'Higgsfield/ae-mcp/node_modules/fnf-after-effects-mcp');
const sdk=path.join(pkg,'node_modules/@modelcontextprotocol/sdk/dist/esm/client');
const {Client}=await import(pathToFileURL(path.join(sdk,'index.js')));
const {StdioClientTransport}=await import(pathToFileURL(path.join(sdk,'stdio.js')));
const client=new Client({name:'aiquiz-referee-animation',version:'2.0.0'});
await client.connect(new StdioClientTransport({command:process.execPath,args:[path.join(pkg,'dist/index.js')],env:{...process.env,AE_MCP_EXE:'G:/adobe/Adobe After Effects 2026/Support Files/AfterFX.exe'},stderr:'pipe'}));
try {
 const result=process.argv[2]==='list'?await client.listTools():await client.callTool(JSON.parse(await fs.readFile(process.argv[2],'utf8')),undefined,{timeout:180000});
 await fs.writeFile(process.argv[3],JSON.stringify(result,null,2));
 console.log(process.argv[2]==='list'?result.tools.map(t=>t.name).join('\n'):JSON.stringify(result).slice(0,8000));
}finally{await client.close();}
