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
 await fs.writeFile(out+'/ae_build_log.json',JSON.stringify(log,null,2));
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
 const info=await call('ae_project_info',{});
 await call('ae_save_project',{path:out+'/AIQUIZ_RefereeFinish_v2.aep'});
 for(const item of info.items)if(item.type==='CompItem' && (item.name.startsWith('AIQUIZ_Referee_v2_')||item.name.startsWith('Referee_v2_')))await op('project.delete_item',{itemId:item.id});
 if(!info.items.some(x=>x.name==='AIQUIZ Referee v2'))await op('folder.create',{name:'AIQUIZ Referee v2'});
 if(!info.items.some(x=>x.name==='Archive - result v1'))await op('folder.create',{name:'Archive - result v1'});
 for(const item of info.items)if(item.type==='CompItem' && item.name.startsWith('AIQUIZ_Result_'))add('item.move_to_folder',{item:item.id,folder:'Archive - result v1'});
 await flush();
 const scenarios=[['P1',[[8,3],[9,1]]],['P2',[[9,1],[7,3]]],['DRAW',[[6,2],[4,3]]]];
 const manifest={comps:{},cards:{}};
 for(const [scenario,scores] of scenarios){
  const comp='AIQUIZ_Referee_v2_'+scenario;
  const created=await op('comp.create',{name:comp,width:1280,height:720,fps:60,duration:14,bgColor:[.027,.047,.082]});
  manifest.comps[scenario]=created.id;
  add('item.move_to_folder',{item:comp,folder:'AIQUIZ Referee v2'});
  add('comp.set_props',{comp,props:{motionBlur:true,shutterAngle:120,comment:'Blender-authored cast plate + editable native AE typography, score counters and controls. 12.667 s result, 14 s preview.'}});
  rect(comp,'Score backing',[640,603],[1280,234],[.027,.047,.082],82,2);
  rect(comp,'Final accent',[640,4],[1280,8],scenario==='P1'?[.95,.55,.2]:scenario==='P2'?[.2,.65,.9]:[1,.83,.27],100,9.333333);
  rect(comp,'Rule separator',[640,104],[380,3],[1,.83,.27],65,2);
  add('layer.set_props',{comp,layer:'Rule separator',props:{outPoint:7.333333}});
  rect(comp,'Controls separator',[640,639],[1184,1],[.97,.98,1],15,9.333333);
  await flush();
  for(let i=0;i<2;i++){
   const card=`Referee_v2_${scenario}_P${i+1}_Card`;
   const dup=await op('comp.duplicate',{comp:`AIQUIZ_Result_P${i+1}_Card`,newName:card});
   manifest.cards[card]=dup.newCompId;
   add('item.move_to_folder',{item:card,folder:'AIQUIZ Referee v2'});
   add('text.set_content',{comp:card,layer:'Correct count',text:String(scores[i][0])});
   add('text.set_content',{comp:card,layer:'HP count',text:String(scores[i][1])});
   add('expression.set',{comp:card,layer:'Total',property:['ADBE Text Properties','ADBE Text Document'],expression:'var n=parseFloat(thisComp.layer("Correct count").text.sourceText)*parseFloat(thisComp.layer("HP count").text.sourceText); time < 4 ? "?" : Math.round(n * thisComp.layer("Count progress").transform.position[0]/100).toString();'});
   const layer=`P${i+1} score card`,x=324+632*i,dir=i===0?1:-1,enter=2+i*4/45;
   add('layer.create_footage',{comp,sourceItemId:dup.newCompId,name:layer});
   add('layer.set_props',{comp,layer,props:{stretch:100/.75,startTime:-2/3,inPoint:2,outPoint:14,motionBlur:true}});
   keys(comp,layer,'ADBE Position',[enter,enter+.46/.75,9.333333,11.466667],[[x-dir*640,571],[x,553],[x,553],[x,577]]);
   keys(comp,layer,'ADBE Scale',[enter,enter+.46/.75,9.333333,11.466667],[[96,96],[100,100],[100,100],[79,79]]);
   keys(comp,layer,'ADBE Rotate Z',[enter,enter+.46/.75],[-4*dir,0]);
   keys(comp,layer,'ADBE Opacity',[enter,enter+.16/.75],[0,100]);
   await flush();
  }
  text(comp,'Heading','得点発表',[640,77],40,undefined,2,7.333333);
  text(comp,'Rule','正解数 × 残りHP で勝負！',[640,120],22,undefined,2,7.333333);
  for(const [name,start,y] of [['Heading',2,77],['Rule',2.133333,120]]){
   keys(comp,name,'ADBE Position',[start,start+.613333],[[640,y+22],[640,y]]);
   keys(comp,name,'ADBE Opacity',[start,start+.213333],[0,100]);
  }
  const draw=scenario==='DRAW';
  text(comp,'Verdict announcement',draw?'引き分け！':`${scenario} の勝ち！`,[640,123],76,undefined,7.333333,9.333333);
  keys(comp,'Verdict announcement','ADBE Scale',[7.333333,7.946667],[[138,138],[100,100]]);
  keys(comp,'Verdict announcement','ADBE Rotate Z',[7.333333,7.946667],[-4,0]);
  keys(comp,'Verdict announcement','ADBE Opacity',[7.333333,7.546667],[0,100]);
  text(comp,'Final winner',draw?'引き分け':`${scenario}  WIN`,[draw?640:305,103],draw?66:70,undefined,9.333333);
  keys(comp,'Final winner','ADBE Opacity',[9.866667,10.666667],[0,100]);
  keys(comp,'Final winner','ADBE Scale',[11.466667,11.666667,11.866667],[[100,100],[108,108],[100,100]]);
  text(comp,'Referee subtitle',draw?'二人ともナイスゲーム！':'ゴドーくんの最終判定！',[draw?640:304,143],20,undefined,9.333333);
  keys(comp,'Referee subtitle','ADBE Opacity',[10.8,11.466667],[0,100]);
  text(comp,'Final eyebrow','F I N A L  R E S U L T',[985,53],15,[1,.83,.27],9.333333);
  keys(comp,'Final eyebrow','ADBE Opacity',[9.533333,10.266667],[0,100]);
  // Reuse the original editable button component; its internal geometry remains native.
  add('layer.create_footage',{comp,sourceItemId:132,name:'Result actions'});
  add('transform.set',{comp,layer:'Result actions',position:[640,670]});
  add('layer.set_props',{comp,layer:'Result actions',props:{stretch:100/.75,startTime:-2/3,inPoint:12.666667,outPoint:14}});
  keys(comp,'Result actions','ADBE Position',[12.666667,13.28],[[640,692],[640,670]]);
  keys(comp,'Result actions','ADBE Opacity',[12.666667,12.88],[0,100]);
  for(const [time,comment] of [[0,'Line-up'],[2,'Score reveal'],[7.333333,'Verdict'],[8.45,draw?'Draw: no contact':'Bat contact'],[8.55,'Release'],[9.55,draw?'Draw: no burst':'Toy burst + deceleration'],[11.466667,'Cast / camera / VFX freeze'],[12.666667,'Interactive controls']])add('marker.add_comp',{comp,time,comment});
  await flush();
  console.log('Created native '+comp);
 }
 await fs.writeFile(out+'/ae_manifest.json',JSON.stringify(manifest,null,2));
 await call('ae_save_project',{path:out+'/AIQUIZ_RefereeFinish_v2.aep'});
}finally{await client.close();}
