import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { requiredEnv, ServiceError } from "./http.ts";

export function adminClient() {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export async function authenticate(request: Request) {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new ServiceError("UNAUTHORIZED", "请先登录后再上传。", 401);
  }
  const client = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    },
  );
  const { data, error } = await client.auth.getUser(authorization.slice(7));
  if (error || !data.user) {
    throw new ServiceError("UNAUTHORIZED", "登录已过期，请重新登录。", 401);
  }
  return { client, user: data.user };
}

export type AdminClient = ReturnType<typeof adminClient>;
