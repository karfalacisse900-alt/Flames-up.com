import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { AdminApi, ApiError, request } from "./api";
import type {
  AdminSession,
  ReportDetail,
  ReportSummary,
  Paginated,
  AdminMedia,
} from "./types";
import {
  sections,
  readConsoleURL,
  safePreviewURL,
  type ConsoleSection,
} from "./console-state";
import { FinancePage } from "./FinancePage";
import "./console.css";

type Row = Record<string, unknown>;
type Case = ReportDetail & { admin_version?: number; assigned_to?: string };
type Operation = {
  id: string;
  action: string;
  target: string;
  version: number;
  reason: string;
  note?: string;
  assignee?: string;
  hours?: number;
  scope?: string;
  role?: string;
  duplicate_of?: string;
};
const can = (s: AdminSession, p: string) =>
  s.permissions.includes("*") || s.permissions.includes(p);
const label = (v: unknown) =>
  String(v ?? "")
    .replaceAll("_", " ")
    .replace(/^./, (x) => x.toUpperCase());
const date = (v: unknown) =>
  v && Number.isFinite(Date.parse(String(v)))
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(String(v)),
      )
    : "Not provided";
const text = (v: unknown) => (typeof v === "string" ? v : "");
const short = (v: unknown) =>
  text(v).length > 14 ? `${text(v).slice(0, 8)}…` : text(v);

export function Icon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    home: (
      <>
        <path d="m3 10 9-7 9 7v11H3Z" />
        <path d="M9 21v-8h6v8" />
      </>
    ),
    report: (
      <>
        <path d="M6 2h9l4 4v16H6Z" />
        <path d="M14 2v5h5M9 11h7M9 15h7M9 19h4" />
      </>
    ),
    users: (
      <>
        <circle cx="12" cy="7" r="4" />
        <path d="M3 21v-3a9 6 0 0 1 18 0v3Z" />
      </>
    ),
    image: (
      <>
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <circle cx="9" cy="8" r="2" />
        <path d="m3 18 6-6 4 4 4-5 4 5" />
      </>
    ),
    play: (
      <>
        <rect x="2" y="4" width="20" height="16" rx="3" />
        <path d="m10 8 6 4-6 4Z" />
      </>
    ),
    calendar: (
      <>
        <rect x="3" y="5" width="18" height="16" rx="2" />
        <path d="M7 2v6M17 2v6M3 11h18" />
      </>
    ),
    appeal: (
      <>
        <path d="M12 2v20M6 22h12M3 6h18M5 6l-4 8h8ZM19 6l-4 8h8Z" />
      </>
    ),
    shield: (
      <>
        <path d="m12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6Z" />
        <path d="m8 12 3 3 5-6" />
      </>
    ),
    history: (
      <>
        <rect x="4" y="2" width="13" height="19" rx="1" />
        <path d="M7 6h7M7 10h7M7 14h3" />
        <circle cx="18" cy="18" r="4" />
        <path d="M18 16v3h2" />
      </>
    ),
    settings: (
      <>
        <path d="m9 2-1 3-3 1-3 5 2 2v4l5 4 3-1 3 1 5-4v-4l2-2-3-5-3-1-1-3Z" />
        <circle cx="12" cy="12" r="4" />
      </>
    ),
    search: (
      <>
        <circle cx="10" cy="10" r="7" />
        <path d="m15 15 6 6" />
      </>
    ),
    alert: (
      <>
        <path d="m12 3 10 18H2Z" />
        <path d="M12 9v5M12 17v1" />
      </>
    ),
    clock: (
      <>
        <circle cx="12" cy="12" r="10" />
        <path d="M12 6v7l5 3" />
      </>
    ),
    filter: <path d="M3 3h18l-7 9v8l-4-2v-6Z" />,
    close: <path d="m6 6 12 12M18 6 6 18" />,
  };
  return (
    <svg
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.65"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name] || paths.report}
    </svg>
  );
}

function useLoad<T>(load: () => Promise<T>, key: string, enabled = true) {
  const [state, set] = useState<{
    key: string;
    data?: T;
    error?: string;
    loading: boolean;
  }>({ key, loading: enabled });
  const generation = useRef(0);
  const latest = useRef(load);
  latest.current = load;
  const reload = useCallback(async () => {
    const id = ++generation.current;
    if (!enabled) {
      set({ key, loading: false });
      return;
    }
    set((s) => ({ ...s, key, loading: true, error: undefined }));
    try {
      const data = await latest.current();
      if (id === generation.current) set({ key, data, loading: false });
    } catch (e) {
      if (id === generation.current)
        set((s) => ({
          ...s,
          key,
          loading: false,
          error: e instanceof Error ? e.message : "Unable to load.",
        }));
    }
  }, [key, enabled]);
  useEffect(() => {
    set({ key, loading: enabled });
    void reload();
    return () => {
      generation.current++;
    };
  }, [reload, enabled]);
  return {
    ...(state.key === key
      ? state
      : { loading: enabled, data: undefined, error: undefined }),
    reload,
  };
}
function ErrorState({
  message,
  retry,
}: {
  message: string;
  retry: () => void;
}) {
  return (
    <div className="console-error" role="alert">
      <strong>
        {/permission|access required|forbidden/i.test(message)
          ? "Access restricted"
          : "Unable to load"}
      </strong>
      <p>{message}</p>
      <button className="secondary-button" onClick={retry}>
        Retry
      </button>
    </div>
  );
}
function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="console-empty">
      <Icon name="report" />
      <h3>{title}</h3>
      <p>{children}</p>
    </div>
  );
}
function Loading() {
  return (
    <div className="console-loading" role="status">
      Loading…
      <div />
      <div />
      <div />
    </div>
  );
}
function Badge({ value }: { value: unknown }) {
  return (
    <span className={`console-badge state-${text(value)}`}>
      {label(value) || "Unknown"}
    </span>
  );
}
function Preview({
  media,
  large = false,
}: {
  media?: AdminMedia | null;
  large?: boolean;
}) {
  const source = safePreviewURL(
    media?.thumbnail_url ||
      media?.thumbnailUrl ||
      media?.poster_url ||
      media?.posterUrl ||
      media?.feed_media_url ||
      media?.feedUrl,
  );
  return (
    <PreviewResource
      key={source}
      source={source}
      video={(media?.media_type || media?.type) === "video"}
      large={large}
    />
  );
}
function PreviewResource({
  source,
  large,
  video,
}: {
  source: string;
  large: boolean;
  video: boolean;
}) {
  const [state, set] = useState("loading");
  const [attempt, retry] = useState(0);
  useEffect(() => {
    if (state !== "loading" || !source) return;
    const timer = setTimeout(() => set("failed"), 15000);
    return () => clearTimeout(timer);
  }, [state, source, attempt]);
  return (
    <div className={`console-preview ${large ? "large" : ""}`}>
      {source && state !== "failed" ? (
        <img
          key={`${source}:${attempt}`}
          src={source}
          alt={large ? "Reported content preview" : ""}
          onLoad={() => set("loaded")}
          onError={() => set("failed")}
          referrerPolicy="no-referrer"
        />
      ) : null}
      {!source || state !== "loaded" ? (
        <div className="preview-status">
          <Icon name={video ? "play" : "image"} />
          {large ? (
            <span>
              {!source
                ? "Preview unavailable"
                : state === "failed"
                  ? "Preview could not load"
                  : "Loading preview…"}
            </span>
          ) : null}
          {large && state === "failed" ? (
            <button
              onClick={() => {
                set("loading");
                retry((n) => n + 1);
              }}
            >
              Retry preview
            </button>
          ) : null}
        </div>
      ) : null}
      {large && source ? (
        <span className="preview-kind">{video ? "Video poster" : "Photo"}</span>
      ) : null}
    </div>
  );
}

function Confirmation({
  token,
  action,
  target,
  version,
  onClose,
  onDone,
  initialNote = "",
}: {
  token: string;
  action: string;
  target: string;
  version: number;
  onClose: () => void;
  onDone: () => void;
  initialNote?: string;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const busyRef = useRef(false);
  const pending = useRef<Operation | null>(null);
  const [reason, setReason] = useState("");
  const [note, setNote] = useState(initialNote);
  const [extra, setExtra] = useState("");
  const [scope, setScope] = useState(action === "role" ? "" : "posting");
  const [hours, setHours] = useState(24);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [ambiguous, setAmbiguous] = useState(false);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    dialog.current?.showModal();
    return () => previous?.focus();
  }, []);
  async function submit() {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    const op = pending.current ?? {
      id: crypto.randomUUID(),
      action,
      target,
      version,
      reason: reason.trim(),
      note: note.trim(),
      assignee: action === "assign" ? extra : undefined,
      duplicate_of: action === "duplicate" ? extra : undefined,
      role: action === "role" ? scope : undefined,
      scope,
      hours,
    };
    pending.current = op;
    try {
      let result: { ok: boolean; code?: string } | undefined;
      if (ambiguous) {
        try {
          result = await request(`/admin/console/operations/${op.id}`, token);
        } catch (e) {
          if (!(e instanceof ApiError && e.status === 404)) throw e;
        }
      }
      if (!result)
        result = await request("/admin/console/operations", token, {
          method: "POST",
          body: JSON.stringify(op),
        });
      if (!result?.ok)
        throw new ApiError(
          label(result?.code) || "Operation not confirmed.",
          409,
        );
      onDone();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action not confirmed.");
      const uncertain =
        !(e instanceof ApiError) ||
        [0, 408, 500, 502, 503, 504].includes(e.status);
      setAmbiguous(uncertain);
      if (!uncertain) pending.current = null;
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  return (
    <dialog
      className="console-dialog"
      ref={dialog}
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) onClose();
      }}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <div className="inspector-heading">
          <h2>
            {label(action)} {action.startsWith("appeal") ? "" : "action"}
          </h2>
          <button
            type="button"
            className="icon-button"
            aria-label="Close confirmation"
            disabled={busy}
            onClick={onClose}
          >
            <Icon name="close" />
          </button>
        </div>
        <p>
          Target <code>{target}</code>. This action takes effect only after
          server confirmation.
        </p>
        <fieldset disabled={busy || ambiguous}>
          <label>
            Reason{" "}
            {["warn", "suspend", "ban", "reinstate", "appeal_uphold"].includes(
              action,
            )
              ? "(visible to the affected user)"
              : ""}
            <textarea
              required
              minLength={3}
              maxLength={800}
              autoFocus
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </label>
          <label>
            Internal note
            <textarea
              maxLength={2000}
              required={action === "note"}
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </label>
          {["assign", "duplicate"].includes(action) ? (
            <label>
              {action === "assign"
                ? "Administrator ID (leave blank to unassign)"
                : "Original report ID"}
              <input value={extra} onChange={(e) => setExtra(e.target.value)} />
            </label>
          ) : null}
          {["restrict", "suspend"].includes(action) ? (
            <label>
              Duration (hours)
              <input
                type="number"
                min="1"
                max="2160"
                value={hours}
                onChange={(e) => setHours(Number(e.target.value))}
              />
            </label>
          ) : null}
          {["restrict", "role"].includes(action) ? (
            <label>
              {action === "role" ? "Access role" : "Restricted capability"}
              <select value={scope} onChange={(e) => setScope(e.target.value)}>
                <option value="">Select…</option>
                {(action === "role"
                  ? ["owner", "moderator", "support", "none"]
                  : ["posting", "commenting", "messaging", "commerce", "all"]
                ).map((x) => (
                  <option key={x}>{x}</option>
                ))}
              </select>
            </label>
          ) : null}
        </fieldset>
        {error ? (
          <p role="alert" className="console-error">
            {error}
            {ambiguous
              ? " The outcome is not yet confirmed. Check its status before retrying."
              : ""}
          </p>
        ) : null}
        <div className="dialog-actions">
          <button
            type="button"
            className="secondary-button"
            disabled={busy}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            className="primary-button"
            disabled={busy || reason.trim().length < 3}
          >
            {busy
              ? "Checking…"
              : ambiguous
                ? "Check operation status"
                : "Confirm action"}
          </button>
        </div>
      </form>
    </dialog>
  );
}

function Summary({ token }: { token: string }) {
  const query = useLoad(
    () =>
      request<{
        cards: Record<string, number | null>;
        errors: Record<string, string>;
      }>("/admin/console-summary", token),
    token,
  );
  return (
    <div className="console-metrics">
      {[
        ["open_reports", "Open reports", "report"],
        ["high_priority", "High priority", "alert"],
        ["in_review", "In review", "clock"],
        ["appeals", "Appeals", "appeal"],
      ].map(([key, title, icon]) => (
        <article key={key} className={`summary-${key}`}>
          <div>
            <strong>
              {query.loading ? "—" : (query.data?.cards[key] ?? "—")}
            </strong>
            <span>{title}</span>
            {!query.loading && (query.error || query.data?.errors[key]) ? (
              <button onClick={() => void query.reload()}>
                Unavailable · Retry
              </button>
            ) : null}
          </div>
          <Icon name={icon} />
        </article>
      ))}
    </div>
  );
}

function Reports({
  token,
  session,
  params,
  navigate,
}: {
  token: string;
  session: AdminSession;
  params: URLSearchParams;
  navigate: (changes: Record<string, string>) => void;
}) {
  const selected = params.get("case") || "";
  const status = params.get("status") || "open";
  const offset = Number(params.get("offset")) || 0;
  const query = new URLSearchParams({
    status,
    limit: "25",
    offset: String(offset),
  });
  ["search", "priority", "assigned", "target_type", "sort"].forEach((k) => {
    if (params.get(k)) query.set(k, params.get(k)!);
  });
  const list = useLoad(
    () => AdminApi.reports(token, `?${query}`),
    `${token}:${query}`,
  );
  const detail = useLoad(
    () => AdminApi.report(token, selected) as Promise<{ report: Case }>,
    `${token}:${selected}`,
    !!selected,
  );
  const [filters, setFilters] = useState(false);
  const [action, setAction] = useState("");
  const [notice, setNotice] = useState("");
  const [draftNotes, setDraftNotes] = useState<Record<string, string>>({});
  const report = detail.data?.report;
  return (
    <>
      <Summary token={token} />
      <div className="case-workspace">
        <section className="console-panel queue" aria-label="Report queue">
          <div className="queue-toolbar">
            <div className="queue-tabs">
              {[
                ["open", "All open"],
                ["unassigned", "Unassigned"],
                ["under_review", "In review"],
              ].map(([value, name]) => (
                <button
                  key={value}
                  aria-pressed={
                    value === "unassigned"
                      ? params.get("assigned") === "none"
                      : status === value && params.get("assigned") !== "none"
                  }
                  onClick={() =>
                    navigate({
                      status: value === "unassigned" ? "open" : value,
                      assigned: value === "unassigned" ? "none" : "",
                      offset: "0",
                    })
                  }
                >
                  {name}
                </button>
              ))}
            </div>
            <button
              className="secondary-button"
              aria-expanded={filters}
              onClick={() => setFilters((x) => !x)}
            >
              <Icon name="filter" />
              Filter
            </button>
          </div>
          {filters ? (
            <div className="queue-filters">
              <label>
                Status
                <select
                  aria-label="Status"
                  value={status}
                  onChange={(e) =>
                    navigate({ status: e.target.value, offset: "0" })
                  }
                >
                  {[
                    "open",
                    "all",
                    "under_review",
                    "escalated",
                    "dismissed",
                    "action_taken",
                  ].map((x) => (
                    <option key={x} value={x}>
                      {label(x)}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Priority
                <select
                  aria-label="Priority"
                  value={params.get("priority") || ""}
                  onChange={(e) =>
                    navigate({ priority: e.target.value, offset: "0" })
                  }
                >
                  <option value="">All priorities</option>
                  {["urgent", "high", "medium", "normal", "low"].map((x) => (
                    <option key={x}>{x}</option>
                  ))}
                </select>
              </label>
              <label>
                Order
                <select
                  aria-label="Order"
                  value={params.get("sort") || "newest"}
                  onChange={(e) =>
                    navigate({ sort: e.target.value, offset: "0" })
                  }
                >
                  <option value="newest">Newest first</option>
                  <option value="oldest">Oldest first</option>
                </select>
              </label>
            </div>
          ) : null}
          <div className="report-columns" aria-hidden="true">
            <span>Content</span>
            <span>Reason</span>
            <span>Priority</span>
            <span>Status</span>
          </div>
          {list.error ? (
            <ErrorState message={list.error} retry={() => void list.reload()} />
          ) : null}
          {list.loading && !list.data ? (
            <Loading />
          ) : list.data?.results.length ? (
            <div aria-busy={list.loading}>
              {list.data.results.map((r: ReportSummary) => (
                <button
                  className={`case-row ${selected === r.id ? "selected" : ""}`}
                  key={r.id}
                  onClick={() => navigate({ case: r.id })}
                  aria-label={`Open report ${r.id}: ${r.preview || label(r.reason)}`}
                  aria-current={selected === r.id ? "true" : undefined}
                >
                  <div className="case-content">
                    <Preview media={r.target_media} />
                    <div>
                      <strong>
                        {r.preview || label(r.target_type) + " report"}
                      </strong>
                      <span>
                        {label(r.target_type)} by @
                        {r.target_user.username || "unavailable"}
                      </span>
                      <time>{date(r.created_at)}</time>
                    </div>
                  </div>
                  <span className="case-reason">{label(r.reason)}</span>
                  <span className={`priority priority-${r.priority}`}>
                    <i />
                    {label(r.priority)}
                  </span>
                  <Badge value={r.status} />
                </button>
              ))}
            </div>
          ) : !list.error && !list.loading ? (
            <Empty title="No matching reports">
              Try a different filter. Reports do not automatically establish a
              violation.
            </Empty>
          ) : null}
          <Pager
            offset={offset}
            hasNext={(list.data?.results.length || 0) === 25}
            onChange={(n) => navigate({ offset: String(n) })}
            disabled={list.loading}
          />
        </section>
        <aside
          className="console-panel case-inspector"
          aria-label="Case inspector"
        >
          {detail.error ? (
            <ErrorState
              message={detail.error}
              retry={() => void detail.reload()}
            />
          ) : detail.loading ? (
            <Loading />
          ) : report ? (
            <>
              <div className="inspector-heading">
                <h2 title={report.id}>Case #{short(report.id)}</h2>
                <Badge value={report.status} />
                <button
                  className="icon-button"
                  aria-label="Close case"
                  onClick={() => navigate({ case: "" })}
                >
                  <Icon name="close" />
                </button>
              </div>
              <Preview media={report.target_media} large />
              <div className="creator-line">
                <span className="initial-avatar">
                  {(report.target_user.username || "?")
                    .slice(0, 1)
                    .toUpperCase()}
                </span>
                <div>
                  <strong>
                    @{report.target_user.username || "Unavailable account"}
                  </strong>
                  <span>
                    {label(report.target_type)} · {date(report.created_at)}
                  </span>
                </div>
              </div>
              {report.target?.missing ? (
                <p className="muted">
                  The original target is unavailable. The report and history
                  remain.
                </p>
              ) : null}
              <div className="case-facts">
                <strong>Reason</strong>
                <p>{label(report.reason)}</p>
              </div>
              {can(session, "reports:write") ? (
                <label className="inspector-note">
                  Internal note
                  <textarea
                    rows={2}
                    maxLength={2000}
                    placeholder="Add a note for your team…"
                    value={draftNotes[report.id] || ""}
                    onChange={(e) =>
                      setDraftNotes((s) => ({
                        ...s,
                        [report.id]: e.target.value,
                      }))
                    }
                  />
                </label>
              ) : null}
              {can(session, "reports:write") ? (
                <>
                  <div className="case-buttons">
                    <button
                      className="primary-button"
                      onClick={() => setAction("review")}
                    >
                      Review action
                    </button>
                    <button
                      className="secondary-button"
                      onClick={() => setAction("dismiss")}
                    >
                      Dismiss report
                    </button>
                  </div>
                  <div className="secondary-actions">
                    {[
                      ["note", "Add internal note"],
                      ["assign", "Assign"],
                      ["escalate", "Escalate"],
                      ["duplicate", "Group duplicate"],
                      ["resolve", "Resolve case"],
                    ].map(([a, l]) => (
                      <button key={a} onClick={() => setAction(a)}>
                        {l}
                      </button>
                    ))}
                  </div>
                </>
              ) : (
                <p className="read-only-note">
                  Read-only access. Case changes require a moderator.
                </p>
              )}
              <p className="quiet-note">
                Actions require a reason and confirmation. Resolving a case does
                not remove its content.
              </p>
              <div className="inspector-links">
                <button
                  onClick={() =>
                    navigate({
                      section: "users",
                      user:
                        report.target_owner_user_id || report.target_user.id,
                    })
                  }
                >
                  View account
                </button>
                <button
                  onClick={() =>
                    navigate({ section: "audit", search: report.target_id })
                  }
                >
                  View history
                </button>
              </div>
              <details className="case-history">
                <summary>Assignment, evidence & decision history</summary>
                <p>Assigned to: {report.assigned_to || "Unassigned"}</p>
                <p>{report.details}</p>
                {report.notes?.length ? (
                  report.notes.map((n) => (
                    <article key={n.id}>
                      <strong>
                        {n.admin?.username || "Administrator"} ·{" "}
                        {date(n.created_at)}
                      </strong>
                      <p>{n.note}</p>
                    </article>
                  ))
                ) : (
                  <p>No internal notes.</p>
                )}
                {report.previous_actions?.map((a) => (
                  <article key={a.id}>
                    <strong>{label(a.action_type)}</strong>
                    <p>{a.reason}</p>
                    <time>{date(a.created_at)}</time>
                  </article>
                ))}
              </details>
            </>
          ) : (
            <Empty title="Select a report">
              Review its target, evidence and history here.
            </Empty>
          )}
        </aside>
      </div>
      {notice ? (
        <p role="status" className="console-notice">
          {notice}
        </p>
      ) : null}
      {action && report ? (
        <Confirmation
          key={`${report.id}:${action}`}
          token={token}
          action={action}
          target={report.id}
          version={report.admin_version ?? 0}
          initialNote={draftNotes[report.id] || ""}
          onClose={() => {
            setAction("");
            void detail.reload();
          }}
          onDone={() => {
            setNotice("Case updated.");
            setDraftNotes((s) => ({ ...s, [report.id]: "" }));
            void list.reload();
            void detail.reload();
          }}
        />
      ) : null}
    </>
  );
}
function Pager({
  offset,
  hasNext,
  onChange,
  disabled,
}: {
  offset: number;
  hasNext: boolean;
  onChange: (offset: number) => void;
  disabled?: boolean;
}) {
  return (
    <div className="console-pagination">
      <span>Page {Math.floor(offset / 25) + 1}</span>
      <button
        disabled={disabled || offset === 0}
        onClick={() => onChange(Math.max(0, offset - 25))}
      >
        Previous
      </button>
      <button
        disabled={disabled || !hasNext}
        onClick={() => onChange(offset + 25)}
      >
        Next
      </button>
    </div>
  );
}

const resourceColumns: Record<string, [string, string][]> = {
  users: [
    ["username", "Account"],
    ["full_name", "Name"],
    ["status", "State"],
    ["created_at", "Created"],
  ],
  posts: [
    ["title", "Content"],
    ["category", "Type"],
    ["status", "State"],
    ["created_at", "Created"],
  ],
  media: [
    ["id", "Media ID"],
    ["media_type", "Type"],
    ["moderation_status", "Moderation"],
    ["upload_status", "Upload"],
  ],
  listings: [
    ["title", "Listing"],
    ["content_type", "Type"],
    ["status", "Availability"],
    ["quantity_committed", "Committed"],
    ["capacity", "Capacity"],
  ],
  appeals: [
    ["id", "Appeal"],
    ["decision_id", "Original decision"],
    ["status", "State"],
    ["created_at", "Submitted"],
  ],
  operations: [
    ["id", "Operation"],
    ["actor_id", "Actor"],
    ["result", "Outcome"],
    ["created_at", "Created"],
  ],
  audit: [
    ["action_type", "Action"],
    ["target_type", "Target type"],
    ["target_id", "Target"],
    ["created_at", "Timestamp"],
  ],
  access: [
    ["user_id", "Administrator"],
    ["role", "Server role"],
    ["admin_version", "Version"],
    ["updated_at", "Updated"],
  ],
};
function Records({
  section,
  token,
  session,
  params,
  navigate,
}: {
  section: string;
  token: string;
  session: AdminSession;
  params: URLSearchParams;
  navigate: (c: Record<string, string>) => void;
}) {
  const offset = Number(params.get("offset")) || 0;
  const search = params.get("search") || "";
  const status = params.get("status") || "all";
  const isStories = section === "posts" && params.get("kind") === "stories";
  const q = `?${new URLSearchParams({ offset: String(offset), limit: "25", search, status })}`;
  const endpoint =
    section === "posts"
      ? isStories
        ? "/admin/console/stories"
        : "/admin/posts"
      : section === "users"
        ? "/admin/users"
        : section === "audit"
          ? "/admin/audit-logs"
          : `/admin/console/${section}`;
  const list = useLoad(
    () => request<Paginated<Row>>(endpoint + q, token),
    `${token}:${endpoint}:${q}`,
  );
  const selected = params.get(section === "users" ? "user" : "item") || "";
  const selectedRow = list.data?.results.find(
    (r) => String(r.id || r.user_id) === selected,
  );
  const user = useLoad(
    () => AdminApi.user(token, selected),
    `${token}:${selected}`,
    section === "users" && !!selected,
  );
  const [action, setAction] = useState("");
  const [grantTarget, setGrantTarget] = useState("");
  const row =
    section === "users" ? (user.data?.user as unknown as Row) : selectedRow;
  const columns = isStories
    ? [
        ["id", "Story ID"],
        ["user_id", "Creator"],
        ["media_type", "Type"],
        ["status", "State"],
        ["expires_at", "Expires"],
      ]
    : resourceColumns[section] || [];
  const statusOptions: Record<string, string[]> = {
    users: ["active", "suspended", "banned"],
    posts: ["active", "removed", "deleted"],
    media: ["uploaded", "pending", "approved", "rejected", "failed"],
    listings: ["active", "paused", "sold_out", "expired", "cancelled"],
    appeals: ["open", "in_review", "upheld", "overturned"],
  };
  const descriptions: Record<string, string> = {
    media:
      "Metadata only. Private asset previews require an audited evidence route; storage keys are never exposed.",
    listings:
      "Commercial availability and committed capacity are not moderation decisions. Financial records and entitlements remain unchanged.",
    access:
      "Only the owner can manage access. Changes require recent multi-factor verification; the final owner cannot be removed.",
    appeals:
      "Review independently of the original decision. Restoration is withheld until source-media revocation and restoration are verified.",
    operations:
      "Confirmed and rejected actions, with durable operation IDs. Financial support remains separate and permission-restricted.",
    posts:
      "Content removal, quarantine, restoration and deletion remain gated until delivery/cache revocation is verified. No destructive shortcut is exposed.",
  };
  return (
    <>
      <p className="section-description">{descriptions[section]}</p>
      {section === "posts" ? (
        <div className="secondary-actions">
          <button
            aria-pressed={!isStories}
            onClick={() => navigate({ kind: "", offset: "0", item: "" })}
          >
            Posts
          </button>
          <button
            aria-pressed={isStories}
            onClick={() => navigate({ kind: "stories", offset: "0", item: "" })}
          >
            Stories metadata
          </button>
        </div>
      ) : null}
      {section === "access" && session.role === "owner" ? (
        <form
          className="access-grant"
          onSubmit={(e) => {
            e.preventDefault();
            setAction("role");
          }}
        >
          <label>
            Existing account ID
            <input
              required
              pattern="[A-Za-z0-9_-]{1,160}"
              value={grantTarget}
              onChange={(e) => setGrantTarget(e.target.value)}
              placeholder="Canonical account ID"
            />
          </label>
          <button className="secondary-button">
            Grant administrator access
          </button>
        </form>
      ) : null}
      <div className={`records-layout ${selected ? "with-inspector" : ""}`}>
        <section className="console-panel">
          <div className="records-toolbar">
            <strong>{sections.find((x) => x.key === section)?.label}</strong>
            {statusOptions[section] ? (
              <select
                aria-label="Record status"
                style={{ width: "auto", maxWidth: 180 }}
                value={status}
                onChange={(e) =>
                  navigate({ status: e.target.value, offset: "0" })
                }
              >
                <option value="all">All states</option>
                {statusOptions[section].map((s) => (
                  <option key={s} value={s}>
                    {label(s)}
                  </option>
                ))}
              </select>
            ) : null}
            <button
              className="secondary-button"
              onClick={() => void list.reload()}
            >
              Refresh
            </button>
          </div>
          {list.error ? (
            <ErrorState message={list.error} retry={() => void list.reload()} />
          ) : null}
          {list.loading && !list.data ? (
            <Loading />
          ) : list.data?.results.length ? (
            <div className="records-scroll">
              <table>
                <thead>
                  <tr>
                    {columns.map(([k, l]) => (
                      <th key={k}>{l}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {list.data.results.map((r) => (
                    <tr
                      key={String(r.id || r.user_id)}
                      className={
                        selected === String(r.id || r.user_id) ? "selected" : ""
                      }
                    >
                      {columns.map(([k], index) => (
                        <td key={k}>
                          {index === 0 ? (
                            <button
                              className="record-link"
                              onClick={() =>
                                navigate({
                                  [section === "users" ? "user" : "item"]:
                                    String(r.id || r.user_id),
                                })
                              }
                            >
                              {text(r[k]) ||
                                text(r.content).slice(0, 60) ||
                                short(r.id) ||
                                "Untitled"}
                            </button>
                          ) : k === "result" ? (
                            <Badge
                              value={
                                (r.result as Row)?.ok
                                  ? "confirmed"
                                  : (r.result as Row)?.code || "Unknown"
                              }
                            />
                          ) : k.includes("_at") ? (
                            <time>{date(r[k])}</time>
                          ) : k === "status" ||
                            k === "role" ||
                            k.includes("_status") ? (
                            <Badge value={r[k]} />
                          ) : (
                            String(r[k] ?? "Not set")
                          )}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : !list.error && !list.loading ? (
            <Empty title="No matching records">
              This is an empty result, not a failed query.
            </Empty>
          ) : null}
          <Pager
            offset={offset}
            hasNext={listHasNext(list.data)}
            onChange={(n) => navigate({ offset: String(n) })}
            disabled={list.loading}
          />
        </section>
        {selected ? (
          <aside className="console-panel record-inspector">
            <div className="inspector-heading">
              <h2>Record details</h2>
              <button
                className="icon-button"
                aria-label="Close details"
                onClick={() => navigate({ item: "", user: "" })}
              >
                <Icon name="close" />
              </button>
            </div>
            {user.error && section === "users" ? (
              <ErrorState
                message={user.error}
                retry={() => void user.reload()}
              />
            ) : row ? (
              <>
                <dl>
                  {Object.entries(row)
                    .filter(
                      ([k, v]) =>
                        [
                          "id",
                          "user_id",
                          "username",
                          "full_name",
                          "status",
                          "email",
                          "phone",
                          "role",
                          "title",
                          "statement",
                          "decision_id",
                          "outcome_notice",
                          "creator_app_user_id",
                          "starts_at",
                          "ends_at",
                          "expires_at",
                          "capacity",
                          "quantity_committed",
                          "moderation_status",
                          "upload_status",
                          "width",
                          "height",
                          "mime_type",
                          "reason",
                          "internal_note",
                        ].includes(k) &&
                        v !== null &&
                        v !== "",
                    )
                    .map(([k, v]) => (
                      <div key={k}>
                        <dt>{label(k)}</dt>
                        <dd>{String(v)}</dd>
                      </div>
                    ))}
                </dl>
                {section === "users" ? (
                  <>
                    <h3>Moderation</h3>
                    <div className="secondary-actions">
                      {[
                        ["warn", "users:warn"],
                        ["restrict", "users:restrict"],
                        ["suspend", "users:suspend"],
                        ["ban", "users:ban"],
                        ["reinstate", "users:ban"],
                      ]
                        .filter(([, p]) => can(session, p))
                        .map(([a]) => (
                          <button key={a} onClick={() => setAction(a)}>
                            {label(a)}
                          </button>
                        ))}
                    </div>
                    <h3>Recent public content</h3>
                    {user.data?.recent_posts.map((p) => (
                      <p key={p.id}>
                        {p.title || p.content || "Media post"} ·{" "}
                        {label(p.status)}
                      </p>
                    ))}
                    <h3>Moderation history</h3>
                    {user.data?.actions.map((a) => (
                      <p key={a.id}>
                        {label(a.action_type)} · {date(a.created_at)}
                      </p>
                    ))}
                  </>
                ) : null}
                {section === "access" && session.role === "owner" ? (
                  <button
                    className="secondary-button"
                    onClick={() => {
                      setGrantTarget("");
                      setAction("role");
                    }}
                  >
                    Change access
                  </button>
                ) : null}
                {section === "appeals" && can(session, "reports:write") ? (
                  <div className="secondary-actions">
                    <button onClick={() => setAction("appeal_review")}>
                      Begin independent review
                    </button>
                    <button onClick={() => setAction("appeal_uphold")}>
                      Uphold decision
                    </button>
                    <button
                      disabled
                      title="Source-media restoration acceptance is required."
                    >
                      Overturn & restore (not enabled)
                    </button>
                  </div>
                ) : null}
              </>
            ) : user.loading ? (
              <Loading />
            ) : (
              <Empty title="Record not on this page">
                Return to the list or retry the account lookup.
              </Empty>
            )}
          </aside>
        ) : null}
      </div>
      {action && (row || grantTarget) ? (
        <Confirmation
          token={token}
          action={action}
          target={grantTarget || selected}
          version={grantTarget ? 0 : Number(row?.admin_version || 0)}
          onClose={() => {
            setAction("");
            setGrantTarget("");
            void user.reload();
          }}
          onDone={() => {
            void list.reload();
            void user.reload();
          }}
        />
      ) : null}
    </>
  );
}
function listHasNext(data?: Paginated<Row>) {
  return (
    data?.pagination?.next_offset !== null && (data?.results.length || 0) === 25
  );
}

export function Console({
  token,
  session,
  onLogout,
}: {
  token: string;
  session: AdminSession;
  onLogout: () => void;
}) {
  const [url, setURL] = useState(() => readConsoleURL(location.search));
  const [search, setSearch] = useState(url.params.get("search") || "");
  const [sessionError, setSessionError] = useState("");
  const scrollPositions = useRef<Record<string, number>>({});
  const main = useRef<HTMLElement>(null);
  const navigate = useCallback((changes: Record<string, string>) => {
    const p = new URLSearchParams(location.search);
    if (changes.section && changes.section !== p.get("section")) {
      scrollPositions.current[p.get("section") || "reports"] = window.scrollY;
      p.forEach((_, k) => {
        if (k !== "section") p.delete(k);
      });
      for (const k of [...p.keys()]) if (k !== "section") p.delete(k);
    }
    Object.entries(changes).forEach(([k, v]) =>
      v ? p.set(k, v) : p.delete(k),
    );
    history.pushState(null, "", `?${p}`);
    setURL(readConsoleURL(location.search));
  }, []);
  useEffect(() => {
    const changed = () => setURL(readConsoleURL(location.search));
    window.addEventListener("popstate", changed);
    return () => window.removeEventListener("popstate", changed);
  }, []);
  useEffect(() => {
    setSearch(url.params.get("search") || "");
  }, [url.params.get("search")]);
  useEffect(() => {
    window.scrollTo({ top: scrollPositions.current[url.section] || 0 });
  }, [url.section]);
  useEffect(() => {
    let active = true;
    async function check() {
      try {
        await AdminApi.me(token);
        if (active) setSessionError("");
      } catch (e) {
        if (!active) return;
        if (e instanceof ApiError && (e.status === 401 || e.status === 403))
          onLogout();
        else
          setSessionError(
            "Access verification is temporarily unavailable. Actions still require server authorization.",
          );
      }
    }
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void check();
    }, 60000);
    const focus = () => void check();
    window.addEventListener("focus", focus);
    return () => {
      active = false;
      clearInterval(timer);
      window.removeEventListener("focus", focus);
    };
  }, [token, onLogout]);
  const title = sections.find((x) => x.key === url.section)?.label || "Reports";
  const subtitles: Partial<Record<ConsoleSection, string>> = {
    reports: "Review reports and manage community safety.",
    finance: "Review creator earnings, Support releases and payout accounting.",
    dashboard: "A clear view of community safety and operational health.",
    users: "Find accounts and review their moderation history.",
    posts: "Review content without changing Captro’s creative identity.",
    media: "Track uploads and moderation outcomes.",
    listings: "Review community listings while preserving paid access.",
    appeals: "Give decisions a documented, independent review.",
    operations: "Inspect action outcomes and operational follow-up.",
    audit: "Protected history of administrative decisions.",
    access: "Server-managed roles. No public admin registration.",
  };
  return (
    <div className="console-app">
      <a className="skip-link" href="#console-main">
        Skip to workspace
      </a>
      <aside className="console-sidebar">
        <a
          className="console-brand"
          href="?section=dashboard"
          onClick={(e) => {
            e.preventDefault();
            navigate({ section: "dashboard" });
          }}
        >
          <img className="captro-mark" src="/brand/captro-symbol-black.svg" alt="Captro" width="36" height="25" />
          <div>
            <img className="console-lockup" src="/brand/captro-lockup-black.svg" alt="Captro" width="166" height="43" />
            <span>Admin console</span>
          </div>
        </a>
        <nav aria-label="Admin navigation">
          {sections.filter((s) => s.key !== "finance" || can(session, "payments:read")).map((s) => (
            <a
              key={s.key}
              href={`?section=${s.key}`}
              aria-current={url.section === s.key ? "page" : undefined}
              onClick={(e) => {
                e.preventDefault();
                navigate({ section: s.key });
              }}
            >
              <Icon name={s.icon} />
              <span>{s.label}</span>
            </a>
          ))}
        </nav>
        <div className="sidebar-account">
          <span className="initial-avatar">
            {(session.user.full_name || session.user.username || "A")
              .slice(0, 2)
              .toUpperCase()}
          </span>
          <div>
            <strong>{session.user.full_name || session.user.username}</strong>
            <span>{label(session.role)}</span>
          </div>
          <button
            className="icon-button"
            onClick={onLogout}
            aria-label="Sign out"
          >
            ↪
          </button>
        </div>
      </aside>
      <div className="console-workspace">
        <header className="console-header">
          <div className="breadcrumb">
            Workspace <span>/</span>
            <strong>{title}</strong>
          </div>
          <form
            className="console-search"
            onSubmit={(e) => {
              e.preventDefault();
              navigate({ search, offset: "0" });
            }}
          >
            <Icon name="search" />
            <input
              aria-label={`Search ${title.toLowerCase()}`}
              placeholder={
                ["reports", "users", "posts", "audit"].includes(url.section)
                  ? `Search ${title.toLowerCase()} by ID or name`
                  : "Search is available in Reports, Users and Content"
              }
              value={search}
              disabled={
                !["reports", "users", "posts", "audit"].includes(url.section)
              }
              onChange={(e) => setSearch(e.target.value)}
            />
          </form>
          <span
            className="header-avatar"
            aria-label={`Signed in as ${session.user.full_name}`}
          >
            {(session.user.full_name || "A").slice(0, 2).toUpperCase()}
          </span>
        </header>
        <main id="console-main" ref={main} tabIndex={-1}>
          <div className="console-page-heading">
            <div>
              <h1>{title}</h1>
              <p>{subtitles[url.section]}</p>
            </div>
            <span className="workspace-label">
              {label(session.environment)} workspace
            </span>
          </div>
          {sessionError ? (
            <p role="status" className="console-error">
              {sessionError}
            </p>
          ) : null}
          {url.section === "finance" ? (
            can(session, "payments:read") ? <FinancePage token={token} canResolve={can(session, "payments:refund")} canRelease={can(session, "payments:release")} canManageSupport={can(session, "payments:support:manage")} /> : <div className="console-error" role="alert"><strong>Access restricted</strong><p>Finance access is required.</p></div>
          ) : url.section === "reports" ? (
            <Reports
              token={token}
              session={session}
              params={url.params}
              navigate={navigate}
            />
          ) : url.section === "dashboard" ? (
            <>
              <Summary token={token} />
              <section className="console-panel overview-welcome">
                <Icon name="shield" />
                <h2>Community safety workspace</h2>
                <p>
                  Review reports in context. Preserve evidence, use reversible
                  actions, and keep financial support separate from moderation.
                </p>
                <button
                  className="primary-button"
                  onClick={() => navigate({ section: "reports" })}
                >
                  Open report queue
                </button>
              </section>
            </>
          ) : (
            <Records
              key={url.section}
              section={url.section}
              token={token}
              session={session}
              params={url.params}
              navigate={navigate}
            />
          )}
        </main>
        <footer className="console-footer">
          Captro · Private administration · Server-authorized actions
        </footer>
      </div>
    </div>
  );
}
