import assert from "node:assert/strict";
import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "msedge", headless: true });
try {
  const page = await browser.newPage();
  await page.goto("http://127.0.0.1:4180/");
  const result = await page.evaluate(async () => {
    const auth = await import("/src/api.ts");
    const originalFetch = window.fetch;
    const calls = [];
    const response = (status, data) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
    let releaseOld, notifyOld;
    const started = new Promise(resolve => { notifyOld = resolve; });
    window.fetch = async (url, options) => {
      const path = new URL(url).pathname;
      calls.push({ path, token: options.headers.Authorization });
      if (path.endsWith("/auth/login")) return response(200, { access_token: "new-user", refresh_token: "new-refresh" });
      if (path.endsWith("/auth/refresh")) return response(200, { access_token: "new-refreshed", refresh_token: "new-refresh" });
      if (calls.filter(c => c.path.endsWith("/action")).length === 1) {
        notifyOld(); return new Promise(resolve => { releaseOld = () => resolve(response(401, { detail: "Expired" })); });
      }
      return response(200, { status: "accepted" });
    };
    try {
      auth.clearSession(); sessionStorage.setItem("captro.studio.access", "old-user"); sessionStorage.setItem("captro.studio.refresh", "old-refresh");
      const old = auth.api("/business-orders/fixture/action", { action: "accept" }).then(() => 200, e => e.status);
      await started;
      auth.clearSession(); await auth.login("new@example.invalid", "fixture-only");
      releaseOld();
      return { status: await old, calls, token: auth.session() };
    } finally { auth.clearSession(); window.fetch = originalFetch; }
  });
  assert.equal(result.status, 409, "Old account operation is rejected");
  assert.equal(result.calls.filter(c => c.path.endsWith("/action")).length, 1, "An old mutation must never replay as the newly signed-in user");
  assert.equal(result.calls.filter(c => c.path.endsWith("/auth/refresh")).length, 0, "An old 401 must not refresh the new account");
  assert.equal(result.token, "new-user");
  const shared = await page.evaluate(async () => {
    const auth = await import("/src/api.ts"), originalFetch = window.fetch;
    const calls = [];
    const response = (status, data) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
    let releaseOld, releaseRefresh, notifyOld, notifyRefresh;
    const oldStarted = new Promise(resolve => { notifyOld = resolve; });
    const refreshStarted = new Promise(resolve => { notifyRefresh = resolve; });
    let reads = 0;
    window.fetch = async (url, options) => {
      const path = new URL(url).pathname; calls.push({ path, token: options.headers.Authorization });
      if (path.endsWith("/action") && calls.filter(c => c.path.endsWith("/action")).length === 1) {
        notifyOld(); return new Promise(resolve => { releaseOld = () => resolve(response(401, {})); });
      }
      if (path.endsWith("/auth/login")) return response(200, { access_token: "new-user", refresh_token: "new-refresh" });
      if (path.endsWith("/auth/refresh")) {
        notifyRefresh(); return new Promise(resolve => { releaseRefresh = () => resolve(response(200, { access_token: "new-refreshed" })); });
      }
      if (path.endsWith("/professional/me") && reads++ === 0) return response(401, {});
      return response(200, {});
    };
    try {
      auth.clearSession(); sessionStorage.setItem("captro.studio.access", "old-user"); sessionStorage.setItem("captro.studio.refresh", "old-refresh");
      const old = auth.api("/business-orders/fixture/action", { action: "accept" }).then(() => 200, e => e.status);
      await oldStarted; auth.clearSession(); await auth.login("new@example.invalid", "fixture-only");
      const current = auth.api("/professional/me"); await refreshStarted;
      releaseOld();
      // Flush the old response while the new account's refresh remains in flight.
      await new Promise(resolve => setTimeout(resolve, 0));
      releaseRefresh(); await current;
      return { status: await old, calls, token: auth.session() };
    } finally { auth.clearSession(); window.fetch = originalFetch; }
  });
  assert.equal(shared.status, 409);
  assert.equal(shared.calls.filter(c => c.path.endsWith("/action")).length, 1, "Old mutation cannot join the new account's shared refresh and replay");
  assert.equal(shared.token, "new-refreshed");
  for (const transient of [false, true]) {
    const refreshed = await page.evaluate(async transient => {
      const auth = await import("/src/api.ts"), originalFetch = window.fetch;
      const response = (status, data) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
      let refreshes = 0, reads = 0, release, notify;
      const started = new Promise(resolve => { notify = resolve; });
      window.fetch = async (url, options) => {
        if (new URL(url).pathname.endsWith("/auth/refresh")) {
          refreshes++; notify();
          return new Promise(resolve => { release = () => resolve(response(transient ? 503 : 200, transient ? { detail: "Temporary outage" } : { access_token: "fresh-token" })); });
        }
        reads++; return response(options.headers.Authorization === "Bearer fresh-token" ? 200 : 401, {});
      };
      try {
        auth.clearSession(); sessionStorage.setItem("captro.studio.access", "expired-token"); sessionStorage.setItem("captro.studio.refresh", "valid-refresh");
        const requests = [auth.api("/professional/me"), auth.api("/auth/me")].map(p => p.then(() => 200, e => e.status));
        await started; await new Promise(resolve => setTimeout(resolve, 0)); release();
        return { outcomes: await Promise.all(requests), refreshes, reads, access: auth.session(), refresh: sessionStorage.getItem("captro.studio.refresh") };
      } finally { auth.clearSession(); window.fetch = originalFetch; }
    }, transient);
    assert.equal(refreshed.refreshes, 1, "Concurrent failures share one refresh");
    assert.deepEqual(refreshed.outcomes, transient ? [503, 503] : [200, 200]);
    assert.equal(refreshed.reads, transient ? 2 : 4);
    assert.equal(refreshed.access, transient ? "expired-token" : "fresh-token");
    assert.equal(refreshed.refresh, "valid-refresh", "Temporary outages preserve the stored credential");
  }
  console.log("PASS 4 Studio session checks: delayed 401, account switch during shared refresh, coalescing, retryable outage");
} finally { await browser.close(); }
