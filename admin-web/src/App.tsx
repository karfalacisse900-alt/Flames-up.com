import { FormEvent, ReactNode, useCallback, useEffect, useMemo, useState } from 'react';
import { AdminApi, ApiError, API_BASE, login } from './api';
import type {
  AdminComment,
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

type ViewKey = 'dashboard' | 'reports' | 'posts' | 'comments' | 'users' | 'messages' | 'audit' | 'settings';

type ActionDialogState = {
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  defaultReason?: string;
  onConfirm: (reason: string, note: string) => Promise<void>;
};

const TOKEN_KEY = 'captro_admin_token';

const navItems: Array<{ key: ViewKey; label: string }> = [
  { key: 'dashboard', label: 'Dashboard' },
  { key: 'reports', label: 'Reports' },
  { key: 'posts', label: 'Posts' },
  { key: 'comments', label: 'Comments' },
  { key: 'users', label: 'Users' },
  { key: 'messages', label: 'Messages' },
  { key: 'audit', label: 'Audit Logs' },
  { key: 'settings', label: 'Settings' },
];

function formatDate(value?: string | null) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

function titleCase(value: string) {
  return value.replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function statusClass(value?: string) {
  const clean = String(value || '').toLowerCase();
  if (['high', 'banned', 'removed', 'declined', 'failed'].includes(clean)) return 'badge danger';
  if (['medium', 'suspended', 'under_review', 'escalated', 'hidden'].includes(clean)) return 'badge warning';
  if (['active', 'action_taken', 'closed', 'restored'].includes(clean)) return 'badge success';
  return 'badge';
}

function can(session: AdminSession, permission: string) {
  return session.permissions.includes('*') || session.permissions.includes(permission);
}

function useAdminLoad<T>(loader: () => Promise<T>, deps: unknown[]) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const reload = useCallback(async () => {
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

function LoadingRows() {
  return (
    <div className="skeleton-list" aria-label="Loading">
      {Array.from({ length: 5 }).map((_, index) => <div className="skeleton-row" key={index} />)}
    </div>
  );
}

function ErrorBanner({ message }: { message?: string }) {
  if (!message) return null;
  return <div className="error-banner">{message}</div>;
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
        <button className="primary-button" disabled={submitting}>{submitting ? 'Checking access…' : 'Sign in'}</button>
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
        <h2 id="action-title">{state.title}</h2>
        <p>{state.message}</p>
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
            {submitting ? 'Saving…' : state.confirmLabel}
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
            <strong>Captro</strong>
            <span>Moderation</span>
          </div>
        </div>
        <nav>
          {navItems.map((item) => (
            <button key={item.key} className={active === item.key ? 'active' : ''} onClick={() => setActive(item.key)}>
              {item.label}
            </button>
          ))}
        </nav>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div>
            <span className="env-pill">Production</span>
            <strong>{session.user.full_name || session.user.username || 'Admin'}</strong>
            <span className="muted">{titleCase(session.role)}</span>
          </div>
          <button className="ghost-button" onClick={onLogout}>Logout</button>
        </header>
        {children}
      </div>
    </div>
  );
}

function DashboardPage({ token, openReport }: { token: string; openReport: (id: string) => void }) {
  const { data, loading, error, reload } = useAdminLoad<DashboardResponse>(() => AdminApi.dashboard(token), [token]);
  const cards = data?.cards || {};
  return (
    <section className="page">
      <PageHeader title="Dashboard" subtitle="Moderation health, safety queues, and urgent work." onRefresh={reload} />
      <ErrorBanner message={error} />
      {loading ? <LoadingRows /> : (
        <>
          <div className="metric-grid">
            {Object.entries(cards).map(([key, value]) => (
              <article className="metric-card" key={key}>
                <span>{titleCase(key)}</span>
                <strong>{value}</strong>
              </article>
            ))}
          </div>
          <Panel title="Priority queue">
            {data?.queues.new_reports.length ? data.queues.new_reports.map((report) => (
              <ReportRow key={report.id} report={report} onOpen={() => openReport(report.id)} />
            )) : <EmptyState title="No open reports" body="The queue is clear right now." />}
          </Panel>
        </>
      )}
    </section>
  );
}

function PageHeader({ title, subtitle, onRefresh }: { title: string; subtitle: string; onRefresh?: () => void }) {
  return (
    <div className="page-header">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {onRefresh ? <button className="secondary-button" onClick={onRefresh}>Refresh</button> : null}
    </div>
  );
}

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="panel">
      <h2>{title}</h2>
      {children}
    </section>
  );
}

function ReportRow({ report, onOpen }: { report: ReportSummary; onOpen: () => void }) {
  return (
    <button className="table-row report-row" onClick={onOpen}>
      <span className={statusClass(report.priority)}>{titleCase(report.priority)}</span>
      <div>
        <strong>{titleCase(report.reason)}</strong>
        <span>{titleCase(report.target_type)} · {report.target_user.full_name || report.target_user.username || report.reported_id}</span>
      </div>
      <p>{report.preview || report.details || 'No preview available'}</p>
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
  const query = useMemo(() => `?status=${encodeURIComponent(status)}&reason=${encodeURIComponent(reason)}`, [status, reason]);
  const { data, loading, error, reload } = useAdminLoad<Paginated<ReportSummary>>(() => AdminApi.reports(token, query), [token, query]);
  const detail = useAdminLoad<{ report: ReportDetail } | null>(
    () => selectedId ? AdminApi.report(token, selectedId) : Promise.resolve(null),
    [token, selectedId],
  );
  const [note, setNote] = useState('');

  async function changeReport(action: string, title: string, danger = false) {
    if (!selectedId) return;
    openAction({
      title,
      message: `This updates report ${selectedId}.`,
      confirmLabel: title,
      danger,
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
    <section className="page split-page">
      <div>
        <PageHeader title="Reports" subtitle="Review reported posts, comments, profiles, and messages." onRefresh={reload} />
        <div className="filters">
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="open">Open</option>
            <option value="all">All</option>
            <option value="under_review">In Review</option>
            <option value="escalated">Escalated</option>
            <option value="action_taken">Action Taken</option>
            <option value="dismissed">Dismissed</option>
          </select>
          <select value={reason} onChange={(event) => setReason(event.target.value)}>
            <option value="all">All reasons</option>
            <option value="harassment">Harassment</option>
            <option value="hate">Hate</option>
            <option value="threats">Threats</option>
            <option value="doxxing">Doxxing</option>
            <option value="spam">Spam</option>
            <option value="scam">Scam</option>
            <option value="impersonation">Impersonation</option>
            <option value="copyright_issue">Copyright</option>
            <option value="other">Other</option>
          </select>
        </div>
        <ErrorBanner message={error} />
        {loading ? <LoadingRows /> : data?.results.length ? data.results.map((report) => (
          <ReportRow key={report.id} report={report} onOpen={() => setSelectedId(report.id)} />
        )) : <EmptyState title="No reports found" body="Try another filter or refresh the queue." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows /> : detail.data?.report ? (
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
        ) : <EmptyState title="Select a report" body="Report details and actions will appear here." />}
      </aside>
    </section>
  );
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
  return (
    <div className="detail-stack">
      <div className="detail-title">
        <span className={statusClass(report.priority)}>{titleCase(report.priority)}</span>
        <h2>{titleCase(report.reason)}</h2>
        <p>{titleCase(report.target_type)} · {formatDate(report.created_at)}</p>
      </div>
      <div className="preview-box">
        <strong>Target preview</strong>
        <p>{report.preview || report.details || 'No text preview available.'}</p>
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
      <Panel title="History">
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

function UsersPage({ token, session, openAction }: { token: string; session: AdminSession; openAction: (state: ActionDialogState) => void }) {
  const [search, setSearch] = useState('');
  const query = useMemo(() => search ? `?search=${encodeURIComponent(search)}` : '', [search]);
  const { data, loading, error, reload } = useAdminLoad<Paginated<AdminUser>>(() => AdminApi.users(token, query), [token, query]);

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
        await reload();
      },
    });
  }

  return (
    <section className="page">
      <PageHeader title="Users" subtitle="Search accounts, review safety history, and apply platform restrictions." onRefresh={reload} />
      <input className="search-input" placeholder="Search username, name, email, or user id" value={search} onChange={(event) => setSearch(event.target.value)} />
      <ErrorBanner message={error} />
      {loading ? <LoadingRows /> : data?.results.length ? (
        <div className="table">
          {data.results.map((user) => (
            <div className="table-row user-row" key={user.id}>
              <Avatar src={user.profile_image} label={user.full_name || user.username || 'U'} />
              <div>
                <strong>{user.full_name || user.username || 'Unnamed user'}</strong>
                <span>@{user.username || user.raw_username || 'username required'} · {user.email || user.id}</span>
              </div>
              <span className={statusClass(user.status)}>{titleCase(user.status)}</span>
              <span>{user.report_count || 0} reports</span>
              <div className="row-actions">
                {can(session, 'users:warn') && <button onClick={() => userAction(user, 'warn')}>Warn</button>}
                {can(session, 'users:restrict') && <button onClick={() => userAction(user, 'restrict')}>Restrict</button>}
                {can(session, 'users:suspend') && <button onClick={() => userAction(user, 'suspend')}>Suspend</button>}
                {can(session, 'users:ban') && user.status === 'banned' ? <button onClick={() => userAction(user, 'unban')}>Unban</button> : null}
                {can(session, 'users:ban') && user.status !== 'banned' ? <button className="danger-text" onClick={() => userAction(user, 'ban')}>Ban</button> : null}
                {can(session, 'users:restrict') && <button onClick={() => userAction(user, 'force')}>Username</button>}
              </div>
            </div>
          ))}
        </div>
      ) : <EmptyState title="No users found" body="Try a different search." />}
    </section>
  );
}

function ContentPage({
  token,
  kind,
  openAction,
}: {
  token: string;
  kind: 'posts' | 'comments';
  openAction: (state: ActionDialogState) => void;
}) {
  const [status, setStatus] = useState('all');
  const [search, setSearch] = useState('');
  const query = useMemo(() => {
    const params = new URLSearchParams();
    params.set('status', status);
    if (search) params.set('search', search);
    return `?${params.toString()}`;
  }, [status, search]);
  const postLoad = useAdminLoad<Paginated<AdminPost>>(() => AdminApi.posts(token, query), [token, query, kind]);
  const commentLoad = useAdminLoad<Paginated<AdminComment>>(() => AdminApi.comments(token, query), [token, query, kind]);
  const activeLoad = kind === 'posts' ? postLoad : commentLoad;

  function act(id: string, label: string, action: 'remove' | 'restore' | 'discover') {
    openAction({
      title: label,
      message: `${label} ${kind === 'posts' ? 'post' : 'comment'} ${id}.`,
      confirmLabel: label,
      danger: action !== 'restore',
      onConfirm: async (reason, note) => {
        const body = { reason, note };
        if (kind === 'posts' && action === 'remove') await AdminApi.removePost(token, id, body);
        if (kind === 'posts' && action === 'restore') await AdminApi.restorePost(token, id, body);
        if (kind === 'posts' && action === 'discover') await AdminApi.removeFromDiscover(token, id, body);
        if (kind === 'comments' && action === 'remove') await AdminApi.removeComment(token, id, body);
        if (kind === 'comments' && action === 'restore') await AdminApi.restoreComment(token, id, body);
        await activeLoad.reload();
      },
    });
  }

  return (
    <section className="page">
      <PageHeader title={kind === 'posts' ? 'Post Moderation' : 'Comment Moderation'} subtitle="Remove unsafe content, restore mistakes, and keep previews lightweight." onRefresh={activeLoad.reload} />
      <div className="filters">
        <select value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="all">All statuses</option>
          <option value="active">Active</option>
          <option value="removed">Removed</option>
          <option value="hidden">Hidden</option>
        </select>
        <input placeholder="Search content or id" value={search} onChange={(event) => setSearch(event.target.value)} />
      </div>
      <ErrorBanner message={activeLoad.error} />
      {activeLoad.loading ? <LoadingRows /> : kind === 'posts'
        ? <PostList posts={(postLoad.data?.results || []) as AdminPost[]} act={act} />
        : <CommentList comments={(commentLoad.data?.results || []) as AdminComment[]} act={act} />}
    </section>
  );
}

function PostList({ posts, act }: { posts: AdminPost[]; act: (id: string, label: string, action: 'remove' | 'restore' | 'discover') => void }) {
  if (!posts.length) return <EmptyState title="No posts found" body="The moderation list is empty for this filter." />;
  return (
    <div className="card-grid">
      {posts.map((post) => (
        <article className="content-card" key={post.id}>
          {post.thumbnail_urls?.[0] || post.image ? <img src={post.thumbnail_urls?.[0] || post.image} alt="" /> : <div className="media-placeholder" />}
          <div>
            <span className={statusClass(post.status)}>{titleCase(post.status)}</span>
            <h3>{post.title || post.content || 'Untitled post'}</h3>
            <p>@{post.author.username || 'unknown'} · {formatDate(post.created_at)}</p>
          </div>
          <div className="row-actions">
            {post.status === 'removed'
              ? <button onClick={() => act(post.id, 'Restore', 'restore')}>Restore</button>
              : <button className="danger-text" onClick={() => act(post.id, 'Remove', 'remove')}>Remove</button>}
            <button onClick={() => act(post.id, 'Remove from Discover', 'discover')}>Discover</button>
          </div>
        </article>
      ))}
    </div>
  );
}

function CommentList({ comments, act }: { comments: AdminComment[]; act: (id: string, label: string, action: 'remove' | 'restore') => void }) {
  if (!comments.length) return <EmptyState title="No comments found" body="The moderation list is empty for this filter." />;
  return (
    <div className="table">
      {comments.map((comment) => (
        <div className="table-row" key={comment.id}>
          <div>
            <strong>{comment.content}</strong>
            <span>@{comment.author.username || 'unknown'} · post {comment.post_id}</span>
          </div>
          <span className={statusClass(comment.status)}>{titleCase(comment.status)}</span>
          <time>{formatDate(comment.created_at)}</time>
          <div className="row-actions">
            {comment.status === 'removed'
              ? <button onClick={() => act(comment.id, 'Restore', 'restore')}>Restore</button>
              : <button className="danger-text" onClick={() => act(comment.id, 'Remove', 'remove')}>Remove</button>}
          </div>
        </div>
      ))}
    </div>
  );
}

function MessagesPage({ token, openAction }: { token: string; openAction: (state: ActionDialogState) => void }) {
  const [selectedId, setSelectedId] = useState('');
  const list = useAdminLoad<Paginated<ReportSummary>>(() => AdminApi.reportedMessages(token), [token]);
  const detail = useAdminLoad<ReportedMessageDetail | null>(() => selectedId ? AdminApi.reportedMessage(token, selectedId) : Promise.resolve(null), [token, selectedId]);

  function removeMessage() {
    if (!selectedId) return;
    openAction({
      title: 'Remove reported message',
      message: 'This removes the reported message and closes the report as action taken.',
      confirmLabel: 'Remove message',
      danger: true,
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
        {list.loading ? <LoadingRows /> : list.data?.results.length ? list.data.results.map((report) => (
          <ReportRow key={report.id} report={report} onOpen={() => setSelectedId(report.id)} />
        )) : <EmptyState title="No reported messages" body="Message safety reports will appear here." />}
      </div>
      <aside className="detail-panel">
        {detail.loading ? <LoadingRows /> : detail.data ? (
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
        <div className="table">
          {data.results.map((log) => (
            <div className="table-row audit-row" key={log.id}>
              <span className="badge">{titleCase(log.actor_role || 'admin')}</span>
              <div>
                <strong>{titleCase(log.action_type)}</strong>
                <span>{log.target_type} · {log.target_id}</span>
              </div>
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
          <p>Deploy behind Cloudflare Access for an extra identity gate before this app loads.</p>
        </Panel>
        <Panel title="Security checklist">
          <ul className="check-list">
            <li>Backend role checks on every admin route</li>
            <li>No public admin signup</li>
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

function Avatar({ src, label }: { src?: string; label: string }) {
  if (src) return <img className="avatar" src={src} alt="" />;
  return <span className="avatar fallback">{label.slice(0, 1).toUpperCase()}</span>;
}

function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY) || '');
  const [session, setSession] = useState<AdminSession | null>(null);
  const [booting, setBooting] = useState(true);
  const [accessError, setAccessError] = useState('');
  const [active, setActive] = useState<ViewKey>('dashboard');
  const [selectedReportId, setSelectedReportId] = useState('');
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

  if (booting) return <main className="login-shell"><div className="loading-card">Checking admin access…</div></main>;
  if (!session || !token) return <LoginScreen onLogin={(nextToken) => void loadSession(nextToken)} />;

  const content = (() => {
    if (active === 'dashboard') return <DashboardPage token={token} openReport={(id) => { setSelectedReportId(id); setActive('reports'); }} />;
    if (active === 'reports') return <ReportsPage token={token} selectedId={selectedReportId} setSelectedId={setSelectedReportId} openAction={openAction} />;
    if (active === 'posts') return <ContentPage token={token} kind="posts" openAction={openAction} />;
    if (active === 'comments') return <ContentPage token={token} kind="comments" openAction={openAction} />;
    if (active === 'users') return <UsersPage token={token} session={session} openAction={openAction} />;
    if (active === 'messages') return <MessagesPage token={token} openAction={openAction} />;
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
