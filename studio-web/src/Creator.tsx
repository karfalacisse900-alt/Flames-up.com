import { useRef, useState } from "react";
import {
  api,
  money,
  words,
  categories,
  type Role,
  type PublicData,
} from "./api";
import { ConfirmButton, DataState, Photo, useData } from "./components";
export function PublicProfileForm({
  role,
  saved,
}: {
  role: Role;
  saved: () => void;
}) {
  const [draft, setDraft] = useState(role.public_data),
    [links, setLinks] = useState(role.public_data.links.join("\n")),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState("");
  const operation = useRef<{ key: string; id: string } | undefined>(undefined);
  async function save() {
    setBusy(true);
    setNotice("");
    const data = {
      version: role.version,
      public: {
        ...draft,
        links: links
          .split("\n")
          .map((v) => v.trim())
          .filter(Boolean),
      },
      message: "",
    };
    const key = JSON.stringify(data);
    if (operation.current?.key !== key)
      operation.current = { key, id: crypto.randomUUID() };
    try {
      await api(`/professional/${role.role}/edit_public`, {
        ...data,
        id: operation.current.id,
      });
      setNotice("Public information saved.");
      saved();
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const field = (key: keyof PublicData, value: string | boolean) =>
    setDraft((d) => ({ ...d, [key]: value }));
  return (
    <form
      className="panel form"
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <h1>
        Public {role.role === "creator" ? "creator" : "business"} information
      </h1>
      <p className="quiet">
        These fields appear on your approved professional profile. Regular
        account settings stay in Captro.
      </p>
      <fieldset disabled={role.status !== "active" || busy}>
        <label>
          Display name
          <input
            required
            maxLength={80}
            value={draft.displayName}
            onChange={(e) => field("displayName", e.target.value)}
          />
        </label>
        <label>
          Category
          <select
            value={draft.category}
            onChange={(e) => field("category", e.target.value)}
          >
            {categories[role.role].map((c) => (
              <option key={c} value={c}>
                {words(c)}
              </option>
            ))}
          </select>
        </label>
        <label>
          Description
          <textarea
            required
            maxLength={500}
            value={draft.description}
            onChange={(e) => field("description", e.target.value)}
          />
        </label>
        <label>
          Links · up to three HTTPS URLs, optional
          <textarea
            value={links}
            onChange={(e) => setLinks(e.target.value)}
            placeholder="One link per line"
            autoCapitalize="none"
          />
        </label>
        {role.role === "business" && (
          <>
            <label>
              Operating area
              <input
                required
                maxLength={120}
                value={draft.area}
                onChange={(e) => field("area", e.target.value)}
              />
            </label>
            <label className="check">
              <input
                type="checkbox"
                checked={draft.pickup}
                onChange={(e) => field("pickup", e.target.checked)}
              />{" "}
              Offers pickup
            </label>
          </>
        )}
        <div className="actions">
          <button
            type="button"
            onClick={() => {
              setDraft(role.public_data);
              setLinks(role.public_data.links.join("\n"));
              setNotice("Unsaved changes discarded.");
            }}
          >
            Cancel changes
          </button>
          <button className="primary">
            {busy ? "Saving…" : "Save information"}
          </button>
        </div>
      </fieldset>
      {notice && <p role="status">{notice}</p>}
    </form>
  );
}
type Post = {
  id: string;
  title?: string;
  caption?: string;
  post_type?: string;
  visibility?: string;
  thumbnail_url?: string;
  media_thumbnail_urls?: string[];
  pinned_at?: string;
  detail?: {
    event?: { title?: string; starts_at?: string; venue_name?: string };
  };
};
export function Creator({
  role,
  userID,
  saved,
}: {
  role: Role;
  userID: string;
  saved: () => void;
}) {
  const [tab, setTab] = useState("Work");
  return (
    <>
      <header className="page-title">
        <div>
          <p className="eyebrow">Creator workspace</p>
          <h1>{role.public_data.displayName}</h1>
          <p>{words(role.public_data.category)}</p>
        </div>
      </header>
      <nav className="tabs" aria-label="Creator sections">
        {["Work", "Support"].map((t) => (
          <button
            key={t}
            aria-current={tab === t ? "page" : undefined}
            onClick={() => setTab(t)}
          >
            {t}
          </button>
        ))}
      </nav>
      {tab === "Work" ? (
        <Work role={role} userID={userID} saved={saved} />
      ) : (
        <Support />
      )}
    </>
  );
}
function Work({
  role,
  userID,
  saved,
}: {
  role: Role;
  userID: string;
  saved: () => void;
}) {
  const [offset, setOffset] = useState(0);
  const posts = useData<Post[]>(
    `/users/${encodeURIComponent(userID)}/posts?skip=${offset}&limit=24`,
  );
  const [error, setError] = useState("");
  async function portfolio(id: string) {
    const ids = role.public_data.portfolioPostIds;
    const chosen = ids.includes(id)
      ? ids.filter((v) => v !== id)
      : [...ids, id];
    if (chosen.length > 9)
      throw new Error("Choose up to nine portfolio posts.");
    await api("/professional/creator/edit_public", {
      id: crypto.randomUUID(),
      version: role.version,
      public: { ...role.public_data, portfolioPostIds: chosen },
      message: "",
    });
    saved();
  }
  return (
    <>
      <div className="section-heading">
        <h2>Your work & gigs</h2>
        <button onClick={posts.reload}>Refresh</button>
      </div>
      <p className="quiet">
        Manage existing Captro posts. Create new moments and gigs in the iPhone
        app. Portfolio selections remain subject to each post’s visibility.
      </p>
      <DataState
        error={posts.error}
        loading={posts.loading && !posts.value}
        retry={posts.reload}
      />
      {error && <p role="alert">{error}</p>}
      {posts.value?.length === 0 && (
        <p className="panel">
          No posts on this page. Your existing Captro publishing flow is
          unchanged.
        </p>
      )}
      <div className="products">
        {posts.value?.map((post) => (
          <article className="panel work" key={post.id}>
            <Photo
              url={post.media_thumbnail_urls?.[0] ?? post.thumbnail_url}
              label={post.title || "Captro post"}
            />
            <h3>{post.title || post.caption || "Untitled moment"}</h3>
            <small>
              {words(post.post_type || "moment")}
              {post.detail?.event?.starts_at
                ? " · " + new Date(post.detail.event.starts_at).toLocaleString()
                : ""}
            </small>
            <label>
              Visibility
              <select
                disabled={role.status !== "active"}
                value={post.visibility || "public"}
                onChange={async (e) => {
                  try {
                    await api(
                      `/posts/${post.id}/visibility`,
                      { visibility: e.target.value },
                      "PUT",
                    );
                    posts.reload();
                  } catch (e) {
                    setError((e as Error).message);
                  }
                }}
              >
                {["public", "followers", "friends", "private"].map((v) => (
                  <option key={v}>{v}</option>
                ))}
              </select>
            </label>
            <div className="actions">
              <ConfirmButton
                disabled={role.status !== "active"}
                title={
                  role.public_data.portfolioPostIds.includes(post.id)
                    ? "Remove from portfolio"
                    : "Add to portfolio"
                }
                onConfirm={() => portfolio(post.id)}
              />
              <ConfirmButton
                disabled={role.status !== "active"}
                title={post.pinned_at ? "Unpin post" : "Pin post"}
                onConfirm={async () => {
                  await api(
                    `/posts/${post.id}/pin`,
                    { pinned: !post.pinned_at },
                    "PUT",
                  );
                  posts.reload();
                }}
              />
            </div>
          </article>
        ))}
      </div>
      <div className="actions">
        <button
          disabled={!offset}
          onClick={() => setOffset((x) => Math.max(0, x - 24))}
        >
          Previous
        </button>
        <button
          disabled={(posts.value?.length ?? 0) < 24}
          onClick={() => setOffset((x) => x + 24)}
        >
          Next
        </button>
      </div>
    </>
  );
}
type Pool = {
  category: string;
  currency: string;
  grossReceived: number;
  processingFees: number | null;
  creatorNet: number | null;
  pending: number;
  available: number;
  paidOut: number;
  held: number;
  refunded: number;
  captroFee: number;
};
function Support() {
  const readiness = useData<{
    status: string;
    blockers: ({ code?: string; message?: string; detail?: string } | string)[];
    retryable?: boolean;
  }>("/commerce/earnings/support-readiness");
  const pools = useData<{ mode: string; payoutScope: string; pools: Pool[] }>(
    "/commerce/earnings/pools",
  );
  const [section, setSection] = useState("transactions"),
    [offset, setOffset] = useState(0),
    [currency, setCurrency] = useState("USD");
  const history = useData<{
    items: {
      id: string;
      title?: string;
      status: string;
      createdAt: string;
      grossReceived?: number;
      attributedAmount?: number;
      processingFees?: number | null;
      creatorNet?: number | null;
      payoutFee?: number | null;
      currency: string;
    }[];
    nextOffset: number | null;
  }>(
    `/commerce/earnings/pools/creator_support?currency=${currency}&section=${section}&offset=${offset}`,
  );
  const support = pools.value?.pools.filter(
    (p) => p.category === "creator_support",
  );
  return (
    <>
      <h2>Support earnings</h2>
      <p className="quiet">
        Captro takes 0%. Payment-processing fees apply. Support is your own
        ledger category, separate from business orders. Balances become
        available only under the existing settlement and payout rules.
      </p>
      <section className="panel">
        <h3>Payment readiness</h3>
        <DataState
          error={readiness.error}
          loading={readiness.loading}
          retry={readiness.reload}
        />
        {readiness.value && (
          <>
            <strong>{words(readiness.value.status)}</strong>
            <ul>
              {readiness.value.blockers.map((b, i) => (
                <li key={i}>
                  {typeof b === "string"
                    ? words(b)
                    : b.message ||
                      b.detail ||
                      words(b.code || "Review required")}
                </li>
              ))}
            </ul>
            <p>
              Professional approval does not override these checks. Complete
              existing payment setup in Captro’s Earnings screen; no second
              connected account is created here.
            </p>
          </>
        )}
      </section>
      <DataState
        error={pools.error}
        loading={pools.loading}
        retry={pools.reload}
      />
      {pools.value && (
        <>
          <p>
            {pools.value.mode === "test"
              ? "Stripe test mode"
              : "Stripe live mode"}{" "}
            · Payouts use the existing creator and currency balance across
            earnings categories.
          </p>
          {support?.map((pool) => (
            <section key={pool.currency}>
              <h3>{pool.currency}</h3>
              <dl className="metrics">
                {[
                  ["Gross Support", pool.grossReceived],
                  ["Actual processing fees", pool.processingFees],
                  ["Creator net", pool.creatorNet],
                  ["Pending", pool.pending],
                  ["Available", pool.available],
                  ["Paid out", pool.paidOut],
                  ["Refunded", pool.refunded],
                  ["Captro fee", pool.captroFee],
                ].map(([label, amount]) => (
                  <div key={String(label)}>
                    <dt>{label}</dt>
                    <dd>{money(amount as number | null, pool.currency)}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </>
      )}
      <div className="section-heading">
        <h3>
          {section === "transactions"
            ? "Support transactions"
            : "Payout history"}
        </h3>
        <label>
          Currency
          <select
            value={currency}
            onChange={(e) => {
              setCurrency(e.target.value);
              setOffset(0);
            }}
          >
            {[
              ...new Set(["USD", ...(support?.map((p) => p.currency) ?? [])]),
            ].map((c) => (
              <option key={c}>{c}</option>
            ))}
          </select>
        </label>
      </div>
      <nav className="tabs" aria-label="Support records">
        {["transactions", "payouts"].map((s) => (
          <button
            key={s}
            aria-current={s === section ? "page" : undefined}
            onClick={() => {
              setSection(s);
              setOffset(0);
            }}
          >
            {words(s)}
          </button>
        ))}
      </nav>
      <DataState
        error={history.error}
        loading={history.loading && !history.value}
        retry={history.reload}
      />
      {history.value && (
        <>
          {!history.value.items.length ? (
            <p className="panel">No {section} for this currency.</p>
          ) : (
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Record</th>
                    <th>Status</th>
                    <th>
                      {section === "payouts"
                        ? "Attributed to Support"
                        : "Gross"}
                    </th>
                    <th>Fee</th>
                  </tr>
                </thead>
                <tbody>
                  {history.value.items.map((item) => (
                    <tr key={item.id}>
                      <td>
                        {item.title || item.id.slice(0, 12)}
                        <small>
                          {new Date(item.createdAt).toLocaleDateString()}
                        </small>
                      </td>
                      <td>{words(item.status)}</td>
                      <td>
                        {money(
                          item.attributedAmount ?? item.grossReceived,
                          item.currency,
                        )}
                      </td>
                      <td>
                        {money(
                          section === "payouts"
                            ? item.payoutFee
                            : item.processingFees,
                          item.currency,
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="actions">
            <button
              disabled={!offset}
              onClick={() => setOffset(Math.max(0, offset - 25))}
            >
              Previous
            </button>
            <button
              disabled={history.value.nextOffset === null}
              onClick={() => setOffset(history.value!.nextOffset!)}
            >
              Next
            </button>
          </div>
        </>
      )}
    </>
  );
}
