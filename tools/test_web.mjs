// Node 22+; test-only loopback transport. Never edits the pinned Flutter SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn,execFileSync} from 'node:child_process';
import crypto from 'node:crypto';

const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const sdk=process.env.ELEVAGE_FLUTTER_SDK||process.env.FLUTTER_ROOT||'D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk';
const tests=process.argv.slice(2);
if(!tests.length||tests.some(t=>!/^test\/[a-zA-Z0-9_/-]+_test\.dart$/.test(t)||t.includes('..'))) throw Error('Supply explicit test/*_test.dart paths');
if(typeof WebSocket==='undefined') throw Error('Node 22+ with built-in WebSocket is required');
const expected=(await fs.readFile(path.join(repo,'tools/flutter-revision.txt'),'utf8')).trim();
const revision=execFileSync('git',['-c',`safe.directory=${sdk.replaceAll('\\','/')}`,'-C',sdk,'rev-parse','HEAD'],{encoding:'utf8',windowsHide:true}).trim();
if(revision!==expected) throw Error('Pinned Flutter revision mismatch');
const engineRoot=path.resolve(sdk,'bin/cache/flutter_web_sdk/canvaskit');
const folder=path.join(repo,'.local','web-chrome-qualification');await fs.mkdir(folder,{recursive:true});
const log=await fs.open(path.join(folder,'launcher.log'),'w');
const audit={frameworkRevision:revision,engineRevision:(await fs.readFile(path.join(sdk,'bin/cache/engine.stamp'),'utf8')).trim(),
  tests,startedAt:new Date().toISOString(),canvasKitWindowsWorkaround:process.platform==='win32',servedEngineFiles:{},blockedExternalRequests:[]};
let socket,attachError,attaching=false,recent='',port,origin;
let writes=Promise.resolve();
const wait=ms=>new Promise(ok=>setTimeout(ok,ms));
async function connect() {
  const deadline=Date.now()+30000;let target;
  while(Date.now()<deadline) {
    try {target=(await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t=>t.type==='page'&&t.url.startsWith(origin+'/static/'));}catch{}
    if(target)break;await wait(100);
  }
  if(!target)throw Error('Owned Flutter test page unavailable');
  socket=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok,bad)=>{socket.onopen=ok;socket.onerror=bad;});
  let id=0;const calls=new Map();let reloaded=false;
  const call=(method,params={})=>new Promise((ok,bad)=>{const n=++id;calls.set(n,{ok,bad});socket.send(JSON.stringify({id:n,method,params}));});
  socket.onmessage=e=>{void receive(JSON.parse(e.data)).catch(error=>{attachError=error;console.error(String(error));});};
  async function receive(d) {
    if(d.id) {const p=calls.get(d.id);calls.delete(d.id);if(p)d.error?p.bad(Error(JSON.stringify(d.error))):p.ok(d.result);return;}
    if(d.method==='Runtime.exceptionThrown' && !reloaded && JSON.stringify(d.params).includes('canvaskit')) {
      reloaded=true;
      await call('Runtime.evaluate',{expression:"document.querySelector('iframe')?.contentWindow.location.reload()"});return;
    }
    if(d.method!=='Fetch.requestPaused')return;
    const requestId=d.params.requestId,u=new URL(d.params.request.url);
    if(!['localhost','127.0.0.1','[::1]'].includes(u.hostname)) {
      audit.blockedExternalRequests.push({origin:u.origin,path:u.pathname});
      await call('Fetch.failRequest',{requestId,errorReason:'BlockedByClient'});return;
    }
    if(u.origin!==origin||!u.pathname.startsWith('/canvaskit/')) {await call('Fetch.continueRequest',{requestId});return;}
    const relative=decodeURIComponent(u.pathname.slice('/canvaskit/'.length));
    if(relative.includes('..')||relative.includes('\\')||!relative.match(/^[a-z0-9_./-]+\.(?:js|wasm)$/i)) {
      attachError=Error('Invalid engine asset path');await call('Fetch.failRequest',{requestId,errorReason:'BlockedByClient'});return;
    }
    const filename=path.resolve(engineRoot,relative);
    if(!filename.startsWith(engineRoot+path.sep))throw Error('Engine asset escaped SDK cache');
    const bytes=await fs.readFile(filename);
    audit.servedEngineFiles[relative]=crypto.createHash('sha256').update(bytes).digest('hex');
    await call('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[
      {name:'Content-Type',value:relative.endsWith('.wasm')?'application/wasm':'text/javascript'},
      {name:'Access-Control-Allow-Origin',value:'*'}],body:bytes.toString('base64')});
  }
  // Only the browser owned by this test process is controlled. All remote
  // HTTP requests are refused. Only exact local engine files are substituted.
  await call('Fetch.enable',{patterns:[{urlPattern:'*',requestStage:'Request'}]});
  await call('Runtime.enable');
  console.log('Local CanvasKit workaround active; external requests blocked.');
}
function consume(data) {
  const value=data.toString();writes=writes.then(()=>log.write(value));recent=(recent+value).slice(-32000);
  for(const line of value.split(/\r?\n/))if(/\d\d:\d\d\s+[+-]\d|All tests passed|Some tests failed|Test failed|Error:/.test(line))console.log(line.trim());
  if(process.platform!=='win32'||attaching)return;
  const p=recent.match(/(?:--remote-debugging-port=|DevTools listening on ws:\/\/127\.0\.0\.1:)(\d+)/),o=recent.match(/http:\/\/localhost:\d+\/static\/index\.html/);
  if(p&&o) {port=Number(p[1]);origin=new URL(o[0]).origin;attaching=true;void connect().catch(error=>{attachError=error;console.error(String(error));});}
}
const flutter=path.join(sdk,'bin',process.platform==='win32'?'flutter.bat':'flutter');
const args=['test','--verbose','--no-pub','--platform=chrome',...tests];
let child;
if(process.platform==='win32') {
  if(/["\r\n&|<>^%!]/.test(flutter))throw Error('Unsupported SDK path');
  child=spawn(process.env.ComSpec||'cmd.exe',['/d','/s','/c',`""${flutter}" ${args.join(' ')}"`],{cwd:repo,env:process.env,windowsHide:true,windowsVerbatimArguments:true});
} else child=spawn(flutter,args,{cwd:repo,env:process.env});
child.stdout.on('data',consume);child.stderr.on('data',consume);
const code=await new Promise((ok,bad)=>{child.on('close',ok);child.on('error',bad);});
socket?.close();audit.finishedAt=new Date().toISOString();audit.exitCode=code;
audit.harnessError=attachError?String(attachError):null;
if(process.platform==='win32' && (!attaching||!Object.keys(audit.servedEngineFiles).length))audit.harnessError||='Local engine workaround was not exercised';
await fs.writeFile(path.join(folder,'audit.json'),JSON.stringify(audit,null,2));await writes;await log.close();
console.log(`Browser audit: ${path.join(folder,'audit.json')}`);
process.exitCode=code===0&&!audit.harnessError?0:1;
