export const API = (
  import.meta.env.VITE_CAPTRO_API_BASE || "https://api.flames-up.com/api"
).replace(/\/$/, "");
const ACCESS = "captro.studio.access",
  REFRESH = "captro.studio.refresh";
let epoch = 0,
  refreshing: Promise<void> | null = null;
export class APIError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}
export const session = () => sessionStorage.getItem(ACCESS) || "";
export function clearSession() {
  epoch++;
  sessionStorage.removeItem(ACCESS);
  sessionStorage.removeItem(REFRESH);
  refreshing = null;
}
function storeSession(data: { access_token: string; refresh_token?: string }) {
  if (!data.access_token)
    throw new APIError("Invalid session response. Try again.", 502);
  sessionStorage.setItem(ACCESS, data.access_token);
  if (data.refresh_token) sessionStorage.setItem(REFRESH, data.refresh_token);
}
async function transport(
  path: string,
  body?: unknown,
  method = body === undefined ? "GET" : "POST",
  token = "",
) {
  let response: Response;
  try {
    response = await fetch(API + path, {
      method,
      credentials: "omit",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new APIError(
      "Could not reach Captro. Check your connection and retry.",
      0,
    );
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new APIError(
      data.detail || "Could not complete this request.",
      response.status,
    );
  return data;
}
export async function login(email: string, password: string) {
  const current = epoch;
  const data = await transport("/auth/login", { email, password });
  if (current !== epoch) throw new APIError("Account changed.", 409);
  storeSession(data);
}
export async function exchange(handoff: string) {
  const current = epoch;
  const data = await transport("/professional/studio-session", { handoff });
  if (current !== epoch) throw new APIError("Account changed.", 409);
  storeSession(data);
}
export async function api<T>(
  path: string,
  body?: unknown,
  method?: string,
): Promise<T> {
  const current = epoch;
  let data;
  try {
    data = await transport(path, body, method, session());
  } catch (error) {
    if (current !== epoch) throw new APIError("Account changed. Please sign in again.", 409);
    if (
      !(error instanceof APIError) ||
      error.status !== 401 ||
      !sessionStorage.getItem(REFRESH)
    )
      throw error;
    if (!refreshing) {
      const token = sessionStorage.getItem(REFRESH)!;
      const attempt = transport("/auth/refresh", { refresh_token: token })
        .then((next) => {
          if (current !== epoch) throw new APIError("Account changed.", 409);
          storeSession(next);
        })
        .finally(() => {
          if (refreshing === attempt) refreshing = null;
        });
      refreshing = attempt;
    }
    await refreshing;
    if (current !== epoch) throw new APIError("Account changed. Please sign in again.", 409);
    data = await transport(path, body, method, session());
  }
  if (current !== epoch)
    throw new APIError("Account changed. Please sign in again.", 409);
  return data;
}
export async function logout() {
  try {
    if (session().startsWith("studio_"))
      await api("/professional/studio-signout", {});
  } finally {
    clearSession();
  }
}
export const money = (value: number | null | undefined, currency = "USD") =>
  value == null
    ? "Not reconciled"
    : new Intl.NumberFormat(undefined, { style: "currency", currency }).format(
        value / 100,
      );
export type PublicData = {
  displayName: string;
  category: string;
  description: string;
  links: string[];
  pickup: boolean;
  area: string;
  portfolioPostIds: string[];
};
export type Role = {
  role: "creator" | "business";
  status: "active" | "suspended" | "removed";
  status_message?: string;
  version: number;
  public_data: PublicData;
};
export type Professional = { roles: Role[]; applications: unknown[] };
export const categories = {
  creator: [
    "musician",
    "performer",
    "artist",
    "photographer",
    "filmmaker",
    "freelancer",
    "other_creative",
  ],
  business: [
    "coffee_bakery",
    "street_food",
    "shop",
    "small_brand",
    "service",
    "other_business",
  ],
};
export const words = (value: string) => value.replaceAll("_", " ");

export async function uploadPhoto(file: File): Promise<string> {
  if (
    !["image/jpeg", "image/png", "image/webp", "image/heic"].includes(
      file.type,
    ) ||
    file.size > 20 * 1024 * 1024
  )
    throw new Error("Choose a JPEG, PNG, WebP or HEIC photo under 20 MB.");
  const intent = await api<{ media_id: string; upload_url: string }>(
    "/media/upload-intent",
    {
      media_type: "image",
      filename: file.name,
      mime_type: file.type,
      file_size: file.size,
    },
  );
  const url = new URL(intent.upload_url);
  if (url.protocol !== "https:" || url.hostname !== "upload.imagedelivery.net")
    throw new Error("Unexpected photo upload destination.");
  const form = new FormData();
  form.append("file", file);
  const response = await fetch(url, {
    method: "POST",
    body: form,
    credentials: "omit",
    signal: AbortSignal.timeout(90000),
  });
  if (!response.ok) throw new Error("Photo upload failed. Retry this photo.");
  const complete = { media_id: intent.media_id, file_size: file.size };
  type Status = {
    moderation_status: string;
    upload_status: string;
    rejection_message?: string;
  };
  let status = await api<Status>("/media/complete", complete);
  for (let attempt = 0; attempt < 15; attempt++) {
    if (status.moderation_status === "approved") return intent.media_id;
    if (["rejected", "blocked", "failed"].includes(status.moderation_status))
      throw new Error(
        status.rejection_message || "This photo could not be approved.",
      );
    await new Promise((resolve) => setTimeout(resolve, 1000));
    status =
      status.upload_status === "processing"
        ? await api<Status>("/media/complete", complete)
        : await api<Status>(`/media/${intent.media_id}/status`);
  }
  throw new Error(
    "Photo review is still pending. No unapproved photo was published. Retry later.",
  );
}
