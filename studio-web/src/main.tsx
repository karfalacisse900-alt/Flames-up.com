import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  api,
  session,
  clearSession,
  login,
  exchange,
  logout,
  type Professional,
} from "./api";
import { Business } from "./Business";
import { Creator, PublicProfileForm } from "./Creator";
import "./style.css";

function App() {
  const [signedIn, setSignedIn] = useState(!!session()),
    [me, setMe] = useState<{
      id: string;
      full_name?: string;
      username?: string;
    }>(),
    [state, setState] = useState<Professional>(),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [revision, setRevision] = useState(0);
  const [workspace, setWorkspace] = useState(
      new URLSearchParams(location.search).get("workspace") || "creator",
    ),
    [page, setPage] = useState("Workspace");
  useEffect(() => {
    const handoff = new URLSearchParams(location.hash.slice(1)).get("handoff");
    if (handoff) {
      history.replaceState(null, "", location.pathname + location.search);
      clearSession();
      setSignedIn(false);
      setBusy(true);
      exchange(handoff)
        .then(() => setSignedIn(true))
        .catch((e) => setError(e.message))
        .finally(() => setBusy(false));
    }
  }, []);
  useEffect(() => {
    if (!signedIn) return;
    let alive = true;
    setBusy(true);
    setError("");
    Promise.all([
      api<{ id: string; full_name?: string; username?: string }>("/auth/me"),
      api<Professional>("/professional/me"),
    ])
      .then(([user, result]) => {
        if (alive) {
          setMe(user);
          setState(result);
          if (
            !result.roles.some((r) => r.role === workspace) &&
            result.roles[0]
          )
            setWorkspace(result.roles[0].role);
        }
      })
      .catch((e) => {
        if (alive) {
          setError(e.message);
          if (e.status === 401 || e.status === 403) {
            clearSession();
            setSignedIn(false);
            setMe(undefined);
            setState(undefined);
          }
        }
      })
      .finally(() => {
        if (alive) setBusy(false);
      });
    return () => {
      alive = false;
    };
  }, [signedIn, revision]);
  useEffect(() => {
    if (!signedIn) return;
    const refresh = () => {
      if (document.visibilityState === "visible") setRevision((r) => r + 1);
    };
    window.addEventListener("focus", refresh);
    const timer = setInterval(refresh, 30000);
    return () => {
      window.removeEventListener("focus", refresh);
      clearInterval(timer);
    };
  }, [signedIn]);
  async function signOut() {
    try { await logout(); }
    catch { /* Local credentials are cleared even if the server is offline. */ }
    finally {
      setSignedIn(false); setMe(undefined); setState(undefined); setError("");
    }
  }
  const role = state?.roles.find((r) => r.role === workspace);
  if (!signedIn)
    return (
      <main className="login">
        <div className="brand">
          <img src="/brand/captro-lockup-black.svg" alt="Captro" />
          <span>Studio</span>
        </div>
        <h1>Your professional workspace</h1>
        <p>
          Sign in with your existing Captro account. Approved creators and
          businesses can also open Studio securely from iPhone Settings.
        </p>
        <Login
          busy={busy}
          setBusy={setBusy}
          ready={() => setSignedIn(true)}
          error={error}
          setError={setError}
        />
        <p className="quiet">
          Apple or Google account? Open Captro → Settings → Professional
          accounts → Open Captro Studio. No second account is needed.
        </p>
      </main>
    );
  return (
    <div className="studio">
      <a className="skip" href="#workspace">
        Skip to workspace
      </a>
      <aside className="sidebar">
        <div className="brand">
          <img src="/brand/captro-lockup-black.svg" alt="Captro" />
          <span>Studio</span>
        </div>
        <label>
          Workspace
          <select
            aria-label="Workspace"
            value={workspace}
            onChange={(e) => {
              setWorkspace(e.target.value);
              setPage("Workspace");
              const url = new URL(location.href);
              url.searchParams.set("workspace", e.target.value);
              history.replaceState(null, "", url);
            }}
          >
            {state?.roles.map((r) => (
              <option key={r.role} value={r.role}>
                {r.role === "creator" ? "Creator / Gig" : "Business"}
              </option>
            ))}
          </select>
        </label>
        <nav aria-label="Studio navigation">
          {["Workspace", "Profile"].map((p) => (
            <button
              key={p}
              aria-current={page === p ? "page" : undefined}
              onClick={() => setPage(p)}
            >
              {p === "Workspace"
                ? workspace === "creator"
                  ? "Work & Support"
                  : "Storefront & orders"
                : "Public information"}
            </button>
          ))}
        </nav>
        <div className="sidebar-footer">
          <strong>{me?.full_name || me?.username || "Captro account"}</strong>
          <button onClick={() => void signOut()}>Sign out</button>
        </div>
      </aside>
      <main id="workspace" className="workspace" tabIndex={-1}>
        <div className="topbar">
          <span>
            {workspace === "creator" ? "Creator / Gig" : "Business"} / {page}
          </span>
          <span>Captro Studio</span>
        </div>
        {error && (
          <p role="alert" className="notice error">
            {error}{" "}
            <button onClick={() => setRevision((r) => r + 1)}>Retry</button>
          </p>
        )}
        {busy && !state && <p role="status">Loading your workspace…</p>}
        {state && !state.roles.length && (
          <section className="panel">
            <h1>Approval required</h1>
            <p>
              Apply for Creator / Gig or Business in Captro’s iPhone Settings.
              Submitting an application does not activate a workspace.
            </p>
          </section>
        )}
        {role && me && (
          <div key={me.id + role.role}>
            {role.status !== "active" && (
              <p className="notice" role="status">
                Your {role.role} role is {role.status}. Public editing and new
                commerce are unavailable. Existing records and order resolution
                remain accessible. {role.status_message}
              </p>
            )}
            {page === "Profile" ? (
              <PublicProfileForm
                key={role.role + role.version}
                role={role}
                saved={() => setRevision((r) => r + 1)}
              />
            ) : role.role === "business" ? (
              <Business role={role} />
            ) : (
              <Creator
                role={role}
                userID={me.id}
                saved={() => setRevision((r) => r + 1)}
              />
            )}
          </div>
        )}
      </main>
    </div>
  );
}
function Login({
  busy,
  setBusy,
  ready,
  error,
  setError,
}: {
  busy: boolean;
  setBusy: (v: boolean) => void;
  ready: () => void;
  error: string;
  setError: (v: string) => void;
}) {
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState("");
  return (
    <form
      className="form"
      onSubmit={async (e) => {
        e.preventDefault();
        if (busy) return;
        setBusy(true);
        setError("");
        try {
          await login(email, password);
          setPassword("");
          ready();
        } catch (e) {
          setError((e as Error).message);
        } finally {
          setBusy(false);
        }
      }}
    >
      <label>
        Email
        <input
          required
          type="email"
          autoComplete="username"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </label>
      <label>
        Password
        <input
          required
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </label>
      <button className="primary" disabled={busy}>
        {busy ? "Signing in…" : "Sign in"}
      </button>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </form>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
