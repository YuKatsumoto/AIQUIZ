// Native AE authoring through the installed Higgsfield AE bridge's atomic operations.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root='C:/AIQUIZ/AIQUIZ-Godot';
const out=root+'/assets/animations/result_referee/source';
const pkg=path.join(process.env.LOCALAPPDATA,'Higgsfield/ae-mcp/node_modules/fnf-after-effects-mcp');
const sdk=path.join(pkg,'node_modules/@modelcontextprotocol/sdk/dist/esm/client');
const {Client}=await import(pathToFileURL(path.join(sdk,'index.js')));
const {StdioClientTransport}=await import(pathToFileURL(path.join(sdk,'stdio.js')));
const client=new Client({name:'aiquiz-referee-native-authoring',version:'2.0.0'});
await client.connect(new StdioClientTransport({command:process.execPath,args:[path.join(pkg,'dist/index.js')],env:{...process.env,AE_MCP_EXE:'G:/adobe/Adobe After Effects 2026/Support Files/AfterFX.exe'},stderr:'pipe'}));
const log=[];
async function call(name,args){
 const raw=await client.callTool({name,arguments:args},undefined,{timeout:180000});
 const r=raw.structuredContent??JSON.parse(raw.content.find(x=>x.type==='text').text);
 log.push({name,args,result:r});
 await fs.writeFile(out+'/ae_finish_log.json',JSON.stringify(log,null,2));
 if(raw.isError||r.ok===false||r.result?.ok===false)throw Error(JSON.stringify(r));
 return r.result??r;
}
async function op(operation,args){return call('ae_do',{operation,args});}
let ops=[];
function add(operation,args){ops.push({operation,args});}
async function flush(){if(ops.length){const o=ops;ops=[];await op('batch.run',{ops:o,stopOnError:true});}}
const T='ADBE Transform Group';
function keys(comp,layer,prop,times,values,ease=true){
 const property=[T,prop];add('keyframe.set_batch',{comp,layer,property,times,values});
 if(ease)times.forEach((t,i)=>add('keyframe.set_easing',{comp,layer,property,keyIndex:i+1,inSpeed:0,outSpeed:0,inInfluence:60,outInfluence:30}));
}
function text(comp,layer,content,position,fontSize,color=[.97,.98,1],start=0,end=14){
 add('layer.create_text',{comp,name:layer,text:content});
 add('text.set_style',{comp,layer,font:'NotoSansJP-Bold',fontSize,fillColor:color,justification:'center',applyStroke:false});
 add('transform.set',{comp,layer,position});
 add('layer.set_props',{comp,layer,props:{inPoint:start,outPoint:end,motionBlur:true}});
}
function rect(comp,layer,position,size,color,opacity=100,start=0){
 add('layer.create_shape',{comp,name:layer});
 add('shape.add_group',{comp,layer,name:'Editable geometry'});
 add('shape.add_rect',{comp,layer,groupIndex:1,size,position:[0,0],roundness:0});
 add('shape.add_fill',{comp,layer,groupIndex:1,color:[...color,1],opacity:100});
 add('transform.set',{comp,layer,position,opacity});
 add('layer.set_props',{comp,layer,props:{inPoint:start,outPoint:14}});
}
try{
 const items=(await call('ae_project_info',{})).items;
 for(const scenario of ['P1','P2','DRAW']){
  const comp='AIQUIZ_Referee_v2_'+scenario;
  const footageName='Referee stage '+scenario+' (Blender + UltimateToon)';
  let plate=items.find(i=>i.name===footageName)?.id;
  if(!plate){const item=await op('project.import_file',{path:out+'/'+scenario+'_stage_final.mp4',name:footageName});plate=item.id;}
  else await op('footage.replace',{item:plate,path:out+'/'+scenario+'_stage_final.mp4'});
  const layers=(await op('comp.info',{comp})).layers;
  if(!layers.some(l=>l.name==='Blender cast and purchased VFX'))add('layer.create_footage',{comp,sourceItemId:plate,name:'Blender cast and purchased VFX'});
  add('layer.move',{comp,layer:'Blender cast and purchased VFX',toIndex:14});
  add('item.move_to_folder',{item:plate,folder:'AIQUIZ Referee v2'});
  await flush();
 }
 const sounds={};
 for(const name of ['hero_impact','hero_swish','verdict_impact','score_confirm','burst','roll','victory']){
  const item=await op('project.import_file',{path:out+'/audio/'+name+'.wav',name:'Referee sound '+name});sounds[name]=item.id;
  add('item.move_to_folder',{item:item.id,folder:'AIQUIZ Referee v2'});
 }
 await flush();
 for(const scenario of ['P1','P2','DRAW']){
  const comp='AIQUIZ_Referee_v2_'+scenario;
  const cues=[['score_confirm',2,-6],['score_confirm',3.333333,-6],['roll',4.666667,-12],['score_confirm',6.266667,-6],['verdict_impact',7.333333,-12],['victory',11.466667,-8]];
  if(scenario!=='DRAW')cues.push(['hero_impact',8.45,-8],['hero_swish',8.55,-10],['burst',9.55,-9]);
  for(const [sound,time,db] of cues){const layer=sound+' @ '+time;add('layer.create_footage',{comp,sourceItemId:sounds[sound],name:layer});add('layer.set_props',{comp,layer,props:{startTime:time,inPoint:time,outPoint:Math.min(time+2,14)}});add('property.set',{comp,layer,property:['ADBE Audio Group','ADBE Audio Levels'],value:[db,db]});}
  await flush();
  await call('ae_render_frame',{compNameOrId:comp,time:13.5,outPath:root+'/artifacts/result_ceremony/referee/AE_'+scenario+'_freeze.png'});
 }
 await call('ae_save_project',{path:out+'/AIQUIZ_RefereeFinish_v2.aep'});
 await op('render.add_to_queue',{comp:'AIQUIZ_Referee_v2_P1',outputPath:root+'/artifacts/result_ceremony/referee/AE_Referee_v2_P1.mov'});
 const templates=await op('render.list_templates',{});console.log(JSON.stringify(templates));
 await fs.writeFile(out+'/ae_render_templates.json',JSON.stringify(templates,null,2));
}finally{await client.close();}
