// Isolated browser fixtures. Never bundled into the production app; all API requests are intercepted.
import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
const { chromium } = await import(
  process.env.CAPTRO_PLAYWRIGHT || "playwright"
);
const output = resolve(
  process.env.CAPTRO_SCREENSHOTS || "test-results/admin-console",
);
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: true, channel: "msedge" });
const context = await browser.newContext({
  viewport: { width: 1586, height: 992 },
  reducedMotion: "reduce",
});
await context.addInitScript(() => {
  sessionStorage.setItem("captro.admin.token", "fixture-access");
  sessionStorage.setItem("captro.admin.refresh-token", "fixture-refresh");
});
const pictures = [
  "photo-1519501025264-65ba15a82390",
  "photo-1577083552431-6e5fd01aa342",
  "photo-1518391846015-55a9cc003b25",
  "photo-1514565131-fce0801e5785",
  "photo-1509042239860-f550ce710b93",
];
const titles = [
  "Rooftop session",
  "Weekend art club",
  "Downtown meetup",
  "Morning in the city",
  "Coffee this weekend",
];
const reports = Array.from({ length: 26 }, (_, i) => ({
  id: String(1042 + i),
  reporter_id: "reporter-fixture",
  reported_id: `post-${i}`,
  target_type: i % 2 ? "post" : "event",
  target_id: `post-${i}`,
  target_owner_user_id: `creator-${i}`,
  reason: [
    "misleading_event_details",
    "inappropriate_content",
    "harassment_or_bullying",
    "copyright_violation",
    "spam",
  ][i % 5],
  details: "Submitted for review. This report is not proof of a violation.",
  status: i === 0 ? "under_review" : i === 4 ? "action_taken" : "open",
  priority: i % 3 === 1 ? "high" : i % 3 === 2 ? "low" : "medium",
  created_at: "2026-10-16T12:00:00Z",
  updated_at: "2026-10-16T12:00:00Z",
  admin_version: 0,
  reporter: {
    id: "reporter-fixture",
    username: "reporter",
    full_name: "Fixture reporter",
  },
  target_user: {
    id: `creator-${i}`,
    username: [
      "citycollective",
      "theartclub",
      "nyc.social",
      "lensjourney",
      "brewspots",
    ][i % 5],
    full_name: "Fixture creator",
  },
  preview: titles[i % 5],
  target_media: {
    type: "image",
    thumbnail_url: `https://images.unsplash.com/${pictures[i % 5]}?w=900&q=80`,
  },
  notes: [],
  previous_actions: [],
}));
let denied = false,
  failList = false,
  delayFirst = false,
  lostResponse = false,
  operationCount = 0,
  supportReleaseCount = 0,
  supportReleaseBody = null,
  supportTransferID = null,
  supportEnrollmentReadCount = 0,
  supportEnrollmentWriteCount = 0,
  supportEnrollmentBody = null,
  role = "owner";
const requests = [];
const operations = new Map();
const session = () => ({
  user: {
    id: "owner",
    full_name: "Fixture Owner",
    username: "owner",
    status: "active",
  },
  role,
  permissions:
    role === "owner"
      ? ["*"]
      : ["admin:read", "reports:read", "content:read", "users:read"],
  environment: "Isolated test",
});
await context.route("https://api.flames-up.com/api/**", async (route) => {
  const req = route.request(),
    url = new URL(req.url()),
    path = url.pathname.replace("/api", "");
  requests.push(path + url.search);
  const reply = (body, status = 200) =>
    route.fulfill({
      status,
      contentType: "application/json",
      body: JSON.stringify(body),
    });
  if (path === "/admin/me")
    return role === "revoked"
      ? reply({ detail: "Admin access required" }, 403)
      : reply(session());
  if (path === "/admin/console-summary")
    return reply({
      cards: { open_reports: 12, high_priority: 3, in_review: 6, appeals: 2 },
      errors: {},
    });
  if (/^\/admin\/creator-support\/enrollments\//.test(path) && req.method()==="GET") {
    supportEnrollmentReadCount++;
    return reply({creator:{id:"creator-auth-fixture",username:"creator-fixture"},mode:"test",enabled:false,checkoutEnabled:false,reviewedAt:null,readiness:{status:"ready",retryable:false,blockers:[]}});
  }
  if (/^\/admin\/creator-support\/enrollments\//.test(path) && req.method()==="POST") {
    supportEnrollmentWriteCount++;supportEnrollmentBody=req.postDataJSON();
    return reply({creator:{id:"creator-auth-fixture",username:"creator-fixture"},mode:"test",enabled:true,checkoutEnabled:false,reviewedAt:"2026-10-26T16:05:00Z",readiness:{status:"ready",retryable:false,blockers:[]}});
  }
  if (path === "/admin/finance/pools")
    return reply({mode:"test",asOf:"2026-10-26T16:00:00Z",platform:null,pools:[{category:"creator_support",currency:"USD",orders:1,gross:500,pending:441,available:0,paid_out:0,captro_fee:0,processing_fee:59,seller_id:"creator-fixture"}]});
  if (path === "/admin/finance/recovery")
    return reply({cases:[],alerts:[],actionsEnabled:false});
  if (path === "/admin/finance/records")
    return reply({items:[{category:"creator_support",currency:"USD",seller_id:"creator-fixture",order_id:"11111111-1111-4111-8111-111111111111",item_title:"Creator support",gross:500,pending:441,available:0,paid_out:0,captro_fee:0,processing_fee:59}],nextOffset:null});
  if (/^\/admin\/finance\/orders\//.test(path))
    return reply({order:{category:"creator_support",currency:"USD",seller_id:"creator-fixture",buyer_id:"buyer-fixture",order_id:"11111111-1111-4111-8111-111111111111",item_title:"Creator support",gross:500,pending:441,available:0,paid_out:0,captro_fee:0,processing_fee:59,stripe_mode:"test",stripe_payment_intent_id:"pi_test_support",purchase:{contentType:"creator_support",status:"confirmed",stripeMode:"test",settlementModel:"deferred",transferId:supportTransferID,supportReleaseEnabled:true}},entries:[],nextOffset:null});
  if (path.startsWith("/admin/commerce/purchases/") && path.endsWith("/release") && req.method()==="POST") {
    supportReleaseCount++;supportReleaseBody=req.postDataJSON();supportTransferID="tr_test_support";
    return reply({status:"transferred",transferId:"tr_test_support"});
  }
  if (path === "/admin/reports") {
    if (failList)
      return reply({ detail: "Fixture: report service unavailable" }, 503);
    let result = reports;
    const offset = Number(url.searchParams.get("offset")) || 0;
    if (url.searchParams.get("priority"))
      result = result.filter(
        (x) => x.priority === url.searchParams.get("priority"),
      );
    if (url.searchParams.get("search"))
      result = result.filter((x) =>
        x.id.includes(url.searchParams.get("search")),
      );
    return reply({
      results: result.slice(offset, offset + 25),
      pagination: {
        offset,
        limit: 25,
        next_offset: offset + 25 < result.length ? offset + 25 : null,
      },
    });
  }
  if (/^\/admin\/reports\//.test(path)) {
    const id = path.split("/").pop();
    if (delayFirst && id === "1042")
      await new Promise((r) => setTimeout(r, 400));
    return reply({ report: reports.find((x) => x.id === id) });
  }
  if (path === "/admin/console/operations" && req.method() === "POST") {
    operationCount++;
    const body = req.postDataJSON();
    if (denied)
      return reply(
        {
          detail: "Case changed. Reload before applying this decision.",
          code: "STALE_VERSION",
        },
        409,
      );
    const record = reports.find((x) => x.id === body.target);
    if (record) {
      record.status = body.action === "dismiss" ? "dismissed" : "under_review";
      record.admin_version++;
    }
    const result = { ok: true, id: body.id };
    operations.set(body.id, result);
    if (lostResponse) {
      lostResponse = false;
      return route.abort("failed");
    }
    return reply(result);
  }
  if (path.startsWith("/admin/console/operations/"))
    return reply(
      operations.get(path.split("/").pop()) || { detail: "Not recorded" },
      operations.has(path.split("/").pop()) ? 200 : 404,
    );
  if (path === "/admin/users")
    return reply({ results: [], pagination: { next_offset: null } });
  if (path.startsWith("/admin/users/"))
    return reply({
      user: {
        id: path.split("/").pop(),
        username: "fixturecreator",
        status: "active",
        admin_version: 0,
      },
      actions: [],
      recent_posts: [],
      restrictions: [],
    });
  if (
    path === "/admin/posts" ||
    path === "/admin/audit-logs" ||
    path.startsWith("/admin/console/")
  )
    return reply({ results: [], pagination: { next_offset: null } });
  throw Error(`Unexpected API request: ${path}`);
});
const page = await context.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
await page.goto("http://127.0.0.1:4173/?section=reports");
await page.getByRole("button", { name: /Open report 1042:/ }).waitFor();
await page.getByRole("button", { name: /Open report 1042:/ }).click();
await page.getByRole("heading", { name: "Case #1042" }).waitFor();
// Images are optional external fixture scenery; failures remain visibly recoverable.
await page.waitForFunction(() => {
  const image = document.querySelector(".case-inspector img");
  return (
    image?.complete &&
    image.naturalWidth > 0 &&
    !document.querySelector(".case-inspector .preview-status")
  );
});
await page.waitForFunction(() =>
  [...document.querySelectorAll(".case-row img")].every((x) => x.complete),
);
await page.screenshot({
  path: resolve(output, "desktop.png"),
  fullPage: false,
});
assert.equal(
  await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
  true,
);
console.log("PASS desktop report selection, URL, rendered layout");
await page.getByRole("button", { name: "Filter", exact: true }).click();
await page.getByLabel("Priority", { exact: true }).selectOption("high");
await page.waitForFunction(() => location.search.includes("priority=high"));
await page.waitForFunction(
  () => document.querySelectorAll(".case-row").length < 25,
);
assert.ok(requests.some((x) => x.includes("priority=high")));
await page.getByLabel("Priority", { exact: true }).selectOption("");
await page.waitForFunction(
  () => document.querySelectorAll(".case-row").length === 25,
);
await page.getByRole("button", { name: "Next", exact: true }).click();
await page.getByRole("button", { name: /Open report 1067:/ }).waitFor();
assert.match(page.url(), /offset=25/);
await page.getByRole("button", { name: "Previous", exact: true }).click();
await page.getByRole("button", { name: /Open report 1042:/ }).waitFor();
console.log("PASS server filtering and pagination");
await page.getByRole("button", { name: "Dismiss report", exact: true }).click();
await page
  .getByLabel("Reason", { exact: false })
  .fill("Reviewed; no policy violation established.");
await page.getByRole("button", { name: "Confirm action" }).click();
await page.getByRole("dialog").waitFor({ state: "hidden" });
await page.waitForFunction(
  () =>
    document.querySelector(".case-inspector .console-badge")?.textContent ===
    "Dismissed",
);
assert.equal(operationCount, 1);
console.log("PASS confirmed operation updates queue and inspector");
denied = true;
await page.getByRole("button", { name: "Review action", exact: true }).click();
await page
  .getByLabel("Reason", { exact: false })
  .fill("Review concurrency protection");
await page.getByRole("button", { name: "Confirm action" }).click();
await page.getByRole("alert").filter({ hasText: "Case changed" }).waitFor();
assert.equal(
  await page.locator(".case-inspector .console-badge").first().textContent(),
  "Dismissed",
);
await page.getByRole("button", { name: "Cancel", exact: true }).click();
console.log("PASS rejected action leaves case accurate");
denied = false;
lostResponse = true;
await page.getByRole("button", { name: "Review action", exact: true }).click();
await page
  .getByLabel("Reason", { exact: false })
  .fill("Reconcile an ambiguous response");
const before = operationCount;
await page
  .getByRole("button", { name: "Confirm action" })
  .evaluate((button) => {
    button.click();
    button.click();
  });
await page.getByRole("button", { name: "Check operation status" }).waitFor();
await page.getByRole("button", { name: "Check operation status" }).click();
await page.getByRole("dialog").waitFor({ state: "hidden" });
assert.equal(operationCount, before + 1);
console.log(
  "PASS rapid submissions deduplicated; lost response resolved without replaying mutation",
);
delayFirst = true;
await page.getByRole("button", { name: "Close case", exact: true }).click();
await page.getByRole("button", { name: /Open report 1042:/ }).click();
await page.getByRole("button", { name: /Open report 1043:/ }).click();
await page.getByRole("heading", { name: "Case #1043" }).waitFor();
await page.waitForTimeout(500);
assert.equal(
  await page.getByRole("heading", { name: "Case #1043" }).count(),
  1,
);
console.log("PASS delayed old detail cannot overwrite current selection");
await context.route("https://images.unsplash.com/**", (r) =>
  r.fulfill({ status: 404, body: "missing" }),
);
reports[1].target_media.thumbnail_url =
  "https://images.unsplash.com/missing-fixture";
await page.reload();
await page.getByRole("button", { name: "Retry preview" }).waitFor();
await page.getByRole("button", { name: "Retry preview" }).click();
await page.getByRole("button", { name: "Retry preview" }).waitFor();
console.log("PASS broken media is explicit and retryable");
failList = true;
await page.reload();
await page
  .getByRole("alert")
  .filter({ hasText: "report service unavailable" })
  .waitFor();
assert.equal(
  await page.getByRole("heading", { name: "No matching reports" }).count(),
  0,
);
failList = false;
await page.getByRole("button", { name: "Retry", exact: true }).click();
await page.getByRole("button", { name: /Open report 1042:/ }).waitFor();
console.log("PASS query failure never masquerades as empty result");
await context.unroute("https://images.unsplash.com/**");
reports[1].target_media.thumbnail_url = `https://images.unsplash.com/${pictures[1]}?w=900&q=80`;
await page.setViewportSize({ width: 1024, height: 900 });
await page.goto("http://127.0.0.1:4173/?section=reports&case=1042");
await page.getByRole("heading", { name: "Case #1042" }).waitFor();
await page.waitForFunction(() => {
  const image = document.querySelector(".case-inspector img");
  return (
    image?.complete &&
    image.naturalWidth > 0 &&
    !document.querySelector(".case-inspector .preview-status")
  );
});
await page.screenshot({ path: resolve(output, "tablet.png"), fullPage: false });
assert.equal(
  await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
  true,
);
console.log(
  "PASS tablet layout no horizontal page overflow and cached image visible",
);
role = "owner";
await page.setViewportSize({ width: 1586, height: 992 });
await page.goto("http://127.0.0.1:4173/?section=finance");
await page.getByRole("heading", { name: "Captro Funds" }).first().waitFor();
await page.getByLabel("Canonical creator ID").fill("11111111-1111-4111-8111-111111111111");
await page.getByRole("button", { name: "Check creator" }).click();
await page.getByText("Global checkout remains off.").waitFor();
await page.getByLabel("Review reason").fill("Stripe payout readiness reviewed for isolated test eligibility.");
page.once("dialog", (dialog) => dialog.accept());
await page.getByRole("button", { name: "Approve Support" }).click();
await page.getByText("Creator approved for the current mode.").waitFor();
assert.equal(supportEnrollmentReadCount, 1);assert.equal(supportEnrollmentWriteCount, 1);
assert.equal(supportEnrollmentBody.enabled, true);assert.match(supportEnrollmentBody.reason, /payout readiness reviewed/);
await page.getByRole("button", { name: "View records" }).click();
await page.getByRole("button", { name: "View order" }).click();
await page.getByRole("heading", { name: "Support release review" }).waitFor();
await page.getByLabel("Review reason (required)").fill("Provider charge verified; clear confirmed support to creator.");
page.once("dialog", (dialog) => dialog.accept());
await page.getByRole("button", { name: "Approve and release Support earnings" }).click();
await page.getByRole("status").filter({ hasText: "Stripe transfer confirmed" }).waitFor();
assert.equal(supportReleaseCount, 1);
assert.match(supportReleaseBody.note, /Provider charge verified/);
await page.getByText("Stripe transfer recorded:").waitFor();
assert.equal(await page.getByRole("button", { name: "Approve and release Support earnings" }).count(), 0);
assert.match(page.url(), /section=finance/);
await page.screenshot({ path: resolve(output, "support-release-review.png"), fullPage: false });
console.log("PASS owner pre-approves creator while checkout remains globally disabled");
console.log("PASS Admin Funds Support review confirms creator transfer with required note");
role = "support";
await page.goto("http://127.0.0.1:4173/?section=reports&case=1042");
await page
  .getByText("Read-only access. Case changes require a moderator.")
  .waitFor();
assert.equal(
  await page.getByRole("button", { name: "Dismiss report" }).count(),
  0,
);
await page.keyboard.press("Tab");
assert.notEqual(
  await page.evaluate(() => document.activeElement?.tagName),
  "BODY",
);
console.log("PASS read-only UI and keyboard focus");
const financeReadCount = requests.filter((x) => x.startsWith("/admin/finance/")).length;
await page.goto("http://127.0.0.1:4173/?section=finance");
await page.getByRole("alert").filter({ hasText: "Finance access is required" }).waitFor();
assert.equal(requests.filter((x) => x.startsWith("/admin/finance/")).length, financeReadCount);
console.log("PASS finance route denies read-only role before querying funds");
await page.goto("http://127.0.0.1:4173/?section=reports");
role = "revoked";
await page.evaluate(() => window.dispatchEvent(new Event("focus")));
await page.getByRole("button", { name: /sign in/i }).waitFor();
assert.equal(
  await page.evaluate(() => sessionStorage.getItem("captro.admin.token")),
  null,
);
console.log(
  "PASS revoked administrator loses the open console on access recheck",
);
assert.deepEqual(errors, []);
assert.ok(await page.locator('.admin-brand-lockup').first().evaluate(image => image.complete && image.naturalWidth > 0));
await page.screenshot({path: resolve(output, 'sign-in.png'), fullPage: true});
await browser.close();
console.log(`PASS browser suite; screenshots: ${output}`);
