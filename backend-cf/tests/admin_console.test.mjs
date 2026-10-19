import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { Hono } from "hono";
import {
  validateConsoleOperation,
  consoleUserFilters,
  registerConsoleRoutes,
  recentAdminMFA,
  activeAdminRestriction,
} from "../src/admin-console.ts";
test("capability expiry is explicit and older active restrictions cannot be truncated out", () => {
  const now = Date.parse("2030-01-01T00:00:00Z");
  const old = {
    restriction_type: "commerce",
    starts_at: "2020-01-01T00:00:00Z",
    ends_at: "2031-01-01T00:00:00Z",
  };
  const rows = [
    ...Array.from({ length: 101 }, () => ({
      ...old,
      ends_at: "2029-01-01T00:00:00Z",
    })),
    old,
  ];
  assert.equal(activeAdminRestriction(rows, "commerce", now), true);
  assert.equal(
    activeAdminRestriction(rows.slice(0, 100), "commerce", now),
    false,
  ); // prior truncation loses the restriction
  assert.equal(activeAdminRestriction(rows, "posting", now), false);
  assert.equal(
    activeAdminRestriction([old], "commerce", Date.parse(old.ends_at)),
    false,
  );
  assert.equal(
    activeAdminRestriction(
      [{ ...old, starts_at: "2031-01-01T00:00:00Z" }],
      "commerce",
      now,
    ),
    false,
  );
});
const command = (action = "review", target = "case-one", version = 0) => ({
  id: crypto.randomUUID(),
  action,
  target,
  version,
  reason: "Reviewed supporting evidence",
  note: "",
});
test("recent token issuance does not substitute for recent verified MFA", () => {
  assert.equal(
    recentAdminMFA(
      {
        aal: "aal2",
        iat: 1000,
        amr: [{ method: "token_refresh", timestamp: 1000 }],
      },
      1000,
    ),
    false,
  );
  assert.equal(
    recentAdminMFA(
      { aal: "aal2", amr: [{ method: "totp", timestamp: 999 }] },
      1000,
    ),
    true,
  );
  for (const jwt of [
    { aal: "aal1", amr: [{ method: "totp", timestamp: 999 }] },
    { aal: "aal2", amr: [{ method: "totp", timestamp: 1 }] },
    { aal: "aal2", amr: [{ method: "totp", timestamp: 1100 }] },
  ])
    assert.equal(recentAdminMFA(jwt, 1000), false);
});
test("console validates target, precision, reason, scopes, roles, and private search", () => {
  assert.equal(validateConsoleOperation(command()).action, "review");
  for (const patch of [
    { id: "abc" },
    { action: "delete_everything" },
    { action: "constructor" },
    { action: "__proto__" },
    { id: "aaaaaaaa--------------------------------" },
    { note: 0 },
    { assignee: 123 },
    { duplicate_of: true },
    { target: "x),or(id.eq.other)" },
    { version: -1 },
    { reason: "" },
    { action: "restrict", hours: 24, scope: "admin" },
    { action: "suspend", hours: 0 },
    { action: "role", role: "superuser" },
  ])
    assert.throws(() => validateConsoleOperation({ ...command(), ...patch }));
  assert.throws(
    () => consoleUserFilters("person@example.com", "all", false),
    /FORBIDDEN/,
  );
  assert.match(
    consoleUserFilters("person@example.com", "active", true).or,
    /email/,
  );
  assert.doesNotMatch(
    consoleUserFilters("captro", "active", false).or,
    /email/,
  );
  assert.equal(
    consoleUserFilters("captro", "suspended", false)["metadata->>status"],
    "eq.suspended",
  );
});
test("HTTP denies anonymous/ordinary/support writes and missing MFA; independent summary survives failure", async () => {
  const app = new Hono();
  let writes = 0;
  const auth = async (c, next) => {
    if (!c.req.header("Authorization")) return c.json({}, 401);
    c.set("jwtPayload", { aal: "aal1", iat: Date.now() / 1000 });
    await next();
  };
  registerConsoleRoutes(app, auth, {
    authorize: async (c, p) => {
      const role = c.req.header("Authorization");
      if (
        role === "user" ||
        (role === "support" && !["admin:read", "reports:read"].includes(p))
      )
        throw Error("FORBIDDEN");
      return { userId: "actor" };
    },
    rateLimit: async () => null,
    rpc: async () => {
      writes++;
      return { ok: true };
    },
    rows: async () => [],
    count: async (_c, t) => {
      if (t === "app_admin_appeals") throw Error("missing schema");
      return 7;
    },
  });
  for (const [authHeader, status] of [
    [undefined, 401],
    ["user", 403],
    ["support", 403],
  ]) {
    const headers = { "Content-Type": "application/json" };
    if (authHeader) headers.Authorization = authHeader;
    assert.equal(
      (
        await app.request("/admin/console/operations", {
          method: "POST",
          headers,
          body: JSON.stringify(command()),
        })
      ).status,
      status,
    );
  }
  assert.equal(
    (
      await app.request("/admin/console/operations", {
        method: "POST",
        headers: { Authorization: "owner", "Content-Type": "application/json" },
        body: JSON.stringify(command("ban", "user-one")),
      })
    ).status,
    403,
  );
  assert.equal(writes, 0);
  assert.equal(
    (
      await app.request("/admin/console/constructor", {
        headers: { Authorization: "owner" },
      })
    ).status,
    404,
  );
  const body = await (
    await app.request("/admin/console-summary", {
      headers: { Authorization: "support" },
    })
  ).json();
  assert.equal(body.cards.open_reports, 7);
  assert.equal(body.cards.appeals, null);
  assert.ok(body.errors.appeals);
});
test("real database console workflows and negative authorization", async (t) => {
  const db = new PGlite();
  try {
    await db.exec(
      `create role anon;create role authenticated;create role service_role;create table app_users(id text primary key,metadata jsonb not null default '{}',updated_at timestamptz default now());`,
    );
    const source = readFileSync(
      new URL(
        "../../supabase/migrations/202606080002_captro_operational.sql",
        import.meta.url,
      ),
      "utf8",
    );
    for (const table of [
      "app_notifications",
      "app_reports",
      "app_admin_roles",
      "app_moderation_actions",
      "app_audit_logs",
    ]) {
      const sql = source.match(
        new RegExp(
          `create table if not exists public\\.${table} \\([\\s\\S]*?\\n\\);`,
        ),
      )?.[0];
      assert.ok(sql);
      await db.exec(sql);
    }
    // Match the live legacy grant shape, not an unrealistically clean fixture.
    await db.exec('grant select,insert,update,delete on app_audit_logs,app_moderation_actions,app_reports to anon,authenticated');
    await db.exec(
      readFileSync(
        new URL(
          "../../supabase/migrations/20261017131303_admin_console_workflows.sql",
          import.meta.url,
        ),
        "utf8",
      ),
    );
    await db.exec(
      `insert into app_users(id) values('owner'),('moderator'),('support'),('ordinary'),('other');insert into app_admin_roles(user_id,role) values('owner','owner'),('moderator','moderator'),('support','support');insert into app_reports(id,reporter_id,target_type,target_id,reason) values('case-one','ordinary','post','post-one','spam'),('case-two','ordinary','post','post-two','spam');`,
    );
    const execute = async (actor, op) =>
      (
        await db.query("select captro_admin_execute($1,$2) as result", [
          actor,
          JSON.stringify(op),
        ])
      ).rows[0].result;
    for (const table of ['app_audit_logs','app_moderation_actions','app_reports','app_admin_roles']) {
      const privilege = await db.query("select has_table_privilege('authenticated',$1,'SELECT,INSERT,UPDATE,DELETE') allowed",[table]);
      assert.equal(privilege.rows[0].allowed,false,table+' remains server-only');
    }
    await t.test(
      "client roles cannot read operations or execute trusted mutation RPC",
      async () => {
        await db.exec("set role authenticated");
        await assert.rejects(
          db.query("select * from app_admin_operations"),
          /permission denied/,
        );
        await assert.rejects(
          db.query("select captro_admin_execute('owner','{}')"),
          /permission denied/,
        );
        await db.exec("reset role");
      },
    );
    await t.test(
      "ordinary/support writes denied and authorized failed attempt audited",
      async () => {
        assert.equal((await execute("ordinary", command())).code, "FORBIDDEN");
        const op = command();
        assert.equal((await execute("support", op)).code, "FORBIDDEN");
        assert.equal(
          (
            await db.query(
              "select count(*)::int as n from app_audit_logs where id=$1",
              [op.id],
            )
          ).rows[0].n,
          1,
        );
      },
    );
    await t.test(
      "lost response replay once, payload conflict and stale concurrent action reject",
      async () => {
        const op = command();
        assert.equal((await execute("moderator", op)).ok, true);
        assert.equal((await execute("moderator", op)).ok, true);
        assert.equal(
          (await execute("moderator", { ...op, action: "dismiss" })).code,
          "IDEMPOTENCY_CONFLICT",
        );
        assert.equal(
          (await execute("moderator", command("dismiss"))).code,
          "STALE_VERSION",
        );
        assert.equal(
          (
            await db.query(
              "select admin_version from app_reports where id='case-one'",
            )
          ).rows[0].admin_version,
          1,
        );
        assert.equal(
          (
            await db.query(
              "select count(*)::int as n from app_moderation_actions where id=$1",
              [op.id],
            )
          ).rows[0].n,
          1,
        );
      },
    );
    await t.test(
      "notes retained, assignment and duplicate grouping validate real targets",
      async () => {
        assert.ok(
          (
            await execute("moderator", {
              ...command("note", "case-one", 1),
              note: "Internal evidence",
            })
          ).ok,
        );
        assert.equal(
          (
            await execute("moderator", {
              ...command("assign", "case-one", 2),
              assignee: "ordinary",
            })
          ).code,
          "INVALID_ASSIGNEE",
        );
        assert.equal(
          (
            await execute("moderator", {
              ...command("duplicate", "case-one", 2),
              duplicate_of: "case-two",
            })
          ).code,
          "INVALID_DUPLICATE",
        );
        assert.ok(
          (
            await execute("moderator", {
              ...command("assign", "case-one", 2),
              assignee: "moderator",
            })
          ).ok,
        );
        assert.equal(
          (
            await db.query(
              "select jsonb_array_length(metadata->'internal_notes') as n from app_reports where id='case-one'",
            )
          ).rows[0].n,
          1,
        );
      },
    );
    await t.test(
      "timed suspension, permanent ban and reinstatement preserve history/revocation",
      async () => {
        const op = {
          ...command("suspend", "ordinary"),
          hours: 24,
          note: "Sensitive internal evidence",
        };
        assert.ok((await execute("owner", op)).ok);
        const metadata = (
          await db.query("select metadata from app_users where id='ordinary'")
        ).rows[0].metadata;
        assert.equal(metadata.status, "suspended");
        assert.ok(Date.parse(metadata.suspended_until) > Date.now());
        assert.ok((await execute("owner", command("ban", "ordinary", 1))).ok);
        assert.ok(
          (await execute("owner", command("reinstate", "ordinary", 2))).ok,
        );
        const after = (
          await db.query("select metadata from app_users where id='ordinary'")
        ).rows[0].metadata;
        assert.equal(after.status, "active");
        assert.ok(after.session_revoked_at);
        assert.doesNotMatch(
          JSON.stringify(
            (await db.query("select body,data from app_notifications")).rows,
          ),
          /Sensitive internal/,
        );
      },
    );
    await t.test(
      "last owner, privileged targets and removed admins protected",
      async () => {
        // An unusable owner account cannot count as the remaining administrator.
        await db.exec(
          "insert into app_users(id,metadata) values('inactive-owner','{\"status\":\"banned\"}');insert into app_admin_roles(user_id,role) values('inactive-owner','owner')",
        );
        assert.equal(
          (
            await execute("owner", {
              ...command("role", "owner"),
              role: "none",
            })
          ).code,
          "LAST_OWNER",
        );
        assert.equal(
          (await execute("owner", command("ban", "moderator"))).code,
          "PROTECTED_ADMIN",
        );
        await db.exec("delete from app_admin_roles where user_id='support'");
        assert.equal((await execute("support", command())).code, "FORBIDDEN");
      },
    );
    await t.test(
      "appeals bind to own decision, replay uniquely and require independent reviewer",
      async () => {
        const decision = (
          await db.query(
            "select id from app_moderation_actions where target_user_id='ordinary' order by created_at limit 1",
          )
        ).rows[0].id;
        const submit = async (who) =>
          (
            await db.query("select captro_submit_appeal($1,$2,$3) as id", [
              who,
              decision,
              "Please review this decision",
            ])
          ).rows[0].id;
        await assert.rejects(submit("other"), /FORBIDDEN/);
        const appeal = await submit("ordinary");
        assert.equal(await submit("ordinary"), appeal);
        assert.equal(
          (await execute("owner", command("appeal_review", appeal))).code,
          "INDEPENDENT_REVIEW_REQUIRED",
        );
        assert.ok(
          (await execute("moderator", command("appeal_review", appeal))).ok,
        );
        assert.ok(
          (await execute("moderator", command("appeal_uphold", appeal, 1))).ok,
        );
      },
    );
  } finally {
    await db.close();
  }
});
