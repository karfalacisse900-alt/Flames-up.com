import { FormEvent, ReactNode, useCallback, useEffect, useMemo, useState } from 'react';
import { AdminApi, ApiError, API_BASE, login } from './api';
import type {
  AdminComment,
  AdminMedia,
  AdminPost,
  AdminSession,
  AdminUser,
  AuditLog,
  DashboardResponse,
  Paginated,
  ReportDetail,
  ReportSummary,
  ReportedMessageDetail,
} from './types';

type ViewKey = 'dashboard' | 'reports' | 'posts' | 'comments' | 'users' | 'messages' | 'discover' | 'audit' | 'settings';
type PostAction = 'remove' | 'restore' | 'discover' | 'safe';

type ActionDialogState = {
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  defaultReason?: string;
  targetPreview?: ReactNode;
  onConfirm: (reason: string, note: string) => Promise<void>;
};

type MediaPreviewModel = {
  type: 'image' | 'video' | 'none';
  thumbnailUrl: string;
  previewUrl: string;
  posterUrl: string;
  iframeUrl: string;
  aspectRatio: number;
};

const TOKEN_KEY = 'captro_admin_token';

const navItems: Array<{ key: ViewKey; label: string }> = [
  { key: 'dashboard', label: 'Dashboard' },
  { key: 'reports', label: 'Reports' },
  { key: 'posts', label: 'Posts' },
  { key: 'comments', label: 'Comments' },
  { key: 'users', label: 'Users' },
  { key: 'messages', label: 'Messages' },
  { key: 'discover', label: 'Discover' },
  { key: 'audit', label: 'Audit Logs' },
  { key: 'settings', label: 'Settings' },
];

const reportReasons = [
  'all',
  'harassment_or_bullying',
  'hate_speech',
  'threats_or_violence',
  'doxxing_or_private_information',
  'spam_or_scam',
  'impersonation',
  'stolen_content_or_copyright',
  'sexual_content_or_exploitation',
  'illegal_or_dangerous_activity',
  'self_harm_concern',
  'false_or_misleading_content',
  'dont_want_to_see',
  'other',
];

const postCategories = ['all', 'photography', 'outdoors', 'outfits', 'travel', 'events', 'nightlife', 'art', 'lifestyle', 'fitness'];
const editablePostCategories = postCategories.filter((category) => category !== 'all');

function formatDate(value?: string | null) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    year: '2-digit',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

function titleCase(value?: string | null) {
  return String(value || 'unknown')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function compactId(value?: string) {
  if (!value) return '-';
  return value.length > 12 ? `${value.slice(0, 8)}...${value.slice(-4)}` : value;
}

function clampText(value?: string | null, fallback = 'No text') {
  const clean = String(value || '').trim();
  return clean || fallback;
}

function postCategory(post: AdminPost) {
  return post.primary_category || post.category || 'lifestyle';
}

function formatConfidence(value?: number) {
  if (typeof value !== 'number' || Number.isNaN(value)) return '0%';
  return `${Math.round(Math.max(0, Math.min(1, value)) * 100)}%`;
}

function statusClass(value?: string) {
  const clean = String(value || '').toLowerCase();
  if (['urgent', 'high', 'banned', 'removed', 'declined', 'failed'].includes(clean)) return 'badge danger';
  if (['medium', 'suspended', 'under_review', 'escalated', 'hidden', 'pending'].includes(clean)) return 'badge warning';
  if (['active', 'action_taken', 'closed', 'restored', 'safe'].includes(clean)) return 'badge success';
  return 'badge';
}

function can(session: AdminSession, permission: string) {
  return session.permissions.includes('*') || session.permissions.includes(permission);
}

function apiOrigin() {
  try {
    return new URL(API_BASE).origin;
  } catch {
    return 'https://api.flames-up.com';
  }
}

function absoluteMediaUrl(value?: string | null) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (raw.startsWith('cfstream:')) return raw;
  if (raw.startsWith('/')) return `${apiOrigin()}${raw}`;
  return raw;
}

function streamUid(value?: string | null) {
  const raw = String(value || '').trim();
  if (!raw.startsWith('cfstream:')) return '';
  return raw.replace('cfstream:', '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 128);
}

function streamPoster(value?: string | null) {
  const uid = streamUid(value);
  return uid ? `https://videodelivery.net/${uid}/thumbnails/thumbnail.jpg?time=1s&height=720` : '';
}

function streamIframe(value?: string | null) {
  const uid = streamUid(value);
  return uid ? `https://iframe.videodelivery.net/${uid}` : '';
}

function asStringArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item || '')).filter(Boolean);
  if (typeof value !== 'string') return [];
  const trimmed = value.trim();
  if (!trimmed) return [];
  try {
    const parsed = JSON.parse(trimmed);
    return Array.isArray(parsed) ? parsed.map((item) => String(item || '')).filter(Boolean) : [trimmed];
  } catch {
    return [trimmed];
  }
}

function mediaFromFields(media?: AdminMedia | null, post?: AdminPost | null): MediaPreviewModel {
  const mediaType = String(media?.media_type || media?.type || post?.media_type || post?.media_types?.[0] || '').toLowerCase();
  const rawPreview = absoluteMediaUrl(media?.feed_media_url || media?.feedUrl || post?.feed_media_url || post?.feed_media_urls?.[0] || post?.image || post?.images?.[0]);
  const rawThumb = absoluteMediaUrl(media?.thumbnail_url || media?.thumbnailUrl || post?.thumbnail_url || post?.thumbnail_urls?.[0]);
  const rawPoster = absoluteMediaUrl(media?.poster_url || media?.posterUrl || post?.poster_url || post?.poster_urls?.[0]);
  const fallbackImages = asStringArray(post?.images);
  const fallbackUrl = absoluteMediaUrl(rawPreview || rawThumb || rawPoster || fallbackImages[0]);
  const isVideo = mediaType.includes('video') || fallbackUrl.startsWith('cfstream:') || /\.(mp4|mov|m4v|webm|m3u8)(\?|#|$)/i.test(fallbackUrl);
  const poster = fallbackUrl.startsWith('cfstream:') ? streamPoster(fallbackUrl) : rawPoster || rawThumb;
  const preview = fallbackUrl.startsWith('cfstream:') ? '' : fallbackUrl;
  const ratio = Number(media?.aspect_ratio || media?.aspectRatio || post?.aspect_ratio || 0) || 3 / 4;

  if (!fallbackUrl && !poster) {
    return { type: 'none', thumbnailUrl: '', previewUrl: '', posterUrl: '', iframeUrl: '', aspectRatio: ratio };
  }

  return {
    type: isVideo ? 'video' : 'image',
    thumbnailUrl: isVideo ? (poster || rawThumb || preview) : (rawThumb || preview || poster),
    previewUrl: preview,
    posterUrl: poster || rawThumb,
    iframeUrl: fallbackUrl.startsWith('cfstream:') ? streamIframe(fallbackUrl) : '',
    aspectRatio: ratio,
  };
}

function mediaFromPost(post?: AdminPost | null) {
  return mediaFromFields(post?.media?.[0] || null, post);
}

function useDebouncedValue<T>(value: T, delay = 250) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const handle = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(handle);
  }, [value, delay]);
  return debounced;
}

function useAdminLoad<T>(loader: () => Promise<T>, deps: unknown[], enabled = true) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [error, setError] = useState('');

  const reload = useCallback(async () => {
    if (!enabled) {
      setLoading(false);
      setData(null);
      setError('');
      return;
    }
    setLoading(true);
    setError('');
    try {
      setData(await loader());
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Could not load data');
    } finally {
      setLoading(false);
    }
  }, deps);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { data, loading, error, reload };
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="empty-state">
      <strong>{title}</strong>
      <span>{body}</span>
    </div>
  );
}

function LoadingRows({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? 'skeleton-list compact' : 'skeleton-list'} aria-label="Loading">
      {Array.from({ length: compact ? 3 : 6 }).map((_, index) => <div className="skeleton-row" key={index} />)}
    </div>
  );
}

function ErrorBanner({ message }: { message?: string }) {
  if (!message) return null;
  return <div className="error-banner">{message}</div>;
}

function MediaPreview({ media, post, size = 'table' }: { media?: AdminMedia | null; post?: AdminPost | null; size?: 'table' | 'card' | 'detail' }) {
  const [failed, setFailed] = useState(false);
  const model = mediaFromFields(media || null, post || null);
  const label = model.type === 'video' ? 'Video' : model.type === 'image' ? 'Photo' : 'No media';

  useEffect(() => setFailed(false), [model.thumbnailUrl, model.previewUrl, model.iframeUrl]);

  if (model.type === 'none' || failed) {
    return (
      <div className={`media-preview ${size} empty-media`}>
        <span>{failed ? 'Media failed to load' : 'No media'}</span>
      </div>
    );
  }

  if (size === 'detail' && model.type === 'video') {
    return (
      <div className="media-detail-wrap">
        <span className="media-type-badge">{label}</span>
        {model.iframeUrl ? (
          <iframe className="media-frame" src={model.iframeUrl} allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture;" allowFullScreen title="Video preview" />
        ) : (
          <video className="media-detail" controls preload="metadata" poster={model.posterUrl || model.thumbnailUrl} onError={() => setFailed(true)}>
            <source src={model.previewUrl} />
          </video>
        )}
      </div>
    );
  }

  const src = size === 'detail' ? (model.previewUrl || model.thumbnailUrl || model.posterUrl) : (model.thumbnailUrl || model.posterUrl || model.previewUrl);
  return (
    <div className={`media-preview ${size}`}>
      <span className="media-type-badge">{label}</span>
      <img src={src} alt="" onError={() => setFailed(true)} />
    </div>
  );
}

function Avatar({ src, label }: { src?: string; label: string }) {
  if (src) return <img className="avatar" src={src} alt="" />;
  return <span className="avatar fallback">{label.slice(0, 1).toUpperCase()}</span>;
}

function LoginScreen({ onLogin }: { onLogin: (token: string) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      const payload = await login(email, password);
      onLogin(payload.access_token);
    } catch (error) {
      const message = error instanceof ApiError && error.status === 403
        ? 'This account is not allowed to access Captro Admin.'
        : error instanceof Error ? error.message : 'Login failed';
      setError(message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="login-shell">
      <form className="login-card" onSubmit={submit}>
        <div className="brand-mark">C</div>
        <span className="eyebrow">Production access</span>
        <h1>Captro Admin</h1>
        <p>Private moderation access for approved Captro staff only.</p>
        <ErrorBanner message={error} />
        <label>
          Email
          <input autoComplete="email" inputMode="email" value={email} onChange={(event) => setEmail(event.target.value)} required />
        </label>
        <label>
          Password
          <input autoComplete="current-password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} required />
        </label>
        <button className="primary-button full-width" disabled={submitting}>{submitting ? 'Checking access...' : 'Sign in'}</button>
        <small>No public signup. Backend role checks run before any admin data loads.</small>
      </form>
    </main>
  );
}

function ActionDialog({ state, onClose }: { state: ActionDialogState; onClose: () => void }) {
  const [reason, setReason] = useState(state.defaultReason || '');
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    if (!reason.trim()) {
      setError('A reason is required.');
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      await state.onConfirm(reason.trim(), note.trim());
      onClose();
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Action failed');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation">
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="action-title">
        <div className="modal-heading">
          <span className={state.danger ? 'badge danger' : 'badge warning'}>{state.danger ? 'Destructive action' : 'Moderation action'}</span>
          <h2 id="action-title">{state.title}</h2>
          <p>{state.message}</p>
        </div>
        {state.targetPreview ? <div className="modal-preview">{state.targetPreview}</div> : null}
        <label>
          Reason
          <textarea value={reason} onChange={(event) => setReason(event.target.value)} rows={4} autoFocus />
        </label>
        <label>
          Internal note
          <textarea value={note} onChange={(event) => setNote(event.target.value)} rows={3} />
        </label>
        <ErrorBanner message={error} />
        <div className="modal-actions">
          <button className="ghost-button" onClick={onClose} type="button">Cancel</button>
          <button className={state.danger ? 'danger-button' : 'primary-button'} onClick={submit} disabled={submitting} type="button">
            {submitting ? 'Saving...' : state.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function AdminLayout({
  session,
  active,
  setActive,
  onLogout,
  children,
}: {
  session: AdminSession;
  active: ViewKey;
  setActive: (view: ViewKey) => void;
  onLogout: () => void;
  children: ReactNode;
}) {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <div className="brand-mark small">C</div>
          <div>
            <strong>Captro Admin</strong>
            <span>Moderation console</span>
          </div>
        </div>
        <nav aria-label="Admin navigation">
          {navItems.map((item) => (
            <button key={item.key} className={active === item.key ? 'active' : ''} onClick={() => setActive(item.key)}>
              {item.label}
            </button>
          ))}
        </nav>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="topbar-title">
            <strong>Captro Admin</strong>
            <span className="env-pill">Production</span>
          </div>
          <div className="topbar-user">
            <Avatar src={session.user.profile_image} label={session.user.full_name || session.user.username || 'A'} />
            <div>
              <strong>{session.user.full_name || session.user.username || 'Admin'}</strong>
              <span className={statusClass(session.role)}>{titleCase(session.role)}</span>
            </div>
            <button className="ghost-button" onClick={onLogout}>Logout</button>
          </div>
        </header>
        {children}
      </div>
    </div>
  );
}

function PageHeader({ title, subtitle, onRefresh, actions }: { title: string; subtitle: string; onRefresh?: () => void; actions?: ReactNode }) {
  return (
    <div className="page-header">
      <div>
        <span className="eyebrow">Captro moderation</span>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <div className="header-actions">
        {actions}
        {onRefresh ? <button className="secondary-button" onClick={onRefresh}>Refresh</button> : null}
      </div>
    </div>
  );
}

function Panel({ title, children, className = '' }: { title: string; children: ReactNode; className?: string }) {
  return (
    <section className={`panel ${className}`}>
      <h2>{title}</h2>
      {children}
    </section>
  );
}

function DashboardPage({ token, openReport }: { token: string; openReport: (id: string) => void }) {
  const { data, loading, error, reload } = useAdminLoad<DashboardResponse>(() => AdminApi.dashboard(token), [token]);
  const cards = data?.cards || {};
  const cardOrder = [
    ['open_reports', 'Open reports'],
    ['reports_today', 'Reports today'],
    ['posts_removed_today', 'Posts removed'],
    ['users_suspended_today', 'Users suspended'],
    ['urgent_reports', 'Urgent reports'],
    ['upload_failures_24h', 'Upload failures'],
    ['new_accounts_today', 'New accounts'],
  ];
  return (
    <section className="page">
      <PageHeader title="Dashboard" subtitle="Moderation health, safety queues, and urgent work." onRefresh={reload} />
      <ErrorBanner message={error} />
      {loading ? <LoadingRows /> : (
        <>
          <div className="metric-grid">
            {cardOrder.map(([key, label]) => (
              <article className="metric-card" key={key}>
                <span>{label}</span>
                <strong>{cards[key] || 0}</strong>
              </article>
            ))}
          </div>
          <Panel title="Priority queue">
            {data?.queues.new_reports.length ? (
              <div className="admin-table compact-table">
                <div className="table-head reports-head">
                  <span>Priority</span>
                  <span>Reason</span>
                  <span>Target</span>
                  <span>Created</span>
                  <span>Status</span>
                </div>
                {data.queues.new_reports.map((report) => <ReportRow key={report.id} report={report} onOpen={() => openReport(report.id)} />)}
              </div>
            ) : <EmptyState title="No open reports" body="The queue is clear right now." />}
          </Panel>
        </>
      )}
    </section>
  );
}

function ReportRow({ report, onOpen }: { report: ReportSummary; onOpen: () => void }) {
  return (
    <button className="table-row report-row" onClick={onOpen}>
      <span className={statusClass(report.priority)}>{titleCase(report.priority)}</span>
      <div>
        <strong>{titleCase(report.reason)}</strong>
        <span>{compactId(report.id)}</span>
      </div>
      <div className="with-media">
        <MediaPreview media={report.target_media || null} size="table" />
        <span>{titleCase(report.target_type)} - {report.target_user.full_name || report.target_user.username || report.reported_id}</span>
      </div>
      <time>{formatDate(report.created_at)}</time>
      <span className={statusClass(report.status)}>{titleCase(report.status)}</span>
    </button>
  );
}

function ReportsPage({
  token,
  selectedId,
  setSelectedId,
  openAction,
}: {
  token: string;
  selectedId: string;
  setSelectedId: (id: string) => void;
  openAction: (state: ActionDialogState) => void;
}) {
  const [status, setStatus] = useState('open');
  const [reason, setReason] = useState('all');
  const [targetType, setTargetType] = useState('all');
  const [fromDate, setFromDate] = useState('');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search);
  const query = useMemo(() => {
    const params = new URLSearchParams();
    params.set('status', status);
    params.set('reason', reason);
    params.set('target_type', targetType);
    params.set('limit', '40');
    if (fromDate) params.set('from', fromDate);
    if (debouncedSearch) params.set('search', debouncedSearch);
    return `?${params.toString()}`;
  }, [status, reason, targetType, fromDate, debouncedSearch]);
  const { data, loading, error, reload } = useAdminLoad<Paginated<ReportSummary>>(() => AdminApi.reports(token, query), [token, query]);
  const detail = useAdminLoad<{ report: ReportDetail } | null>(
    () => selectedId ? AdminApi.report(token, selectedId) : Promise.resolve(null),
    [token, selectedId],
    !!selectedId,
  );
  const [note, setNote] = useState('');

  async function changeReport(action: string, title: string, danger = false) {
    if (!selectedId || !detail.data?.report) return;
    const report = detail.data.report;
    openAction({
      title,
      message: `This updates report ${compactId(selectedId)}.`,
      confirmLabel: title,
      danger,
      targetPreview: <ReportActionPreview report={report} />,
      onConfirm: async (reasonText, internalNote) => {
        await AdminApi.reportAction(token, selectedId, { action, reason: reasonText, note: internalNote });
        await reload();
        await detail.reload();
      },
    });
  }

  async function addNote() {
    if (!selectedId || !note.trim()) return;
    await AdminApi.reportNote(token, selectedId, note.trim());
    setNote('');
    await detail.reload();
  }

  return (
    <section className="page split-page wide-detail">
      <div>
        <PageHeader title="Reports" subtitle="Review reported posts, comments, profiles, and messages." onRefresh={reload} />
        <div className="filter-bar">
          <input placeholder="Search report, user, or content id" value={search} onChange={(event) => setSearch(event.target.value)} />
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="open">Open</option>
            <option value="all">All statuses</option>
            <option value="under_review">In Review</option>
            <option value="escalated">Escalated</option>
            <option value="action_taken">Action Taken</option>
            <option value="dismissed">Dismissed</option>
          </select>
          <select value={reason} onChange={(event) => setReason(event.target.value)}>
            {reportReasons.map((item) => <option value={item} key={item}>{item === 'all' ? 'All reasons' : titleCase(item)}</option>)}
          </select>
          <select value={targetType} onChange={(event) => setTargetType(event.target.value)}>
            <option value="all">All targets</option>
            <option value="post">Posts</option>
            <option value="comment">Comments</option>
            <option value="user">Users</option>
            <option value="profile">Profiles</option>
            <option value="message">Messages</option>
            <option value="discover_post">Discover posts</option>
            <option value="story">Stories</option>
            <option value="handshake_request">Handshake requests</option>
          </select>
          <input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} aria-label="Created after" />
        </div>
        <ErrorBanner message={error} />
        {loading ? <LoadingRows /> : data?.results.length ? (
          <div className="admin-table">
            <div className="table-head reports-head">
              <span>Report</span>
              <span>Reason</span>
              <span>Target user</span>
              <span>Created</span>
              <span>Status</span>
            </div>
            {data.results.map((report) => <ReportRow key={report.id} report={report} onOpen={() => setSelectedId(report.id)} />)}
          </div>
        ) : <EmptyState title="No reports found" body="Try another filter or refresh the queue." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows compact /> : detail.data?.report ? (
          <ReportDetailView
            report={detail.data.report}
            note={note}
            setNote={setNote}
            addNote={addNote}
            onMarkReview={() => void changeReport('under_review', 'Mark in review')}
            onDismiss={() => void changeReport('dismiss', 'Dismiss report')}
            onEscalate={() => void changeReport('escalate', 'Escalate report')}
            onRemove={() => void changeReport('remove_content', 'Remove target content', true)}
          />
        ) : <EmptyState title="Select a report" body="Report details, media, notes, and actions will appear here." />}
      </aside>
    </section>
  );
}

function ReportActionPreview({ report }: { report: ReportDetail }) {
  const targetPost = reportTargetPost(report);
  return (
    <div className="action-preview">
      {targetPost ? <MediaPreview post={targetPost} size="table" /> : <MediaPreview media={report.target_media || null} size="table" />}
      <div>
        <strong>{titleCase(report.target_type)} - {titleCase(report.reason)}</strong>
        <span>{clampText(report.preview || report.details, 'No text preview')}</span>
      </div>
    </div>
  );
}

function reportTargetPost(report: ReportDetail): AdminPost | null {
  const target = report.target as { type?: string; post?: AdminPost } | undefined;
  return target?.type === 'post' && target.post ? target.post : null;
}

function ReportDetailView({
  report,
  note,
  setNote,
  addNote,
  onMarkReview,
  onDismiss,
  onEscalate,
  onRemove,
}: {
  report: ReportDetail;
  note: string;
  setNote: (value: string) => void;
  addNote: () => void;
  onMarkReview: () => void;
  onDismiss: () => void;
  onEscalate: () => void;
  onRemove: () => void;
}) {
  const targetPost = reportTargetPost(report);
  return (
    <div className="detail-stack">
      <div className="detail-title">
        <span className={statusClass(report.priority)}>{titleCase(report.priority)}</span>
        <h2>{titleCase(report.reason)}</h2>
        <p>{titleCase(report.target_type)} - {formatDate(report.created_at)} - {compactId(report.id)}</p>
      </div>
      {targetPost ? <MediaPreview post={targetPost} size="detail" /> : <MediaPreview media={report.target_media || null} size="detail" />}
      <div className="preview-box">
        <strong>Target preview</strong>
        <p>{report.preview || report.details || 'No text preview available.'}</p>
      </div>
      <div className="detail-meta">
        <span>Reporter</span>
        <strong>{report.reporter.full_name || report.reporter.username || report.reporter_id}</strong>
        <span>Target user</span>
        <strong>{report.target_user.full_name || report.target_user.username || report.reported_id}</strong>
      </div>
      <div className="action-grid">
        <button className="secondary-button" onClick={onMarkReview}>In Review</button>
        <button className="secondary-button" onClick={onEscalate}>Escalate</button>
        <button className="ghost-button" onClick={onDismiss}>Dismiss</button>
        <button className="danger-button" onClick={onRemove}>Remove</button>
      </div>
      <label>
        Internal note
        <textarea rows={3} value={note} onChange={(event) => setNote(event.target.value)} />
      </label>
      <button className="secondary-button" onClick={addNote} disabled={!note.trim()}>Add note</button>
      <Panel title="History" className="flat-panel">
        {report.notes?.length ? report.notes.map((item) => (
          <div className="note" key={item.id}>
            <strong>{item.admin.full_name || item.admin.username || 'Admin'}</strong>
            <span>{formatDate(item.created_at)}</span>
            <p>{item.note}</p>
          </div>
        )) : <EmptyState title="No notes" body="Internal notes will appear here." />}
      </Panel>
    </div>
  );
}

function PostModerationPage({
  token,
  session,
  surface = 'posts',
  openAction,
  onViewAuthor,
}: {
  token: string;
  session: AdminSession;
  surface?: 'posts' | 'discover';
  openAction: (state: ActionDialogState) => void;
  onViewAuthor: (id: string) => void;
}) {
  const [status, setStatus] = useState('all');
  const [category, setCategory] = useState(surface === 'discover' ? 'all' : 'all');
  const [search, setSearch] = useState('');
  const [selectedPostId, setSelectedPostId] = useState('');
  const debouncedSearch = useDebouncedValue(search);
  const query = useMemo(() => {
    const params = new URLSearchParams();
    params.set('status', status);
    params.set('limit', '36');
    if (category !== 'all') params.set('category', category);
    if (surface === 'discover') params.set('surface', 'discover');
    if (debouncedSearch) params.set('search', debouncedSearch);
    return `?${params.toString()}`;
  }, [status, category, surface, debouncedSearch]);
  const list = useAdminLoad<Paginated<AdminPost>>(() => AdminApi.posts(token, query), [token, query]);
  const detail = useAdminLoad<{ post: AdminPost; actions?: AuditLog[] } | null>(
    () => selectedPostId ? AdminApi.post(token, selectedPostId) as Promise<{ post: AdminPost; actions?: AuditLog[] }> : Promise.resolve(null),
    [token, selectedPostId],
    !!selectedPostId,
  );

  function act(post: AdminPost, label: string, action: PostAction) {
    openAction({
      title: label,
      message: `${label} post ${compactId(post.id)}.`,
      confirmLabel: label,
      danger: action === 'remove' || action === 'discover',
      targetPreview: <PostActionPreview post={post} />,
      onConfirm: async (reason, note) => {
        const body = { reason, note };
        if (action === 'remove') await AdminApi.removePost(token, post.id, body);
        if (action === 'restore') await AdminApi.restorePost(token, post.id, body);
        if (action === 'discover') await AdminApi.removeFromDiscover(token, post.id, body);
        if (action === 'safe') await AdminApi.markPostSafe(token, post.id, body);
        await list.reload();
        if (selectedPostId) await detail.reload();
      },
    });
  }

  function changeCategory(post: AdminPost, category: string) {
    openAction({
      title: 'Change Discover category',
      message: `Move post ${compactId(post.id)} to ${titleCase(category)}.`,
      confirmLabel: 'Change category',
      targetPreview: <PostActionPreview post={post} />,
      onConfirm: async (reason, note) => {
        await AdminApi.changePostCategory(token, post.id, { primary_category: category, reason, note });
        await list.reload();
        if (selectedPostId) await detail.reload();
      },
    });
  }

  const title = surface === 'discover' ? 'Discover Moderation' : 'Post Moderation';
  const subtitle = surface === 'discover'
    ? 'Review public gallery content, categories, and visual spam before it spreads.'
    : 'Review post media, authors, captions, status, and moderation actions.';

  return (
    <section className="page split-page">
      <div>
        <PageHeader title={title} subtitle={subtitle} onRefresh={list.reload} />
        <div className="filter-bar">
          <input placeholder="Search post, caption, or username" value={search} onChange={(event) => setSearch(event.target.value)} />
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="all">All statuses</option>
            <option value="active">Active</option>
            <option value="removed">Removed</option>
            <option value="hidden">Hidden</option>
          </select>
          <select value={category} onChange={(event) => setCategory(event.target.value)}>
            {postCategories.map((item) => <option value={item} key={item}>{item === 'all' ? 'All categories' : titleCase(item)}</option>)}
          </select>
        </div>
        <ErrorBanner message={list.error} />
        {list.loading ? <LoadingRows /> : list.data?.results.length ? (
          <div className="admin-table post-table">
            <div className="table-head posts-head">
              <span>Media</span>
              <span>Post</span>
              <span>Author</span>
              <span>Status</span>
              <span>Counts</span>
              <span>Actions</span>
            </div>
            {list.data.results.map((post) => (
              <PostRow
                key={post.id}
                post={post}
                session={session}
                selected={selectedPostId === post.id}
                onView={() => setSelectedPostId(post.id)}
                onAction={act}
                onViewAuthor={() => onViewAuthor(post.author.id)}
              />
            ))}
          </div>
        ) : <EmptyState title="No posts found" body="Try another filter or refresh the moderation list." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows compact /> : detail.data?.post ? (
          <PostDetailPanel post={detail.data.post} actions={detail.data.actions || []} session={session} onAction={act} onCategoryChange={changeCategory} onViewAuthor={() => onViewAuthor(detail.data?.post.author.id || '')} />
        ) : <EmptyState title="Select a post" body="Media preview, caption, metadata, and actions will appear here." />}
      </aside>
    </section>
  );
}

function PostActionPreview({ post }: { post: AdminPost }) {
  return (
    <div className="action-preview">
      <MediaPreview post={post} size="table" />
      <div>
        <strong>@{post.author.username || 'unknown'} - {titleCase(postCategory(post))}</strong>
        <span>{clampText(post.content || post.title, 'No caption')}</span>
      </div>
    </div>
  );
}

function PostRow({
  post,
  session,
  selected,
  onView,
  onAction,
  onViewAuthor,
}: {
  post: AdminPost;
  session: AdminSession;
  selected: boolean;
  onView: () => void;
  onAction: (post: AdminPost, label: string, action: PostAction) => void;
  onViewAuthor: () => void;
}) {
  return (
    <div className={selected ? 'table-row post-row selected' : 'table-row post-row'}>
      <button className="media-button" onClick={onView} aria-label="View post">
        <MediaPreview post={post} size="table" />
      </button>
      <button className="text-cell" onClick={onView}>
        <strong>{clampText(post.title || post.content, 'Untitled post')}</strong>
        <span>{titleCase(postCategory(post))} - {formatDate(post.created_at)}</span>
      </button>
      <button className="author-cell" onClick={onViewAuthor}>
        <Avatar src={post.author.profile_image} label={post.author.full_name || post.author.username || 'U'} />
        <span>@{post.author.username || 'unknown'}</span>
      </button>
      <span className={statusClass(post.status)}>{titleCase(post.status)}</span>
      <span className="muted">{post.likes_count || 0} likes / {post.comments_count || 0} comments</span>
      <div className="row-actions">
        <button onClick={onView}>View</button>
        {can(session, 'content:write') && post.status === 'removed'
          ? <button onClick={() => onAction(post, 'Restore', 'restore')}>Restore</button>
          : can(session, 'content:write') ? <button className="danger-text" onClick={() => onAction(post, 'Remove', 'remove')}>Remove</button> : null}
        {can(session, 'content:write') ? <button onClick={() => onAction(post, 'Mark safe', 'safe')}>Safe</button> : null}
        {can(session, 'content:write') ? <button onClick={() => onAction(post, 'Remove from Discover', 'discover')}>Discover</button> : null}
      </div>
    </div>
  );
}

function PostDetailPanel({
  post,
  actions,
  session,
  onAction,
  onCategoryChange,
  onViewAuthor,
}: {
  post: AdminPost;
  actions: AuditLog[];
  session: AdminSession;
  onAction: (post: AdminPost, label: string, action: PostAction) => void;
  onCategoryChange: (post: AdminPost, category: string) => void;
  onViewAuthor: () => void;
}) {
  const [selectedCategory, setSelectedCategory] = useState(postCategory(post));
  useEffect(() => {
    setSelectedCategory(postCategory(post));
  }, [post.id, post.primary_category, post.category]);

  return (
    <div className="detail-stack">
      <div className="detail-title">
        <span className={statusClass(post.status)}>{titleCase(post.status)}</span>
        <h2>{clampText(post.title || post.content, 'Untitled post')}</h2>
        <p>@{post.author.username || 'unknown'} - {formatDate(post.created_at)}</p>
      </div>
      <MediaPreview post={post} size="detail" />
      <div className="detail-meta">
        <span>Category</span>
        <strong>{titleCase(postCategory(post))}</strong>
        <span>AI confidence</span>
        <strong>{formatConfidence(post.category_confidence)} / {titleCase(post.category_status || 'low_confidence')}</strong>
        <span>Source</span>
        <strong>{titleCase(post.category_source || 'fallback')}</strong>
        <span>Visibility</span>
        <strong>{titleCase(post.visibility)}</strong>
        <span>Counts</span>
        <strong>{post.likes_count || 0} likes / {post.comments_count || 0} comments / {post.saves_count || 0} saves</strong>
      </div>
      <div className="preview-box">
        <strong>Discover tags</strong>
        <p>{post.tags?.length ? post.tags.map((tag) => `#${tag}`).join(' ') : 'No category tags saved yet.'}</p>
      </div>
      {can(session, 'content:write') ? (
        <div className="category-correction">
          <div>
            <strong>Correct Discover category</strong>
            <span>Requires a reason and writes a category_changed audit log.</span>
          </div>
          <select value={selectedCategory} onChange={(event) => setSelectedCategory(event.target.value)}>
            {editablePostCategories.map((item) => <option value={item} key={item}>{titleCase(item)}</option>)}
          </select>
          <button
            className="secondary-button"
            disabled={selectedCategory === postCategory(post)}
            onClick={() => onCategoryChange(post, selectedCategory)}
          >
            Change
          </button>
        </div>
      ) : null}
      <div className="preview-box">
        <strong>Caption</strong>
        <p>{clampText(post.content, 'No caption')}</p>
      </div>
      <div className="action-grid">
        <button className="secondary-button" onClick={onViewAuthor}>View author</button>
        {can(session, 'content:write') ? <button className="secondary-button" onClick={() => onAction(post, 'Mark safe', 'safe')}>Mark safe</button> : null}
        {can(session, 'content:write') && post.status === 'removed'
          ? <button className="primary-button" onClick={() => onAction(post, 'Restore', 'restore')}>Restore</button>
          : can(session, 'content:write') ? <button className="danger-button" onClick={() => onAction(post, 'Remove', 'remove')}>Remove</button> : null}
      </div>
      <Panel title="Action history" className="flat-panel">
        {actions.length ? actions.map((action) => (
          <div className="note" key={action.id}>
            <strong>{titleCase(action.action_type)}</strong>
            <span>{formatDate(action.created_at)}</span>
            <p>{action.reason || action.internal_note || action.note || 'No reason recorded'}</p>
          </div>
        )) : <EmptyState title="No recent actions" body="Post moderation actions will appear in the audit log." />}
      </Panel>
    </div>
  );
}

function UsersPage({
  token,
  session,
  selectedUserId,
  setSelectedUserId,
  openAction,
}: {
  token: string;
  session: AdminSession;
  selectedUserId: string;
  setSelectedUserId: (id: string) => void;
  openAction: (state: ActionDialogState) => void;
}) {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const debouncedSearch = useDebouncedValue(search);
  const query = useMemo(() => {
    const params = new URLSearchParams();
    params.set('limit', '40');
    if (debouncedSearch) params.set('search', debouncedSearch);
    if (status !== 'all') params.set('status', status);
    return `?${params.toString()}`;
  }, [debouncedSearch, status]);
  const list = useAdminLoad<Paginated<AdminUser>>(() => AdminApi.users(token, query), [token, query]);
  const detail = useAdminLoad<{ user: AdminUser; restrictions: unknown[]; actions: AuditLog[]; recent_posts: AdminPost[] } | null>(
    () => selectedUserId ? AdminApi.user(token, selectedUserId) : Promise.resolve(null),
    [token, selectedUserId],
    !!selectedUserId,
  );

  function userAction(user: AdminUser, action: 'warn' | 'restrict' | 'suspend' | 'ban' | 'unban' | 'force') {
    const labels = {
      warn: 'Warn user',
      restrict: 'Restrict user',
      suspend: 'Suspend user',
      ban: 'Ban user',
      unban: 'Unban user',
      force: 'Force username change',
    };
    openAction({
      title: labels[action],
      message: `${labels[action]} for ${user.full_name || user.username || user.id}.`,
      confirmLabel: labels[action],
      danger: ['ban', 'suspend', 'force'].includes(action),
      targetPreview: <UserActionPreview user={user} />,
      onConfirm: async (reason, note) => {
        const body = action === 'restrict'
          ? { reason, note, restriction_type: 'all', duration_hours: 24 }
          : action === 'suspend'
            ? { reason, note, duration_hours: 24 }
            : { reason, note };
        if (action === 'warn') await AdminApi.warnUser(token, user.id, body);
        if (action === 'restrict') await AdminApi.restrictUser(token, user.id, body);
        if (action === 'suspend') await AdminApi.suspendUser(token, user.id, body);
        if (action === 'ban') await AdminApi.banUser(token, user.id, body);
        if (action === 'unban') await AdminApi.unbanUser(token, user.id, body);
        if (action === 'force') await AdminApi.forceUsername(token, user.id, body);
        await list.reload();
        if (selectedUserId) await detail.reload();
      },
    });
  }

  return (
    <section className="page split-page">
      <div>
        <PageHeader title="Users" subtitle="Search accounts, review safety history, and apply platform restrictions." onRefresh={list.reload} />
        <div className="filter-bar">
          <input placeholder="Search username, name, email, or user id" value={search} onChange={(event) => setSearch(event.target.value)} />
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="all">All statuses</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
            <option value="banned">Banned</option>
          </select>
        </div>
        <ErrorBanner message={list.error} />
        {list.loading ? <LoadingRows /> : list.data?.results.length ? (
          <div className="admin-table">
            <div className="table-head users-head">
              <span>User</span>
              <span>Email / ID</span>
              <span>Status</span>
              <span>Reports</span>
              <span>Created</span>
              <span>Actions</span>
            </div>
            {list.data.results.map((user) => (
              <div className={selectedUserId === user.id ? 'table-row user-row selected' : 'table-row user-row'} key={user.id}>
                <button className="author-cell" onClick={() => setSelectedUserId(user.id)}>
                  <Avatar src={user.profile_image} label={user.full_name || user.username || 'U'} />
                  <span>@{user.username || user.raw_username || 'username required'}</span>
                </button>
                <button className="text-cell" onClick={() => setSelectedUserId(user.id)}>
                  <strong>{user.full_name || 'Unnamed user'}</strong>
                  <span>{user.email || user.id}</span>
                </button>
                <span className={statusClass(user.status)}>{titleCase(user.status)}</span>
                <span>{user.report_count || 0}</span>
                <time>{formatDate(user.created_at)}</time>
                <div className="row-actions">
                  <button onClick={() => setSelectedUserId(user.id)}>View</button>
                  {can(session, 'users:warn') && <button onClick={() => userAction(user, 'warn')}>Warn</button>}
                  {can(session, 'users:restrict') && <button onClick={() => userAction(user, 'restrict')}>Restrict</button>}
                  {can(session, 'users:suspend') && <button onClick={() => userAction(user, 'suspend')}>Suspend</button>}
                  {can(session, 'users:ban') && user.status === 'banned' ? <button onClick={() => userAction(user, 'unban')}>Unban</button> : null}
                  {can(session, 'users:ban') && user.status !== 'banned' ? <button className="danger-text" onClick={() => userAction(user, 'ban')}>Ban</button> : null}
                </div>
              </div>
            ))}
          </div>
        ) : <EmptyState title="No users found" body="Try a different search." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows compact /> : detail.data?.user ? (
          <UserDetailPanel data={detail.data} session={session} onAction={userAction} />
        ) : <EmptyState title="Select a user" body="Profile, recent posts, reports, and actions will appear here." />}
      </aside>
    </section>
  );
}

function UserActionPreview({ user }: { user: AdminUser }) {
  return (
    <div className="action-preview">
      <Avatar src={user.profile_image} label={user.full_name || user.username || 'U'} />
      <div>
        <strong>{user.full_name || user.username || user.id}</strong>
        <span>@{user.username || user.raw_username || 'username required'} - {titleCase(user.status)}</span>
      </div>
    </div>
  );
}

function UserDetailPanel({
  data,
  session,
  onAction,
}: {
  data: { user: AdminUser; restrictions: unknown[]; actions: AuditLog[]; recent_posts: AdminPost[] };
  session: AdminSession;
  onAction: (user: AdminUser, action: 'warn' | 'restrict' | 'suspend' | 'ban' | 'unban' | 'force') => void;
}) {
  const user = data.user;
  return (
    <div className="detail-stack">
      <div className="user-detail-header">
        <Avatar src={user.profile_image} label={user.full_name || user.username || 'U'} />
        <div>
          <h2>{user.full_name || user.username || 'Unnamed user'}</h2>
          <p>@{user.username || user.raw_username || 'username required'} - {titleCase(user.status)}</p>
        </div>
      </div>
      <div className="detail-meta">
        <span>Email</span>
        <strong>{user.email || 'Hidden for role'}</strong>
        <span>Reports</span>
        <strong>{user.report_count || 0}</strong>
        <span>Created</span>
        <strong>{formatDate(user.created_at)}</strong>
      </div>
      <div className="action-grid">
        {can(session, 'users:warn') && <button className="secondary-button" onClick={() => onAction(user, 'warn')}>Warn</button>}
        {can(session, 'users:restrict') && <button className="secondary-button" onClick={() => onAction(user, 'restrict')}>Restrict</button>}
        {can(session, 'users:suspend') && <button className="secondary-button" onClick={() => onAction(user, 'suspend')}>Suspend</button>}
        {can(session, 'users:ban') && user.status === 'banned' ? <button className="primary-button" onClick={() => onAction(user, 'unban')}>Unban</button> : null}
        {can(session, 'users:ban') && user.status !== 'banned' ? <button className="danger-button" onClick={() => onAction(user, 'ban')}>Ban</button> : null}
      </div>
      <Panel title="Recent posts" className="flat-panel">
        {data.recent_posts.length ? (
          <div className="mini-post-grid">
            {data.recent_posts.map((post) => (
              <div className="mini-post" key={post.id}>
                <MediaPreview post={post} size="card" />
                <span>{clampText(post.content || post.title, 'Untitled')}</span>
              </div>
            ))}
          </div>
        ) : <EmptyState title="No recent posts" body="This user has no recent public post data here." />}
      </Panel>
      <Panel title="Action history" className="flat-panel">
        {data.actions.length ? data.actions.map((action) => (
          <div className="note" key={action.id}>
            <strong>{titleCase(action.action_type)}</strong>
            <span>{formatDate(action.created_at)}</span>
            <p>{action.reason || action.internal_note || action.note || 'No reason recorded'}</p>
          </div>
        )) : <EmptyState title="No recent actions" body="User moderation actions will appear here." />}
      </Panel>
    </div>
  );
}

function CommentModerationPage({ token, openAction }: { token: string; openAction: (state: ActionDialogState) => void }) {
  const [status, setStatus] = useState('all');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search);
  const query = useMemo(() => {
    const params = new URLSearchParams();
    params.set('status', status);
    params.set('limit', '50');
    if (debouncedSearch) params.set('search', debouncedSearch);
    return `?${params.toString()}`;
  }, [status, debouncedSearch]);
  const list = useAdminLoad<Paginated<AdminComment>>(() => AdminApi.comments(token, query), [token, query]);

  function act(comment: AdminComment, label: string, action: 'remove' | 'restore') {
    openAction({
      title: label,
      message: `${label} comment ${compactId(comment.id)}.`,
      confirmLabel: label,
      danger: action === 'remove',
      targetPreview: (
        <div className="action-preview">
          <Avatar src={comment.author.profile_image} label={comment.author.full_name || comment.author.username || 'U'} />
          <div>
            <strong>@{comment.author.username || 'unknown'}</strong>
            <span>{comment.content}</span>
          </div>
        </div>
      ),
      onConfirm: async (reason, note) => {
        const body = { reason, note };
        if (action === 'remove') await AdminApi.removeComment(token, comment.id, body);
        if (action === 'restore') await AdminApi.restoreComment(token, comment.id, body);
        await list.reload();
      },
    });
  }

  return (
    <section className="page">
      <PageHeader title="Comment Moderation" subtitle="Review reported or unsafe comments with clear wrapping and stable table rows." onRefresh={list.reload} />
      <div className="filter-bar">
        <input placeholder="Search comment, id, or username" value={search} onChange={(event) => setSearch(event.target.value)} />
        <select value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="all">All statuses</option>
          <option value="active">Active</option>
          <option value="removed">Removed</option>
          <option value="hidden">Hidden</option>
        </select>
      </div>
      <ErrorBanner message={list.error} />
      {list.loading ? <LoadingRows /> : list.data?.results.length ? (
        <div className="admin-table">
          <div className="table-head comments-head">
            <span>Comment</span>
            <span>Author</span>
            <span>Post</span>
            <span>Status</span>
            <span>Created</span>
            <span>Actions</span>
          </div>
          {list.data.results.map((comment) => (
            <div className="table-row comment-row" key={comment.id}>
              <div className="text-cell">
                <strong>{comment.content}</strong>
                <span>{compactId(comment.id)}</span>
              </div>
              <div className="author-cell">
                <Avatar src={comment.author.profile_image} label={comment.author.full_name || comment.author.username || 'U'} />
                <span>@{comment.author.username || 'unknown'}</span>
              </div>
              <span>{compactId(comment.post_id)}</span>
              <span className={statusClass(comment.status)}>{titleCase(comment.status)}</span>
              <time>{formatDate(comment.created_at)}</time>
              <div className="row-actions">
                {comment.status === 'removed'
                  ? <button onClick={() => act(comment, 'Restore', 'restore')}>Restore</button>
                  : <button className="danger-text" onClick={() => act(comment, 'Remove', 'remove')}>Remove</button>}
              </div>
            </div>
          ))}
        </div>
      ) : <EmptyState title="No comments found" body="The moderation list is empty for this filter." />}
    </section>
  );
}

function MessagesPage({ token, openAction }: { token: string; openAction: (state: ActionDialogState) => void }) {
  const [selectedId, setSelectedId] = useState('');
  const list = useAdminLoad<Paginated<ReportSummary>>(() => AdminApi.reportedMessages(token), [token]);
  const detail = useAdminLoad<ReportedMessageDetail | null>(() => selectedId ? AdminApi.reportedMessage(token, selectedId) : Promise.resolve(null), [token, selectedId], !!selectedId);

  function removeMessage() {
    if (!selectedId || !detail.data?.report) return;
    openAction({
      title: 'Remove reported message',
      message: 'This removes the reported message and closes the report as action taken.',
      confirmLabel: 'Remove message',
      danger: true,
      targetPreview: <ReportActionPreview report={detail.data.report} />,
      onConfirm: async (reason, note) => {
        await AdminApi.reportedMessageAction(token, selectedId, { action: 'remove_message', reason, note });
        await list.reload();
        await detail.reload();
      },
    });
  }

  return (
    <section className="page split-page">
      <div>
        <PageHeader title="Reported Messages" subtitle="Limited private-message review. Every detail view is audit logged." onRefresh={list.reload} />
        <ErrorBanner message={list.error} />
        {list.loading ? <LoadingRows /> : list.data?.results.length ? (
          <div className="admin-table compact-table">
            {list.data.results.map((report) => <ReportRow key={report.id} report={report} onOpen={() => setSelectedId(report.id)} />)}
          </div>
        ) : <EmptyState title="No reported messages" body="Message safety reports will appear here." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows compact /> : detail.data ? (
          <div className="detail-stack">
            <div className="privacy-warning">{detail.data.privacy_warning}</div>
            <h2>Conversation context</h2>
            <div className="message-context">
              {detail.data.context.map((message) => (
                <div className={message.is_reported ? 'message-line reported' : 'message-line'} key={message.id}>
                  <strong>{message.sender_id}</strong>
                  <p>{message.content || titleCase(message.media_type || 'media')}</p>
                  <span>{formatDate(message.created_at)}</span>
                </div>
              ))}
            </div>
            <button className="danger-button" onClick={removeMessage}>Remove reported message</button>
          </div>
        ) : <EmptyState title="Select a reported message" body="Nearby context will load only after selection." />}
      </aside>
    </section>
  );
}

function AuditPage({ token }: { token: string }) {
  const { data, loading, error, reload } = useAdminLoad<Paginated<AuditLog>>(() => AdminApi.auditLogs(token), [token]);
  return (
    <section className="page">
      <PageHeader title="Audit Logs" subtitle="Read-only history of admin and moderator actions." onRefresh={reload} />
      <ErrorBanner message={error} />
      {loading ? <LoadingRows /> : data?.results.length ? (
        <div className="admin-table">
          <div className="table-head audit-head">
            <span>Role</span>
            <span>Action</span>
            <span>Target</span>
            <span>Reason</span>
            <span>Created</span>
          </div>
          {data.results.map((log) => (
            <div className="table-row audit-row" key={log.id}>
              <span className="badge">{titleCase(log.actor_role || 'admin')}</span>
              <div>
                <strong>{titleCase(log.action_type)}</strong>
                <span>{log.actor_full_name || log.actor_username || log.actor_admin_user_id || 'Admin'}</span>
              </div>
              <span>{titleCase(log.target_type)} - {compactId(log.target_id)}</span>
              <p>{log.reason || log.internal_note || 'No reason recorded'}</p>
              <time>{formatDate(log.created_at)}</time>
            </div>
          ))}
        </div>
      ) : <EmptyState title="No audit logs" body="Admin actions will appear here." />}
    </section>
  );
}

function SettingsPage({ session }: { session: AdminSession }) {
  return (
    <section className="page">
      <PageHeader title="Settings" subtitle="Deployment and security expectations for the private admin surface." />
      <div className="settings-grid">
        <Panel title="Access">
          <p>Current role: <strong>{titleCase(session.role)}</strong></p>
          <p>API: <code>{API_BASE}</code></p>
          <p>Backend role checks run on every admin route before data loads.</p>
        </Panel>
        <Panel title="Security checklist">
          <ul className="check-list">
            <li>Backend role checks on every admin route</li>
            <li>No public admin signup or demo credentials</li>
            <li>Destructive actions require reason and confirmation</li>
            <li>Reported message views create audit logs</li>
            <li>No database credentials or API secrets in frontend</li>
            <li>Cloudflare Pages security headers enabled</li>
          </ul>
        </Panel>
      </div>
    </section>
  );
}

function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY) || '');
  const [session, setSession] = useState<AdminSession | null>(null);
  const [booting, setBooting] = useState(true);
  const [accessError, setAccessError] = useState('');
  const [active, setActive] = useState<ViewKey>('dashboard');
  const [selectedReportId, setSelectedReportId] = useState('');
  const [selectedUserId, setSelectedUserId] = useState('');
  const [dialog, setDialog] = useState<ActionDialogState | null>(null);
  const [toast, setToast] = useState('');

  const loadSession = useCallback(async (nextToken: string) => {
    setBooting(true);
    setAccessError('');
    try {
      const next = await AdminApi.me(nextToken);
      setSession(next);
      sessionStorage.setItem(TOKEN_KEY, nextToken);
      setToken(nextToken);
    } catch (error) {
      sessionStorage.removeItem(TOKEN_KEY);
      setToken('');
      setSession(null);
      setAccessError(error instanceof Error ? error.message : 'Access denied');
    } finally {
      setBooting(false);
    }
  }, []);

  useEffect(() => {
    if (token) void loadSession(token);
    else setBooting(false);
  }, []);

  function logout() {
    sessionStorage.removeItem(TOKEN_KEY);
    setToken('');
    setSession(null);
  }

  function openAction(state: ActionDialogState) {
    setDialog({
      ...state,
      onConfirm: async (reason, note) => {
        await state.onConfirm(reason, note);
        setToast('Action saved');
        window.setTimeout(() => setToast(''), 2200);
      },
    });
  }

  function viewAuthor(userId: string) {
    if (!userId) return;
    setSelectedUserId(userId);
    setActive('users');
  }

  if (booting) return <main className="login-shell"><div className="loading-card">Checking admin access...</div></main>;
  if (!session || !token) return <LoginScreen onLogin={(nextToken) => void loadSession(nextToken)} />;

  const content = (() => {
    if (active === 'dashboard') return <DashboardPage token={token} openReport={(id) => { setSelectedReportId(id); setActive('reports'); }} />;
    if (active === 'reports') return <ReportsPage token={token} selectedId={selectedReportId} setSelectedId={setSelectedReportId} openAction={openAction} />;
    if (active === 'posts') return <PostModerationPage token={token} session={session} openAction={openAction} onViewAuthor={viewAuthor} />;
    if (active === 'comments') return <CommentModerationPage token={token} openAction={openAction} />;
    if (active === 'users') return <UsersPage token={token} session={session} selectedUserId={selectedUserId} setSelectedUserId={setSelectedUserId} openAction={openAction} />;
    if (active === 'messages') return <MessagesPage token={token} openAction={openAction} />;
    if (active === 'discover') return <PostModerationPage token={token} session={session} surface="discover" openAction={openAction} onViewAuthor={viewAuthor} />;
    if (active === 'audit') return <AuditPage token={token} />;
    return <SettingsPage session={session} />;
  })();

  return (
    <AdminLayout session={session} active={active} setActive={setActive} onLogout={logout}>
      {accessError ? <ErrorBanner message={accessError} /> : null}
      {content}
      {toast ? <div className="toast">{toast}</div> : null}
      {dialog ? <ActionDialog state={dialog} onClose={() => setDialog(null)} /> : null}
    </AdminLayout>
  );
}

export default App;
