import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";
const output = resolve(
  process.env.CAPTRO_SCREENSHOTS || "test-results/professional",
);
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: "msedge", headless: true });
try {
  for (const width of [1440, 768]) {
    const context = await browser.newContext({
      viewport: { width, height: 1000 },
    });
    await context.addInitScript(() =>
      sessionStorage.setItem("captro.admin.token", "fixture-admin"),
    );
    const application = {
      user_id: "sample",
      role: "creator",
      status: "under_review",
      version: 1,
      public_data: {
        displayName: "Sample Artist",
        category: "musician",
        description: "Independent musician sharing original performances.",
        area: "",
        pickup: false,
        links: ["https://example.com"],
      },
      applicant_message: "Sample application, not a real account.",
      reviewer_message: "",
    };
    let approved = false;
    let decision;
    await context.route("**/api/**", async (route) => {
      const req = route.request(),
        path = new URL(req.url()).pathname.replace("/api", "");
      let data = {},
        status = 200;
      if (path === "/admin/me")
        data = {
          user: { id: "owner", username: "reviewer" },
          role: "owner",
          permissions: ["*"],
          environment: "fixture",
        };
      else if (path === "/admin/professional")
        data = { items: approved ? [] : [application], nextOffset: null };
      else if (path === "/admin/professional/sample/creator")
        data = {
          application: {
            ...application,
            status: approved ? "approved" : "under_review",
            version: approved ? 2 : 1,
          },
          role: approved
            ? { ...application, status: "active", version: 1 }
            : null,
          history: approved
            ? [
                {
                  id: "decision",
                  action: "approve",
                  actor_id: "owner",
                  created_at: "2026-11-15T10:00:00Z",
                  reason: decision.reason,
                  internal_note: decision.note,
                  result: { ok: true },
                },
              ]
            : [],
        };
      else if (path === "/admin/professional/sample/creator/approve") {
        decision = req.postDataJSON();
        approved = true;
        data = { ok: true };
      } else if (path === "/admin/dashboard") data = {};
      else {
        data = { items: [] };
      }
      await route.fulfill({
        status,
        contentType: "application/json",
        body: JSON.stringify(data),
      });
    });
    const page = await context.newPage();
    await page.goto("http://127.0.0.1:4181/?section=professional");
    await page.getByRole("button", { name: /Sample Artist/ }).click();
    await page
      .getByText("Independent musician sharing original performances.")
      .waitFor();
    await page.screenshot({
      path: resolve(output, `admin-review-${width}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "approve", exact: true }).click();
    await page.getByLabel("Decision reason").fill("Reviewed sample evidence");
    await page
      .getByLabel("Message to applicant")
      .fill("Approved for Creator / Gig. Payment readiness remains separate.");
    await page.getByLabel("Internal note").fill("Private test note");
    await page.getByRole("button", { name: "Confirm decision" }).click();
    await page.getByText("approve · Confirmed").waitFor();
    assert.equal(decision.version, 1);
    assert.match(decision.id, /^[a-f0-9-]{36}$/);
    assert.equal(decision.note, "Private test note");
    assert.ok(
      await page
        .getByRole("button", { name: "suspend", exact: true })
        .isVisible(),
    );
    await context.close();
  }
  console.log(
    "PASS admin desktop/tablet application selection, reasoned approval, version/idempotency contract and audit display",
  );
} finally {
  await browser.close();
}
