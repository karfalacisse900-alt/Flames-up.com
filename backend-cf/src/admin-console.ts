// Console contracts and policy; all persistence goes through existing service-role adapters.
export function activeAdminRestriction(
  entries: any[],
  scope: string,
  now = Date.now(),
): boolean {
  return entries.some((r) => {
    if (r.restriction_type !== "all" && r.restriction_type !== scope)
      return false;
    const start = Date.parse(r.starts_at || r.created_at || "");
    const end = Date.parse(r.ends_at || "");
    return (
      (!Number.isFinite(start) || start <= now) &&
      (!Number.isFinite(end) || end > now)
    );
  });
}
export const consolePermissions: Record<string, string> = {
  note: "reports:write",
  assign: "reports:write",
  review: "reports:write",
  dismiss: "reports:write",
  escalate: "reports:write",
  resolve: "reports:write",
  duplicate: "reports:write",
  warn: "users:warn",
  restrict: "users:restrict",
  suspend: "users:suspend",
  ban: "users:ban",
  reinstate: "users:ban",
  role: "roles:write",
  appeal_review: "reports:write",
  appeal_uphold: "reports:write",
};
export function recentAdminMFA(jwt: any, now = Date.now() / 1000) {
  return (
    jwt?.aal === "aal2" &&
    Array.isArray(jwt.amr) &&
    jwt.amr.some(
      (factor: any) =>
        factor.method === "totp" &&
        Number.isFinite(factor.timestamp) &&
        factor.timestamp <= now + 30 &&
        now - factor.timestamp <= 900,
    )
  );
}
export function validateConsoleOperation(input: any) {
  if (
    !input ||
    typeof input.action !== "string" ||
    !Object.hasOwn(consolePermissions, input.action)
  )
    throw new Error("INVALID_ACTION");
  if (
    typeof input.id !== "string" ||
    !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(input.id)
  )
    throw new Error("INVALID_OPERATION_ID");
  if (typeof input.target !== "string" || !/^[\w-]{1,160}$/.test(input.target))
    throw new Error("INVALID_TARGET");
  if (
    typeof input.reason !== "string" ||
    input.reason.trim().length < 3 ||
    input.reason.length > 800
  )
    throw new Error("REASON_REQUIRED");
  if (!Number.isSafeInteger(input.version) || input.version < 0)
    throw new Error("VERSION_REQUIRED");
  if (
    input.note !== undefined &&
    (typeof input.note !== "string" || input.note.length > 2000)
  )
    throw new Error("INVALID_NOTE");
  if (
    ["suspend", "restrict"].includes(input.action) &&
    (!Number.isSafeInteger(input.hours) ||
      input.hours < 1 ||
      input.hours > 2160)
  )
    throw new Error("INVALID_DURATION");
  if (
    input.action === "restrict" &&
    !["posting", "commenting", "messaging", "commerce", "all"].includes(
      input.scope,
    )
  )
    throw new Error("INVALID_SCOPE");
  if (
    input.action === "role" &&
    !["owner", "moderator", "support", "none"].includes(input.role)
  )
    throw new Error("INVALID_ROLE");
  if (
    input.assignee !== undefined &&
    (typeof input.assignee !== "string" ||
      (input.assignee !== "" && !/^[\w-]{1,160}$/.test(input.assignee)))
  )
    throw new Error("INVALID_ASSIGNEE");
  if (
    input.duplicate_of !== undefined &&
    (typeof input.duplicate_of !== "string" ||
      !/^[\w-]{1,160}$/.test(input.duplicate_of))
  )
    throw new Error("INVALID_DUPLICATE");
  return Object.fromEntries(
    [
      "id",
      "action",
      "target",
      "version",
      "reason",
      "note",
      "hours",
      "scope",
      "role",
      "assignee",
      "duplicate_of",
    ]
      .filter((k) => input[k] !== undefined)
      .map((k) => [k, input[k]]),
  );
}
export function consolePage(query: Record<string, string>) {
  return {
    limit: 25,
    offset: Math.min(
      100000,
      Math.max(0, Math.trunc(Number(query.offset) || 0)),
    ),
  };
}
export function consoleUserFilters(
  search: string,
  status: string,
  privateLookup: boolean,
) {
  const filters: Record<string, string> = {};
  if (status && status !== "all" && /^[a-z_]+$/.test(status))
    filters["metadata->>status"] = `eq.${status}`;
  const term = search.trim().slice(0, 120);
  if (term.includes("@") && !privateLookup)
    throw new Error("PRIVATE_LOOKUP_FORBIDDEN");
  // Never interpolate PostgREST punctuation supplied by an operator.
  const safe = term.replace(/[^\p{L}\p{N}_@. -]/gu, "");
  if (term && !safe) throw new Error("INVALID_SEARCH");
  if (safe)
    filters.or = `(id.ilike.*${safe}*,username.ilike.*${safe}*${privateLookup ? `,email.ilike.*${safe}*` : ""})`;
  return filters;
}
export async function performConsoleOperation(c: any, io: any) {
  const actor = await io.authorize(c, "admin:read");
  const limited = await io.rateLimit(c, actor, "admin_console_operation");
  if (limited) return limited;
  if (Number(c.req.header("Content-Length")) > 10000)
    return c.json({ detail: "Action payload is too large." }, 413);
  const raw = await c.req.text();
  if (raw.length > 10000)
    return c.json({ detail: "Action payload is too large." }, 413);
  let input: any;
  try {
    input = JSON.parse(raw);
  } catch {
    throw new Error("INVALID_JSON");
  }
  const body = validateConsoleOperation(input);
  await io.authorize(c, consolePermissions[String(body.action)]);
  // Role changes and permanent bans require a verified, recent MFA session, never a body claim.
  if (["role", "ban", "reinstate"].includes(String(body.action))) {
    const jwt = c.get("jwtPayload");
    if (!recentAdminMFA(jwt))
      return c.json(
        {
          detail:
            "Recent authenticator verification is required. Ask the owner to complete the approved MFA setup.",
          code: "STEP_UP_REQUIRED",
        },
        403,
      );
  }
  const result = await io.rpc(c, "captro_admin_execute", {
    p_actor: actor.userId,
    p_request: body,
  });
  return c.json(
    {
      ...result,
      detail: result.ok
        ? undefined
        : result.code === "STALE_VERSION"
          ? "This record changed. Close this dialog, review the refreshed record and try again."
          : String(result.code || "Operation failed").replaceAll("_", " "),
    },
    result.ok
      ? 200
      : result.code === "FORBIDDEN"
        ? 403
        : result.code === "NOT_FOUND"
          ? 404
          : 409,
  );
}

export function registerConsoleRoutes(api: any, auth: any, io: any) {
  const run = (fn: (c: any) => Promise<any>) => async (c: any) => {
    c.header("Cache-Control", "private, no-store");
    try {
      return await fn(c);
    } catch (error: any) {
      const code = String(error?.message || "");
      const denied =
        code === "FORBIDDEN" || code === "PRIVATE_LOOKUP_FORBIDDEN";
      const invalid = /^(INVALID_|REASON_REQUIRED|VERSION_REQUIRED)/.test(code);
      return c.json(
        {
          detail: denied
            ? "You do not have permission for this action."
            : invalid
              ? "Check the action and required fields."
              : "This section is unavailable. Retry or check the required schema deployment.",
          code: denied ? "FORBIDDEN" : invalid ? code : "CONSOLE_UNAVAILABLE",
        },
        denied ? 403 : invalid ? 400 : 503,
      );
    }
  };
  api.post(
    "/admin/console/operations",
    auth,
    run((c) => performConsoleOperation(c, io)),
  );
  api.get(
    "/admin/console/operations/:id",
    auth,
    run(async (c) => {
      const actor = await io.authorize(c, "admin:read");
      if (
        !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(
          c.req.param("id"),
        )
      )
        return c.json({ detail: "Invalid operation ID" }, 400);
      const rows = await io.rows(c, "app_admin_operations", {
        select: "id,result,created_at",
        filters: {
          actor_id: `eq.${actor.userId}`,
          id: `eq.${c.req.param("id")}`,
        },
        limit: 1,
      });
      return rows.length
        ? c.json(rows[0].result)
        : c.json(
            {
              detail:
                "Operation not recorded. It is safe to retry with the same operation ID.",
            },
            404,
          );
    }),
  );
  const resources: Record<
    string,
    {
      table: string;
      select: string;
      permission: string;
      order?: string;
      status?: string;
    }
  > = {
    media: {
      table: "app_media_assets",
      select:
        "id,user_id,media_type,mime_type,width,height,upload_status,moderation_status,created_at,updated_at",
      permission: "content:read",
      status: "moderation_status",
    },
    stories: {
      table: "app_stories",
      select: "id,user_id,media_type,visibility,status,expires_at,created_at",
      permission: "content:read",
      status: "status",
    },
    listings: {
      table: "app_purchasables",
      select:
        "id,post_id,title,creator_app_user_id,content_type,status,payment_model,starts_at,ends_at,expires_at,capacity,quantity_committed,created_at",
      permission: "content:read",
      status: "status",
    },
    appeals: {
      table: "app_admin_appeals",
      select:
        "id,decision_id,appellant_id,statement,status,outcome_notice,admin_version,created_at",
      permission: "reports:read",
      status: "status",
    },
    access: {
      table: "app_admin_roles",
      select: "user_id,role,admin_version,created_at,updated_at",
      permission: "roles:write",
      order: "created_at.desc,user_id.asc",
    },
    operations: {
      table: "app_admin_operations",
      select: "id,actor_id,result,created_at",
      permission: "audit:read",
      order: "created_at.desc,actor_id.asc,id.asc",
    },
  };
  api.get(
    "/admin/console/:section",
    auth,
    run(async (c) => {
      const section = c.req.param("section");
      const resource = Object.hasOwn(resources, section)
        ? resources[section]
        : undefined;
      if (!resource) return c.json({ detail: "Unknown section" }, 404);
      await io.authorize(c, resource.permission);
      const page = consolePage(c.req.query());
      const status = c.req.query("status");
      const filters: Record<string, string> = {};
      if (
        status &&
        status !== "all" &&
        resource.status &&
        /^[a-z_]+$/.test(status)
      )
        filters[resource.status] = `eq.${status}`;
      const rows = await io.rows(c, resource.table, {
        select: resource.select,
        filters,
        order: resource.order || "created_at.desc,id.asc",
        limit: page.limit + 1,
        offset: page.offset,
      });
      return c.json({
        results: rows.slice(0, page.limit),
        pagination: {
          ...page,
          next_offset:
            rows.length > page.limit ? page.offset + page.limit : null,
        },
      });
    }),
  );
  api.get(
    "/admin/console-summary",
    auth,
    run(async (c) => {
      await io.authorize(c, "reports:read");
      const cards: Record<string, number | null> = {};
      const errors: Record<string, string> = {};
      const jobs: Record<string, [string, Record<string, string>]> = {
        open_reports: [
          "app_reports",
          { status: "in.(open,pending,under_review,in_review,escalated)" },
        ],
        high_priority: [
          "app_reports",
          {
            status: "in.(open,pending,under_review,in_review,escalated)",
            priority: "in.(urgent,high)",
          },
        ],
        in_review: ["app_reports", { status: "in.(under_review,in_review)" }],
        appeals: ["app_admin_appeals", { status: "in.(open,in_review)" }],
      };
      await Promise.all(
        Object.entries(jobs).map(async ([key, [table, filters]]) => {
          try {
            cards[key] = await io.count(c, table, filters);
          } catch {
            cards[key] = null;
            errors[key] = "Count unavailable";
          }
        }),
      );
      return c.json({ cards, errors });
    }),
  );
}
