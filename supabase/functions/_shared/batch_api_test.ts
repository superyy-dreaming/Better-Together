import { handleApi } from "../api/index.ts";

Deno.test("batch action reaches one transaction and returns every created record", async () => {
  const fetchBefore = globalThis.fetch;
  const names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  const before = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://db.example.test");
  Deno.env.set(names[1], "unit-anon");
  Deno.env.set(names[2], "unit-service");
  let writes = 0, reads = 0;
  try {
    globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
      const request = input instanceof Request ? input : new Request(input, init);
      const path = new URL(request.url).pathname;
      let data: unknown;
      if (path === "/auth/v1/user") data = {id:"91000000-0000-4000-8000-000000000001",aud:"authenticated"};
      else if (path === "/rest/v1/rpc/app_action") {
        const args = await request.json();
        if (args.p_action !== "submit_checkin_batch" || args.p_args.groups.length !== 2) throw new Error("Lost groups");
        writes++;
        data = {checkin_ids:["a","b"],batch_id:"batch"};
      } else if (path === "/rest/v1/rpc/get_checkin") {
        const args = await request.json(); reads++;
        data = {id:args.p_id,photos:[]};
      } else throw new Error("Unexpected endpoint");
      return new Response(JSON.stringify(data),{headers:{"Content-Type":"application/json"}});
    };
    const response = await handleApi(new Request("https://edge.example/api", {
      method:"POST",headers:{Authorization:"Bearer test-token"},
      body:JSON.stringify({action:"submit_checkin_batch",response_version:2,
        idempotency_key:"test-batch",groups:[{media_ids:["one"]},{media_ids:["two"]}]}),
    }));
    const body = await response.json();
    if (response.status !== 200 || writes !== 1 || reads !== 2 || body.data.updated_checkins.length !== 2) {
      throw new Error("Batch contract not preserved");
    }
  } finally {
    globalThis.fetch = fetchBefore;
    names.forEach((name,i)=>before[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name,before[i]!));
  }
});
