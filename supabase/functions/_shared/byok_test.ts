import { handleRecognize } from "../recognize/index.ts";
import { handleApi } from "../api/index.ts";
import { handleWorker } from "../worker/index.ts";
import { parseByokPhoto, pendingByokPhoto } from "./byok.ts";
function assert(value:unknown,message:string):asserts value {if(!value)throw new Error(message);}
const photo="10000000-0000-4000-8000-000000000001";
Deno.test("BYOK rejects forged sources, extra secrets, invalid dates and probabilities",()=>{
 const base={...pendingByokPhoto(photo),status:"ready"};
 for(const value of [ {...base,api_key:"synthetic"},{...base,confidence:1.1},
  {...base,screenshot_date:"2026-02-30"},
  {...base,fields:[{key:"duration",label:"时长",value:"30 分钟",source:"manual",confidence:1}]},
  {...base,fields:[{key:"duration",label:"时长",value:"30 分钟",source:"ai",confidence:1}]},
  {...base,fields:[{key:"duration",label:"时长",value:"30 分钟",source:"screenshot",confidence:1}]},
 ]) {let rejected=false;try{parseByokPhoto(value,photo,"camera");}catch{rejected=true;}assert(rejected,"Invalid provenance accepted");}
 assert(parseByokPhoto(base,photo,"camera").status==="ready","Valid result rejected");
});
Deno.test("retired proxy/settings/AI workers never read or send credentials",async()=>{
 const saved=globalThis.fetch;
 const env={SUPABASE_URL:"https://db.example.com",SUPABASE_ANON_KEY:"synthetic-anon",SUPABASE_SERVICE_ROLE_KEY:"synthetic-service",JOB_SECRET:"synthetic-jobs"};
 const previous=Object.fromEntries(Object.keys(env).map(k=>[k,Deno.env.get(k)]));
 const calls:string[]=[];
 try {
  Object.entries(env).forEach(([k,v])=>Deno.env.set(k,v));
  globalThis.fetch=async(input)=>{
   const url=input instanceof Request?input.url:String(input);calls.push(url);
   assert(url.endsWith('/auth/v1/user'),"Unexpected DB/storage/provider access");
   return Response.json({id:"20000000-0000-4000-8000-000000000001",aud:"authenticated",role:"authenticated",email:"synthetic@example.test"});
  };
  const req=(body:unknown)=>new Request("https://db.example.com/functions/v1/api",{method:"POST",headers:{authorization:"Bearer synthetic-user","content-type":"application/json"},body:JSON.stringify(body)});
  const retired=await handleRecognize(req({}));assert(retired.status===503,"Old client must receive pending-compatible upgrade response");
  for(const action of ['get_ai_settings','save_ai_settings','test_ai_settings','delete_ai_settings']) {
   const res=await handleApi(req({action,api_key:'synthetic-dont-store'}));
   assert(res.status===409,"Old settings accepted");assert(!(await res.text()).includes('synthetic-dont-store'),"Key echoed");
  }
  for(const kind of ['ai','report']) {
   const request=new Request('https://db.example.com/functions/v1/worker',{method:'POST',headers:{'x-job-secret':'synthetic-jobs'},body:JSON.stringify({kind})});
   const response=await handleWorker(request);
   assert(response.status===200 && (await response.json()).data.reason==='CLIENT_BYOK_REQUIRED','Retired worker did not skip');
  }
  assert(calls.length===5,"Unexpected server traffic");
 }finally {
  globalThis.fetch=saved;
  Object.entries(previous).forEach(([k,v])=>v===undefined?Deno.env.delete(k):Deno.env.set(k,v));
 }
});
