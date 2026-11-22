import { localDate } from "./media_rules.ts";
import { ServiceError } from "./http.ts";

export function retryTime(
  error: unknown,
  attempt: number,
  createdAt: string,
  timezone: string,
  now = new Date(),
  maximumAttempts = 8,
): string | null {
  const retryable = !(error instanceof ServiceError) || error.retryable ||
    error.code === "CONFIGURATION_REQUIRED";
  if (
    !retryable || attempt >= maximumAttempts ||
    localDate(now, timezone) !== localDate(new Date(createdAt), timezone)
  ) return null;
  const delay = Math.min(
    30 * 60_000,
    30_000 * Math.pow(2, Math.max(0, attempt - 1)),
  );
  const next = new Date(now.getTime() + delay);
  return localDate(next, timezone) === localDate(now, timezone)
    ? next.toISOString()
    : null;
}

export function safeError(error: unknown): string {
  if (error instanceof ServiceError) return error.code;
  return error instanceof Error ? error.name : "UnknownError";
}

