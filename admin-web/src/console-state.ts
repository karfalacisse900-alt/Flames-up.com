export type ConsoleSection =
  | "dashboard"
  | "reports"
  | "users"
  | "posts"
  | "media"
  | "listings"
  | "appeals"
  | "operations"
  | "audit"
  | "access";
export const sections: { key: ConsoleSection; label: string; icon: string }[] =
  [
    { key: "dashboard", label: "Overview", icon: "home" },
    { key: "reports", label: "Reports", icon: "report" },
    { key: "users", label: "Users", icon: "users" },
    { key: "posts", label: "Content", icon: "image" },
    { key: "media", label: "Media", icon: "play" },
    { key: "listings", label: "Clubs & Events", icon: "calendar" },
    { key: "appeals", label: "Appeals", icon: "appeal" },
    { key: "operations", label: "Operations", icon: "shield" },
    { key: "audit", label: "Audit History", icon: "history" },
    { key: "access", label: "Admin Access", icon: "settings" },
  ];
export function readConsoleURL(search: string) {
  const params = new URLSearchParams(search);
  const section =
    sections.find((x) => x.key === params.get("section"))?.key ?? "reports";
  return { section, params };
}
export function safePreviewURL(value?: string) {
  if (!value) return "";
  try {
    const url = new URL(value, location.origin);
    return url.protocol === "https:" ||
      (url.origin === location.origin && url.protocol === "http:")
      ? url.href
      : "";
  } catch {
    return "";
  }
}
