import { useEffect, useRef, useState, type ReactNode } from "react";
import { api, APIError, uploadPhoto } from "./api";
export function Modal({
  children,
  close,
  label,
}: {
  children: ReactNode;
  close: () => void;
  label: string;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    dialog.current?.showModal();
    return () => {
      dialog.current?.close();
      previous?.focus();
    };
  }, []);
  return (
    <dialog
      ref={dialog}
      className="modal"
      aria-label={label}
      onCancel={(event) => {
        event.preventDefault();
        close();
      }}
    >
      {children}
    </dialog>
  );
}
export function useData<T>(path: string | null) {
  const [value, setValue] = useState<T>(),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(false),
    [revision, setRevision] = useState(0);
  const previous = useRef(path);
  useEffect(() => {
    let alive = true;
    if (previous.current !== path) {
      setValue(undefined);
      previous.current = path;
    }
    if (!path) return;
    setLoading(true);
    setError("");
    api<T>(path)
      .then((v) => {
        if (alive) setValue(v);
      })
      .catch((e) => {
        if (alive) {
          if (e instanceof APIError && [401, 403, 404].includes(e.status))
            setValue(undefined);
          setError(e.message);
        }
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [path, revision]);
  return { value, error, loading, reload: () => setRevision((x) => x + 1) };
}
export function DataState({
  error,
  loading,
  retry,
  children,
}: {
  error: string;
  loading: boolean;
  retry: () => void;
  children?: ReactNode;
}) {
  return (
    <>
      {error ? (
        <p className="notice error" role="alert">
          {error} <button onClick={retry}>Retry</button>
        </p>
      ) : loading ? (
        <p className="quiet" role="status">
          Loading…
        </p>
      ) : null}
      {children}
    </>
  );
}
export function Photo({ url, label }: { url?: string; label: string }) {
  const [failed, setFailed] = useState(false),
    [retry, setRetry] = useState(0);
  useEffect(() => setFailed(false), [url]);
  return (
    <div className="photo">
      {url && !failed ? (
        <img
          key={retry}
          src={url}
          alt={label}
          loading="lazy"
          onError={() => setFailed(true)}
        />
      ) : (
        <span>
          {failed ? "Photo unavailable" : "No photo"}
          {failed && (
            <button
              onClick={() => {
                setFailed(false);
                setRetry((x) => x + 1);
              }}
            >
              Retry
            </button>
          )}
        </span>
      )}
    </div>
  );
}
export function PhotoInput({
  label,
  onUploaded,
  disabled = false,
}: {
  label: string;
  onUploaded: (id: string) => void;
  disabled?: boolean;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  return (
    <label>
      {label}
      <input
        type="file"
        accept="image/jpeg,image/png,image/webp,image/heic"
        disabled={disabled || busy}
        onChange={async (e) => {
          const file = e.target.files?.[0];
          if (!file) return;
          setBusy(true);
          setError("");
          try {
            onUploaded(await uploadPhoto(file));
          } catch (error) {
            setError((error as Error).message);
          } finally {
            setBusy(false);
            e.target.value = "";
          }
        }}
      />
      {busy && <small role="status">Uploading and reviewing photo…</small>}
      {error && <small role="alert">{error}</small>}
    </label>
  );
}
export function ConfirmButton({
  title,
  onConfirm,
  disabled = false,
}: {
  title: string;
  onConfirm: () => Promise<void>;
  disabled?: boolean;
}) {
  const [confirm, setConfirm] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  return (
    <>
      <button disabled={disabled || busy} onClick={() => setConfirm(true)}>
        {title}
      </button>
      {confirm && (
        <div
          className="confirmation"
          role="group"
          aria-label={"Confirm " + title}
        >
          <p>Confirm {title.toLowerCase()} for this order?</p>
          <button disabled={busy} onClick={() => setConfirm(false)}>
            Keep unchanged
          </button>
          <button
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              setError("");
              try {
                await onConfirm();
                setConfirm(false);
              } catch (e) {
                setError((e as Error).message);
              } finally {
                setBusy(false);
              }
            }}
          >
            {busy ? "Confirming…" : "Confirm"}
          </button>
          {error && <p role="alert">{error}</p>}
        </div>
      )}
    </>
  );
}
