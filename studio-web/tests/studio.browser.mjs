import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";
const output = resolve(
  process.env.CAPTRO_SCREENSHOTS || "test-results/professional",
);
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: "msedge", headless: true });
const shop = "20000000-0000-4000-8000-000000000001",
  product = "30000000-0000-4000-8000-000000000001",
  order = "40000000-0000-4000-8000-000000000001";
const publicCreator = {
  displayName: "Sample Artist",
  category: "photographer",
  description: "Portraits, performances and everyday life.",
  links: [],
  area: "",
  pickup: false,
  portfolioPostIds: [],
};
const publicBusiness = {
  displayName: "Sample Coffee",
  category: "coffee_bakery",
  description: "Coffee and pastries in Brooklyn.",
  links: [],
  area: "Brooklyn",
  pickup: true,
  portfolioPostIds: [],
};
let tests = 0;
try {
  for (const viewport of [
    { width: 1440, height: 1050 },
    { width: 390, height: 844 },
  ]) {
    const context = await browser.newContext({
      viewport,
      reducedMotion: "reduce",
    });
    await context.addInitScript(() =>
      sessionStorage.setItem("captro.studio.access", "fixture-only"),
    );
    let businessStatus = "active",
      orderStatus = "received",
      rejected = false,
      failedSales = false;
    const calls = [];
    await context.route("**/api/**", async (route) => {
      const req = route.request(),
        url = new URL(req.url()),
        path = url.pathname.replace("/api", ""),
        body = req.postDataJSON();
      calls.push({ path, method: req.method(), body });
      let data = {},
        status = 200;
      if (path === "/auth/me")
        data = {
          id: "sample",
          username: "sample",
          full_name: "Sample professional",
        };
      else if (path === "/professional/me")
        data = {
          applications: [],
          roles: [
            {
              role: "creator",
              status: "active",
              version: 1,
              public_data: publicCreator,
            },
            {
              role: "business",
              status: businessStatus,
              version: 1,
              public_data: publicBusiness,
            },
          ],
        };
      else if (path === "/business-owner/shops")
        data = [
          {
            id: shop,
            name: "Sample Coffee",
            category: "coffee_bakery",
            pickup_address: "Sample pickup point",
            latitude: 40.7,
            longitude: -73.9,
            hours: "Mon–Fri 8–4",
            paused: false,
            published: true,
            photos: [],
            tax_bps: 800,
          },
        ];
      else if (path.endsWith("/products"))
        data = [
          {
            id: product,
            name: "Sample Latte",
            category: "Coffee",
            unit_amount: 490,
            mode: "CUSTOMIZE",
            available: true,
            stock: 12,
            groups: [
              {
                id: "milk",
                name: "Milk",
                minimum: 1,
                maximum: 1,
                options: [{ id: "oat", name: "Oat", extra: 50 }],
              },
            ],
          },
        ];
      else if (path.endsWith("/orders"))
        data = [
          {
            id: order,
            business_name: "Sample Coffee",
            status: orderStatus,
            created_at: "2026-11-15T10:00:00Z",
            total: 540,
            processing_fee: 42,
            refunded_amount: 0,
            lines: [
              {
                name: "Sample Latte",
                quantity: 1,
                unit_amount: 540,
                options: [{ name: "Oat" }],
              },
            ],
          },
        ];
      else if (path === `/business-orders/${order}/action`) {
        if (rejected) {
          status = 409;
          data = { detail: "Order changed. Reload before acting." };
        } else {
          orderStatus = "accepted";
          data = { ok: true };
        }
      } else if (path.endsWith("/earnings")) {
        if (failedSales) {
          status = 503;
          data = { detail: "Sales are temporarily unavailable." };
        } else
          data = {
            gross: 540,
            tax: 0,
            refunded: 0,
            processing_fee: 42,
            pending_fees: 0,
          };
      } else if (path === "/commerce/earnings/support-readiness")
        data = {
          status: "blocked",
          blockers: [
            {
              source: "captro",
              code: "rollout_disabled",
              message:
                "Support checkout is disabled by Captro in this environment.",
            },
          ],
        };
      else if (path === "/commerce/earnings/pools")
        data = {
          mode: "test",
          payoutScope: "creator_currency_all_categories_fifo",
          pools: [
            {
              category: "creator_support",
              currency: "USD",
              grossReceived: 1000,
              processingFees: 59,
              creatorNet: 941,
              pending: 941,
              available: 0,
              paidOut: 0,
              held: 0,
              refunded: 0,
              captroFee: 0,
            },
          ],
        };
      else if (path === "/commerce/earnings/pools/creator_support")
        data = {
          items: [
            {
              id: "support-test",
              status: "pending",
              createdAt: "2026-11-15T10:00:00Z",
              grossReceived: 1000,
              processingFees: 59,
              creatorNet: 941,
              currency: "USD",
            },
          ],
          nextOffset: null,
        };
      else if (path === "/users/sample/posts")
        data = [
          {
            id: "gig",
            title: "Sample performance",
            post_type: "event",
            visibility: "public",
            detail: {
              event: {
                creatorEditable: true,
                startsAt: "2026-12-15T19:00:00Z",
                timeZone: "America/New_York",
                venueName: "Sample venue",
                attendanceEnabled: true,
              },
            },
          },
        ];
      else if (path === "/posts/gig/event") data = { ok: true };
      else if (path === "/professional/creator/edit_public")
        data = { ok: true };
      else {
        status = 404;
        data = { detail: "Unexpected fixture request" };
      }
      await route.fulfill({
        status,
        contentType: "application/json",
        body: JSON.stringify(data),
      });
    });
    const page = await context.newPage();
    await page.goto("http://127.0.0.1:4180/");
    await page.getByRole("heading", { name: "Sample Artist" }).waitFor();
    tests++;
    await page.getByRole("button", { name: "Edit gig details" }).click();
    await page.getByLabel("Public venue").fill("Updated sample venue");
    await page.getByRole("button", { name: "Save gig details" }).click();
    await page.getByRole("dialog").waitFor({ state: "hidden" });
    assert.equal(
      calls.find((c) => c.path === "/posts/gig/event").body.venueName,
      "Updated sample venue",
    );
    tests++;
    await page.getByRole("button", { name: "Support", exact: true }).click();
    await page.getByText("Gross Support", { exact: true }).waitFor();
    await page
      .getByText("Support checkout is disabled by Captro in this environment.")
      .waitFor();
    assert.equal(
      await page.getByRole("button", { name: /Withdraw|Pay now/ }).count(),
      0,
    );
    tests++;
    await page.screenshot({
      path: resolve(output, `studio-creator-${viewport.width}.png`),
      fullPage: true,
    });
    await page
      .getByLabel("Workspace", { exact: true })
      .selectOption("business");
    await page
      .getByRole("heading", { name: "Sample Coffee", exact: true })
      .waitFor();
    await page.getByRole("button", { name: "accept", exact: true }).click();
    await page.getByRole("button", { name: "Confirm", exact: true }).click();
    await page.getByText("accepted", { exact: true }).waitFor();
    assert.equal(calls.filter((c) => c.path.endsWith("/action")).length, 1);
    tests++;
    await page.screenshot({
      path: resolve(output, `studio-business-${viewport.width}.png`),
      fullPage: true,
    });
    rejected = true;
    await page.getByRole("button", { name: "prepare", exact: true }).click();
    await page.getByRole("button", { name: "Confirm", exact: true }).click();
    await page.getByText("Order changed. Reload before acting.").waitFor();
    assert.ok(await page.getByText("accepted", { exact: true }).isVisible());
    tests++;
    await page.getByRole("button", { name: "Keep unchanged" }).click();
    await page.getByRole("button", { name: "Menu", exact: true }).click();
    await page.getByRole("button", { name: /Sample Latte/ }).click();
    await page.getByLabel("Group name").waitFor();
    assert.equal(
      await page.getByLabel("Option", { exact: true }).inputValue(),
      "Oat",
    );
    await page.getByLabel("Stock · leave blank for unlimited").fill("8");
    await page.getByRole("button", { name: "Save menu item", exact: true }).click();
    await page.getByRole("dialog").waitFor({ state: "hidden" });
    const productUpdate = calls.find(c => c.path.endsWith("/products") && c.method === "POST");
    assert.equal(productUpdate.body.stock, 8);
    assert.equal(productUpdate.body.expected_stock, 12);
    tests++;
    failedSales = true;
    await page.getByRole("button", { name: "Sales", exact: true }).click();
    await page.getByText("Sales are temporarily unavailable.").waitFor();
    assert.equal(await page.locator("dd").count(), 0);
    tests++;
    await page
      .getByRole("button", { name: "Public information", exact: true })
      .click();
    await page.getByLabel("Display name").fill("Unsaved change");
    await page.getByRole("button", { name: "Cancel changes" }).click();
    assert.equal(
      await page.getByLabel("Display name").inputValue(),
      "Sample Coffee",
    );
    tests++;
    businessStatus = "suspended";
    await page.reload();
    await page.getByText(/Your business role is suspended/).waitFor();
    await page.getByRole("button", { name: "Storefront", exact: true }).click();
    assert.ok(
      await page
        .getByRole("button", { name: "Save storefront", exact: true })
        .isDisabled(),
    );
    tests++;
    assert.ok(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth + 1,
      ),
    );
    await page.getByRole("button", { name: "Sign out", exact: true }).click();
    await page
      .getByRole("heading", { name: "Your professional workspace" })
      .waitFor();
    assert.equal(
      await page.evaluate(() => sessionStorage.getItem("captro.studio.access")),
      null,
    );
    tests++;
    await context.close();
  }
  for (const accountState of ["regular", "under_review", "declined", "business_only", "banned"]) {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await context.addInitScript(() => sessionStorage.setItem("captro.studio.access", "fixture-only"));
    let revoked = accountState === "banned";
    const paths = [];
    await context.route("**/api/**", async route => {
      const path = new URL(route.request().url()).pathname.replace("/api", ""); paths.push(path);
      const data = revoked ? { detail: "This account no longer has access." }
        : path === "/auth/me" ? { id: "sample", username: "sample" }
        : path === "/professional/me" ? {
          applications: accountState === "regular" || accountState === "business_only" ? [] : [{ role: "creator", status: accountState }],
          roles: accountState === "business_only" ? [{ role: "business", status: "active", version: 1, public_data: publicBusiness }] : []
        } : path === "/business-owner/shops" ? [] : {};
      await route.fulfill({ status: revoked ? 403 : 200, contentType: "application/json", body: JSON.stringify(data) });
    });
    const page = await context.newPage(); await page.goto("http://127.0.0.1:4180/");
    if (accountState === "banned") {
      await page.getByRole("heading", { name: "Your professional workspace" }).waitFor();
      await page.getByText("This account no longer has access.").waitFor();
      assert.equal(await page.evaluate(() => sessionStorage.getItem("captro.studio.access")), null);
    } else if (accountState === "business_only") {
      await page.getByLabel("Workspace", { exact: true }).selectOption("business");
      assert.equal(await page.locator('select[aria-label="Workspace"] option').count(), 1);
      assert.equal(await page.getByRole("button", { name: "Support", exact: true }).count(), 0);
      assert.ok(!paths.some(p => p.includes("/earnings")));
      revoked = true; await page.evaluate(() => window.dispatchEvent(new Event("focus")));
      await page.getByText("This account no longer has access.").waitFor();
      assert.equal(await page.getByRole("button", { name: "Save storefront" }).count(), 0);
    } else {
      await page.getByRole("heading", { name: "Approval required" }).waitFor();
      assert.ok(!paths.some(p => p.includes("/business-owner/") || p.includes("/earnings")));
    }
    tests++; await context.close();
  }
  console.log(
    `PASS ${tests} Studio browser checks across desktop and mobile; screenshots: ${output}`,
  );
} finally {
  await browser.close();
}
