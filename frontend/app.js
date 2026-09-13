// Shared helpers used by every page. Requires config.js to be loaded first.
const API = window.API_BASE;
const el = id => document.getElementById(id);
let csrfToken = null;

async function ensureCsrf() {
  if (csrfToken) return csrfToken;
  const r = await fetch(API + '/api/csrf', { credentials: 'include' });
  const d = await r.json();
  csrfToken = d.csrf;
  return csrfToken;
}

// Mirrors the original inline api() helper: GET when no body, POST+JSON otherwise.
async function api(path, data) {
  await ensureCsrf();
  const opts = { credentials: 'include' };
  if (data !== undefined) {
    opts.method = 'POST';
    opts.headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };
    opts.body = JSON.stringify(data);
  } else {
    opts.headers = { 'X-CSRF-Token': csrfToken };
  }
  const r = await fetch(API + path, opts);
  const d = await r.json().catch(() => ({}));
  if (!r.ok) {
    if (r.status === 401) { location.href = 'login.html'; }
    throw new Error((d.error || 'Грешка') + (r.status === 402 ? ' Вижте Upgrade горе.' : ''));
  }
  return d;
}

// Like api(), but for /api/login and /api/register: a 401 there is "wrong
// email/password", not "you're logged out" - it must NOT redirect to login.html.
async function authRequest(path, data) {
  await ensureCsrf();
  const r = await fetch(API + path, {
    method: 'POST', credentials: 'include',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
    body: JSON.stringify(data)
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.error || 'Грешка');
  return d;
}

function node(tag, text, cls) {
  const n = document.createElement(tag);
  if (text !== undefined) n.textContent = text;
  if (cls) n.className = cls;
  return n;
}

async function run(button, fn) {
  button.disabled = true;
  const status = el('status');
  if (status) status.textContent = 'Обработване…';
  try {
    await fn();
    if (status) status.textContent = 'Готово.';
  } catch (e) {
    if (status) status.textContent = e.message;
  } finally {
    button.disabled = false;
  }
}

// Populates the shared <header class="account-bar"> on pages that have one,
// and wires up the logout button. Redirects to login if not authenticated.
async function initAccountBar({ requireAuth = true } = {}) {
  const bar = el('account-info');
  try {
    const me = await (async () => {
      await ensureCsrf();
      const r = await fetch(API + '/api/me', { credentials: 'include' });
      if (!r.ok) throw new Error('unauth');
      return r.json();
    })();
    if (bar) bar.textContent = me.email + ' · ' + me.plan;
    const logoutBtn = el('logout-btn');
    if (logoutBtn) logoutBtn.onclick = () => run(logoutBtn, async () => {
      await api('/api/logout', {});
      location.href = 'login.html';
    });
    return me;
  } catch (e) {
    if (requireAuth) { location.href = 'login.html'; }
    return null;
  }
}
