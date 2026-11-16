import { useEffect, useState } from "react";
import { api, money, words, type Role } from "./api";
import {
  ConfirmButton,
  DataState,
  Modal,
  Photo,
  PhotoInput,
  useData,
} from "./components";
type Shop = {
  id: string;
  name: string;
  category: string;
  pickup_address: string;
  pickup_instructions?: string;
  latitude: number;
  longitude: number;
  hours: string;
  paused: boolean;
  published: boolean;
  photos: string[];
  avatar_url?: string;
  tax_bps: number | null;
  location_updated_at?: string;
};
type Option = { id: string; name: string; extra: number };
type Group = {
  id: string;
  name: string;
  minimum: number;
  maximum: number;
  options: Option[];
};
type Product = {
  id: string;
  name: string;
  category: string;
  unit_amount: number;
  mode: "QUICK_ADD" | "CUSTOMIZE";
  available: boolean;
  stock: number | null;
  groups: Group[];
  image_url?: string;
};
type Order = {
  id: string;
  business_name: string;
  status: string;
  created_at: string;
  total: number;
  processing_fee: number | null;
  refunded_amount: number;
  lines: {
    name: string;
    quantity: number;
    unit_amount: number;
    options: { name: string }[];
  }[];
};
const newShop = (): Shop => ({
  id: crypto.randomUUID(),
  name: "",
  category: "coffee_bakery",
  pickup_address: "",
  latitude: 0,
  longitude: 0,
  hours: "",
  paused: true,
  published: false,
  photos: [],
  tax_bps: null,
});
export function Business({ role }: { role: Role }) {
  const shops = useData<Shop[]>("/business-owner/shops");
  const [selected, setSelected] = useState(""),
    [tab, setTab] = useState("Orders"),
    [creating, setCreating] = useState(false);
  const active = role.status === "active";
  const shop = shops.value?.find((s) => s.id === selected) ?? shops.value?.[0];
  return (
    <>
      <header className="page-title">
        <div>
          <p className="eyebrow">Business workspace</p>
          <h1>{role.public_data.displayName}</h1>
        </div>
        {active && (
          <button onClick={() => setCreating(true)}>Add business</button>
        )}
      </header>
      <DataState
        error={shops.error}
        loading={shops.loading && !shops.value}
        retry={shops.reload}
      />
      {shops.value && shops.value.length === 0 && !creating && (
        <section className="panel">
          <h2>No storefront yet</h2>
          <p>
            Your Business role is approved. Ordering currently supports coffee
            shops, bakeries and street food vendors. Other approved businesses
            can edit their public information in Profile.
          </p>
          {active &&
            ["coffee_bakery", "street_food"].includes(
              role.public_data.category,
            ) && (
              <button className="primary" onClick={() => setCreating(true)}>
                Set up storefront
              </button>
            )}
        </section>
      )}
      {shop && !creating && (
        <>
          <div className="workspace-controls">
            <label>
              Business
              <select
                value={shop.id}
                onChange={(e) => setSelected(e.target.value)}
              >
                {shops.value!.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
            <span>
              {shop.paused ? "Ordering paused" : "Accepting orders"} ·{" "}
              {shop.published ? "Published" : "Unpublished"}
            </span>
          </div>
          <nav className="tabs" aria-label="Business sections">
            {["Orders", "Menu", "Storefront", "Sales"].map((t) => (
              <button
                key={t}
                aria-current={tab === t ? "page" : undefined}
                onClick={() => setTab(t)}
              >
                {t}
              </button>
            ))}
          </nav>
          <div key={shop.id}>
            {tab === "Orders" ? (
              <Orders shop={shop} />
            ) : tab === "Menu" ? (
              <Menu shop={shop} active={active} />
            ) : tab === "Storefront" ? (
              <ShopForm shop={shop} active={active} saved={shops.reload} />
            ) : (
              <Sales shop={shop} />
            )}
          </div>
        </>
      )}
      {creating && (
        <ShopForm
          shop={newShop()}
          active={active}
          saved={() => {
            setCreating(false);
            shops.reload();
          }}
          cancel={() => setCreating(false)}
        />
      )}
    </>
  );
}
function ShopForm({
  shop,
  active,
  saved,
  cancel,
}: {
  shop: Shop;
  active: boolean;
  saved: () => void;
  cancel?: () => void;
}) {
  const [draft, setDraft] = useState(shop),
    [avatar, setAvatar] = useState<string>(),
    [photos, setPhotos] = useState<string[]>([]),
    [replacePhotos, setReplacePhotos] = useState(false),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState("");
  const field = (key: keyof Shop, value: unknown) =>
    setDraft((d) => ({ ...d, [key]: value }));
  async function save() {
    setBusy(true);
    setNotice("");
    try {
      await api("/business-owner/shops", {
        id: draft.id,
        name: draft.name,
        category: draft.category,
        pickup_address: draft.pickup_address,
        latitude: draft.latitude,
        longitude: draft.longitude,
        hours: draft.hours,
        paused: draft.paused,
        published: draft.published,
        pickup_instructions: draft.pickup_instructions ?? "",
        ...(avatar ? { avatar_id: avatar } : {}),
        ...(replacePhotos ? { photo_ids: photos } : {}),
      });
      setNotice("Storefront saved.");
      saved();
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      className="panel form"
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <h2>Storefront & pickup</h2>
      <fieldset disabled={!active || busy}>
        <label>
          Public business name
          <input
            required
            maxLength={80}
            value={draft.name}
            onChange={(e) => field("name", e.target.value)}
          />
        </label>
        <label>
          Ordering category
          <select
            value={draft.category}
            onChange={(e) => field("category", e.target.value)}
          >
            <option value="coffee_bakery">Coffee shop / bakery</option>
            <option value="street_food">Street food vendor</option>
          </select>
        </label>
        <label>
          Pickup address
          <input
            required
            maxLength={240}
            value={draft.pickup_address}
            onChange={(e) => field("pickup_address", e.target.value)}
          />
        </label>
        <div className="columns">
          <label>
            Latitude
            <input
              required
              type="number"
              min={-90}
              max={90}
              step="any"
              value={draft.latitude}
              onChange={(e) => field("latitude", Number(e.target.value))}
            />
          </label>
          <label>
            Longitude
            <input
              required
              type="number"
              min={-180}
              max={180}
              step="any"
              value={draft.longitude}
              onChange={(e) => field("longitude", Number(e.target.value))}
            />
          </label>
        </div>
        <p className="quiet">
          For a mobile vendor, save the current pickup point whenever it
          changes. This is a shared location, not live tracking.
        </p>
        <label>
          Operating hours
          <textarea
            maxLength={300}
            value={draft.hours}
            onChange={(e) => field("hours", e.target.value)}
          />
        </label>
        <label>
          Pickup instructions
          <textarea
            maxLength={500}
            value={draft.pickup_instructions ?? ""}
            onChange={(e) => field("pickup_instructions", e.target.value)}
          />
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={draft.paused}
            onChange={(e) => field("paused", e.target.checked)}
          />{" "}
          Pause incoming orders
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={draft.published}
            onChange={(e) => field("published", e.target.checked)}
          />{" "}
          List this storefront publicly
        </label>
        <PhotoInput
          label={
            avatar ? "Profile photo ready to save" : "Upload profile photo"
          }
          onUploaded={setAvatar}
        />
        <div className="photos">
          {draft.photos.map((url) => (
            <Photo key={url} url={url} label="Business photo" />
          ))}
        </div>
        <label className="check">
          <input
            type="checkbox"
            checked={replacePhotos}
            onChange={(e) => setReplacePhotos(e.target.checked)}
          />{" "}
          Replace business photo strip
        </label>
        {replacePhotos && (
          <>
            <PhotoInput
              disabled={photos.length >= 8}
              label={`Add photo · ${photos.length}/8 approved`}
              onUploaded={(id) => setPhotos((p) => [...p, id])}
            />
            {photos.length > 0 && (
              <button type="button" onClick={() => setPhotos([])}>
                Clear replacement photos
              </button>
            )}
            <small>
              Saving an empty replacement removes the current strip. Uploaded
              photos are reviewed before use.
            </small>
          </>
        )}
        <div className="actions">
          {cancel && (
            <button type="button" onClick={cancel}>
              Cancel
            </button>
          )}
          <button className="primary">
            {busy ? "Saving…" : "Save storefront"}
          </button>
        </div>
      </fieldset>
      {draft.tax_bps === null && (
        <p className="notice">
          Tax configuration has not been verified. Checkout remains blocked
          until the existing ordering setup is complete.
        </p>
      )}
      {notice && <p role="status">{notice}</p>}
    </form>
  );
}
function Menu({ shop, active }: { shop: Shop; active: boolean }) {
  const [offset, setOffset] = useState(0);
  const products = useData<Product[]>(
    `/business-owner/${shop.id}/products?offset=${offset}`,
  );
  const [editing, setEditing] = useState<Product>();
  const add = () =>
    setEditing({
      id: crypto.randomUUID(),
      name: "",
      category: "",
      unit_amount: 200,
      mode: "QUICK_ADD",
      available: true,
      stock: null,
      groups: [],
    });
  return (
    <>
      <div className="section-heading">
        <h2>Menu</h2>
        <button disabled={!active} onClick={add}>
          Add product
        </button>
      </div>
      <DataState
        error={products.error}
        loading={products.loading && !products.value}
        retry={products.reload}
      />
      {products.value && (
        <>
          <div className="products">
            {products.value.map((p) => (
              <article className="product" key={p.id}>
                <Photo url={p.image_url} label={p.name} />
                <button className="product-open" onClick={() => setEditing(p)}>
                  <strong>{p.name}</strong>
                </button>
                <span>
                  {money(p.unit_amount)} ·{" "}
                  {p.mode === "CUSTOMIZE" ? "Customize" : "Quick add"}
                </span>
                <small>
                  {p.available ? "Available" : "Unavailable"}
                  {p.stock !== null ? ` · ${p.stock} in stock` : ""}
                </small>
              </article>
            ))}
          </div>
          {!products.value.length && <p>No menu items yet.</p>}
          <div className="actions">
            <button
              disabled={!offset}
              onClick={() => setOffset((x) => Math.max(0, x - 50))}
            >
              Previous
            </button>
            <button
              disabled={products.value.length < 50}
              onClick={() => setOffset((x) => x + 50)}
            >
              Next
            </button>
          </div>
        </>
      )}
      {editing && (
        <Modal label="Edit menu item" close={() => setEditing(undefined)}>
          <ProductForm
            key={editing.id}
            product={editing}
            business={shop.id}
            active={active}
            close={() => setEditing(undefined)}
            saved={() => {
              setEditing(undefined);
              products.reload();
            }}
          />
        </Modal>
      )}
    </>
  );
}
function ProductForm({
  product,
  business,
  active,
  close,
  saved,
}: {
  product: Product;
  business: string;
  active: boolean;
  close: () => void;
  saved: () => void;
}) {
  const [draft, setDraft] = useState(product),
    [image, setImage] = useState<string>(),
    [price, setPrice] = useState((product.unit_amount / 100).toFixed(2)),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const group = (id: string, patch: Partial<Group>) =>
    setDraft((p) => ({
      ...p,
      groups: p.groups.map((g) => (g.id === id ? { ...g, ...patch } : g)),
    }));
  async function save() {
    setBusy(true);
    setError("");
    try {
      if (!/^\d+(\.\d{1,2})?$/.test(price))
        throw new Error("Enter a USD price with at most two decimal places.");
      await api(`/business-owner/${business}/products`, {
        id: draft.id,
        name: draft.name,
        category: draft.category,
        unit_amount: Math.round(Number(price) * 100),
        mode: draft.mode,
        available: draft.available,
        ...(draft.stock !== product.stock ? { stock: draft.stock, expected_stock: product.stock } : {}),
        groups:
          draft.mode === "QUICK_ADD"
            ? []
            : draft.groups.map((g) => ({
                ...g,
                options: g.options.map((o) => ({
                  id: o.id,
                  name: o.name,
                  extra: o.extra,
                })),
              })),
        ...(image ? { media_id: image } : {}),
      });
      saved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      className="form"
      onSubmit={(e) => {
        e.preventDefault();
        void save();
      }}
    >
      <div className="section-heading">
        <h2>Menu item</h2>
        <button type="button" disabled={busy} onClick={close}>
          Close
        </button>
      </div>
      <fieldset disabled={!active || busy}>
        <label>
          Name
          <input
            required
            maxLength={80}
            value={draft.name}
            onChange={(e) => setDraft((p) => ({ ...p, name: e.target.value }))}
          />
        </label>
        <label>
          Menu category
          <input
            required
            maxLength={48}
            value={draft.category}
            onChange={(e) =>
              setDraft((p) => ({ ...p, category: e.target.value }))
            }
          />
        </label>
        <label>
          Base price · USD
          <input
            required
            inputMode="decimal"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
          />
        </label>
        <label>
          Ordering mode
          <select
            value={draft.mode}
            onChange={(e) =>
              setDraft((p) => ({
                ...p,
                mode: e.target.value as Product["mode"],
              }))
            }
          >
            <option value="QUICK_ADD">Quick add</option>
            <option value="CUSTOMIZE">Customize</option>
          </select>
        </label>
        <label>
          Stock · leave blank for unlimited
          <input
            type="number"
            min={0}
            max={100000}
            value={draft.stock ?? ""}
            onChange={(e) =>
              setDraft((p) => ({
                ...p,
                stock: e.target.value === "" ? null : Number(e.target.value),
              }))
            }
          />
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={draft.available}
            onChange={(e) =>
              setDraft((p) => ({ ...p, available: e.target.checked }))
            }
          />{" "}
          Available
        </label>
        <PhotoInput
          label={image ? "Product photo ready" : "Product photo"}
          onUploaded={setImage}
        />
        {draft.mode === "CUSTOMIZE" && (
          <>
            <h3>Options</h3>
            {draft.groups.map((g) => (
              <section className="option-group" key={g.id}>
                <label>
                  Group name
                  <input
                    required
                    maxLength={60}
                    value={g.name}
                    onChange={(e) => group(g.id, { name: e.target.value })}
                  />
                </label>
                <div className="columns">
                  <label>
                    Minimum selections
                    <input
                      type="number"
                      min={0}
                      max={g.maximum}
                      value={g.minimum}
                      onChange={(e) =>
                        group(g.id, { minimum: Number(e.target.value) })
                      }
                    />
                  </label>
                  <label>
                    Maximum selections
                    <input
                      type="number"
                      min={1}
                      max={Math.max(1, g.options.length)}
                      value={g.maximum}
                      onChange={(e) =>
                        group(g.id, { maximum: Number(e.target.value) })
                      }
                    />
                  </label>
                </div>
                {g.options.map((o) => (
                  <div className="option-line" key={o.id}>
                    <label>
                      Option
                      <input
                        required
                        maxLength={60}
                        value={o.name}
                        onChange={(e) =>
                          group(g.id, {
                            options: g.options.map((v) =>
                              v.id === o.id
                                ? { ...v, name: e.target.value }
                                : v,
                            ),
                          })
                        }
                      />
                    </label>
                    <label>
                      Extra · cents
                      <input
                        type="number"
                        min={0}
                        max={5000}
                        value={o.extra}
                        onChange={(e) =>
                          group(g.id, {
                            options: g.options.map((v) =>
                              v.id === o.id
                                ? { ...v, extra: Number(e.target.value) }
                                : v,
                            ),
                          })
                        }
                      />
                    </label>
                    <button
                      type="button"
                      aria-label={"Remove " + (o.name || "option")}
                      onClick={() =>
                        group(g.id, {
                          options: g.options.filter((v) => v.id !== o.id),
                        })
                      }
                    >
                      ×
                    </button>
                  </div>
                ))}
                <div className="actions">
                  <button
                    type="button"
                    disabled={g.options.length >= 30}
                    onClick={() =>
                      group(g.id, {
                        options: [
                          ...g.options,
                          { id: crypto.randomUUID(), name: "", extra: 0 },
                        ],
                      })
                    }
                  >
                    Add option
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      setDraft((p) => ({
                        ...p,
                        groups: p.groups.filter((v) => v.id !== g.id),
                      }))
                    }
                  >
                    Remove group
                  </button>
                </div>
              </section>
            ))}
            <button
              type="button"
              disabled={draft.groups.length >= 12}
              onClick={() =>
                setDraft((p) => ({
                  ...p,
                  groups: [
                    ...p.groups,
                    {
                      id: crypto.randomUUID(),
                      name: "",
                      minimum: 0,
                      maximum: 1,
                      options: [
                        { id: crypto.randomUUID(), name: "", extra: 0 },
                      ],
                    },
                  ],
                }))
              }
            >
              Add option group
            </button>
          </>
        )}
        <button className="primary">
          {busy ? "Saving…" : "Save menu item"}
        </button>
      </fieldset>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
    </form>
  );
}
function Orders({ shop }: { shop: Shop }) {
  const [offset, setOffset] = useState(0),
    [code, setCode] = useState(""),
    [notice, setNotice] = useState("");
  const orders = useData<Order[]>(
    `/business-owner/${shop.id}/orders?offset=${offset}`,
  );
  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState === "visible") orders.reload();
    };
    const timer = setInterval(refresh, 20000);
    window.addEventListener("focus", refresh);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", refresh);
    };
  }, [shop.id]);
  async function action(id: string, action: string) {
    await api(`/business-orders/${id}/action`, { action });
    orders.reload();
  }
  return (
    <>
      <div className="section-heading">
        <h2>Orders</h2>
        <button onClick={orders.reload}>Refresh</button>
      </div>
      <p className="quiet">
        Updates while this workspace is open. Existing orders remain available
        if your Business role is suspended.
      </p>
      <DataState
        error={orders.error}
        loading={orders.loading && !orders.value}
        retry={orders.reload}
      />
      {orders.value?.length === 0 && (
        <p className="panel">No paid orders on this page.</p>
      )}
      {orders.value?.map((o) => (
        <article key={o.id} className="panel order">
          <div className="section-heading">
            <h3>Order {o.id.slice(0, 8)}</h3>
            <span>{words(o.status)}</span>
          </div>
          <small>{new Date(o.created_at).toLocaleString()}</small>
          {o.lines.map((line, index) => (
            <p key={index}>
              {line.quantity} × {line.name}
              <small>{line.options?.map((v) => v.name).join(" · ")}</small>
            </p>
          ))}
          <strong>{money(o.total)}</strong>
          <div className="actions">
            {(
              {
                received: ["accept", "reject"],
                accepted: ["prepare", "cancel"],
                preparing: ["ready", "cancel"],
                ready: ["cancel"],
                refund_pending: ["reject"],
              }[o.status] ?? []
            ).map((a) => (
              <ConfirmButton
                key={a}
                title={words(a)}
                onConfirm={() => action(o.id, a)}
              />
            ))}
          </div>
        </article>
      ))}
      <div className="actions">
        <button
          disabled={!offset}
          onClick={() => setOffset((x) => Math.max(0, x - 50))}
        >
          Previous
        </button>
        <button
          disabled={(orders.value?.length ?? 0) < 50}
          onClick={() => setOffset((x) => x + 50)}
        >
          Next
        </button>
      </div>
      <form
        className="panel form"
        onSubmit={async (e) => {
          e.preventDefault();
          setNotice("Verifying pickup…");
          try {
            await api(`/business-owner/${shop.id}/pickup`, {
              code: code.trim(),
            });
            setNotice("Pickup verified. Order completed.");
            setCode("");
            orders.reload();
          } catch (e) {
            setNotice((e as Error).message);
          }
        }}
      >
        <h3>Verify pickup</h3>
        <label>
          Pickup QR code
          <input
            required
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="Scan with a connected QR reader or paste the code"
            autoComplete="off"
          />
        </label>
        <button className="primary">Verify & complete pickup</button>
        <p className="quiet">
          The server verifies this order and one-time pickup code. The Captro
          iPhone app also includes the existing camera scanner.
        </p>
        {notice && <p role="status">{notice}</p>}
      </form>
    </>
  );
}
function Sales({ shop }: { shop: Shop }) {
  const sales = useData<{
    gross: number;
    tax: number;
    refunded: number;
    processing_fee: number;
    pending_fees: number;
  }>(`/business-owner/${shop.id}/earnings`);
  return (
    <>
      <h2>Order sales</h2>
      <p className="notice">
        The existing Business ordering integration is test-only. These are test
        order records, not withdrawable live earnings. Creator Support balances
        remain separate.
      </p>
      <DataState
        error={sales.error}
        loading={sales.loading}
        retry={sales.reload}
      />
      {sales.value && (
        <dl className="metrics">
          {[
            ["Gross sales", money(sales.value.gross)],
            ["Tax", money(sales.value.tax)],
            ["Refunded", money(sales.value.refunded)],
            ["Known processing fees", money(sales.value.processing_fee)],
            ["Fees awaiting reconciliation", String(sales.value.pending_fees)],
          ].map(([title, value]) => (
            <div key={title}>
              <dt>{title}</dt>
              <dd>{value}</dd>
            </div>
          ))}
        </dl>
      )}
    </>
  );
}
