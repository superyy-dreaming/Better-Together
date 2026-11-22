import { ServiceError, validUuid } from "./http.ts";

export type ByokField = { key: string; label: string; value: string; source: "ai" | "screenshot"; confidence: number };
export type ByokPhoto = {
  photo_id: string; status: "ready" | "pending" | "rejected";
  plan_id: string | null; confidence: number; summary: string;
  fields: ByokField[]; screenshot_date: string | null; origin: "byok";
};
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max: number): v is string => typeof v === "string" && v.length <= max;
const probability = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 1;
function invalid(): never { throw new ServiceError("BYOK_RESULT_INVALID", "识别结果结构不完整，请重新生成。", 422); }

/** Client-supplied provenance is validated, never presented as model attestation.
 * SQL repeats ownership, source, date, version and majority checks atomically. */
export function parseByokPhoto(value: unknown, photoId: string, source: string): ByokPhoto {
  if (!object(value) || Object.keys(value).some((k) => !["photo_id","status","plan_id","confidence","summary","fields","screenshot_date","origin"].includes(k)) ||
    value.photo_id !== photoId || value.origin !== "byok" ||
    !["ready","pending","rejected"].includes(String(value.status)) ||
    (value.plan_id !== null && !validUuid(value.plan_id)) || !probability(value.confidence) || !text(value.summary,2000) ||
    !Array.isArray(value.fields) || value.fields.length>30 ||
    (value.screenshot_date !== null && (typeof value.screenshot_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value.screenshot_date)))) invalid();
  if (typeof value.screenshot_date === "string") {
    const date = new Date(`${value.screenshot_date}T00:00:00Z`);
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0,10)!==value.screenshot_date) invalid();
  }
  for (const f of value.fields) {
    if (!object(f) || Object.keys(f).some((k)=>!["key","label","value","source","confidence"].includes(k)) ||
      !text(f.key,100) || !f.key || !text(f.label,100) || !f.label || !text(f.value,500) || !probability(f.confidence) ||
      !["ai","screenshot"].includes(String(f.source)) || (f.source==="screenshot" && source!=="screenshot")) invalid();
    if (f.source==="ai" && /(duration|distance|volume|water_ml|sleep|meditation|时长|距离|消耗|饮水量|毫升|睡眠)/i.test(f.key+f.label)) invalid();
  }
  if (value.status!=="ready" && (value.plan_id!==null || value.fields.length)) invalid();
  return value as ByokPhoto;
}

export function pendingByokPhoto(photoId: string): ByokPhoto {
  return {photo_id:photoId,status:"pending",plan_id:null,confidence:0,summary:"",fields:[],screenshot_date:null,origin:"byok"};
}
