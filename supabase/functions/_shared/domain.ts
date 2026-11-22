export type ApiAction =
  | "ai_context"
  | "save_byok_photo"
  | "report_ai_context"
  | "save_byok_report"
  | "bootstrap"
  | "bootstrap_v2"
  | "read_page"
  | "get_plan"
  | "get_checkin"
  | "media_urls"
  | "save_profile"
  | "create_team"
  | "join_team"
  | "create_invite"
  | "leave_team"
  | "manage_team"
  | "save_plan"
  | "pause_week"
  | "submit_checkin"
  | "submit_checkin_batch"
  | "edit_memo"
  | "reclassify"
  | "assign_batch_fields"
  | "interact"
  | "interact_report"
  | "poke"
  | "mark_notifications"
  | "register_device"
  | "unregister_device"
  | "share_report"
  | "refresh_report"
  | "accept_suggestion"
  | "delete_photo"
  | "delete_account"
  | "get_ai_settings"
  | "save_ai_settings"
  | "delete_ai_settings"
  | "test_ai_settings";
export const actions = new Set<ApiAction>([
  "ai_context", "save_byok_photo", "report_ai_context", "save_byok_report",
  "bootstrap",
  "bootstrap_v2",
  "read_page",
  "get_checkin", "get_plan",
  "media_urls",
  "save_profile",
  "create_team",
  "join_team",
  "create_invite",
  "leave_team",
  "manage_team",
  "save_plan",
  "pause_week",
  "submit_checkin",
  "submit_checkin_batch",
  "edit_memo",
  "reclassify",
  "assign_batch_fields",
  "interact",
  "interact_report",
  "poke",
  "mark_notifications",
  "register_device",
  "unregister_device",
  "share_report",
  "refresh_report",
  "accept_suggestion",
  "delete_photo",
  "delete_account",
  "get_ai_settings",
  "save_ai_settings",
  "delete_ai_settings",
  "test_ai_settings",
]);
export function challengeThreshold(teamSize: number): number {
  return Math.floor(teamSize / 2) + 1;
}
export function canChallenge(teamSize: number, votes: number): boolean {
  return votes >= challengeThreshold(teamSize);
}
export function isAllowedAction(value: unknown): value is ApiAction {
  return typeof value === "string" && actions.has(value as ApiAction);
}
export function databaseError(
  code: string,
  message: string,
): { code: string; message: string; status: number } {
  if (code === "P0001") return { code: "RULE_CONFLICT", message, status: 409 };
  if (code === "28000" || code === "42501") {
    return {
      code: "FORBIDDEN",
      message: "当前账号没有此操作权限。",
      status: 403,
    };
  }
  if (["22P02", "23514", "23502", "22007", "22008"].includes(code)) {
    return {
      code: "INVALID_INPUT",
      message: "请核对填写的内容与时间格式。",
      status: 400,
    };
  }
  if (code === "23505") {
    return {
      code: "ALREADY_EXISTS",
      message: "这条记录已经存在，请刷新查看。",
      status: 409,
    };
  }
  return {
    code: "SERVICE_UNAVAILABLE",
    message: "服务暂时无法完成操作，请稍后重试。",
    status: 503,
  };
}
