# Local AI Portal — frontend/backend split

This is the original `flask-ai-portal` app split in two:

- **`frontend/`** — a plain static site (HTML/CSS/JS, no build step). Deploy this
  to GitHub Pages.
- **`backend/`** — the original Flask app, now a pure JSON API (no server-rendered
  HTML). Deploy this wherever Python can run.

## Read this first: where the AI actually runs

The backend talks to `LLAMA_URL` and `SD_URL`, which default to
`http://127.0.0.1:8080` and `http://127.0.0.1:8081` — i.e. a llama.cpp server and
a Stable Diffusion webui running **on the same machine as the Flask backend**,
typically using a local GPU. GitHub Pages can only ever host the frontend; it
cannot run Python, llama.cpp, or Stable Diffusion.

So "deploying the backend" here means: run `app.py` + llama.cpp + the SD webui
together on your own PC/server (the one with the GPU), and make that reachable
from the internet — for example with a **Cloudflare Tunnel** pointed at the
Flask port. Cloud PaaS options like Render/Railway won't have your local models
unless you also move the models there (a much bigger, costlier change).

## Deploying the frontend (GitHub Pages)

1. Edit `frontend/config.js` and set `window.API_BASE` to your backend's public
   URL (e.g. your Cloudflare Tunnel URL or VPS domain), **with `https://`**.
2. Push the contents of `frontend/` to a GitHub repo (root, or a `/docs` folder,
   or a `gh-pages` branch — your choice).
3. In the repo's Settings → Pages, point GitHub Pages at that location.
4. Your site is now live at `https://yourname.github.io/your-repo/`.

## Deploying the backend

1. Copy `backend/.env.example` to `backend/.env` and fill in real values.
   Critically:
   - `FRONTEND_URL` / `FRONTEND_ORIGIN` — your GitHub Pages URL (no trailing
     slash), e.g. `https://yourname.github.io`. If your site lives under a
     repo path like `/your-repo/`, `FRONTEND_ORIGIN` still just needs the
     origin (scheme+host), but `FRONTEND_URL` used for Stripe redirects should
     include the path, e.g. `https://yourname.github.io/your-repo`.
   - `COOKIE_SAMESITE=None` and `COOKIE_SECURE=1` — required for the session
     cookie to work across two different origins. This means the backend
     **must be served over HTTPS** (a Cloudflare Tunnel gives you this for
     free).
   - `LLAMA_URL` / `SD_URL` — normally left as localhost, since those servers
     run next to the backend.
2. Run it the same way as before: `pip install -r requirements.txt`, then
   `gunicorn -w 2 -b 127.0.0.1:5005 app:app` (or `python app.py` for a quick
   local check).
3. Expose it publicly, e.g.:
   ```
   cloudflared tunnel --url http://127.0.0.1:5005
   ```
   Use the HTTPS URL cloudflared prints as your backend's public address —
   that's what goes into `frontend/config.js` as `API_BASE`.

## What changed from the original single-app version

- All server-rendered HTML (`SHELL`/`AUTH`/`UPGRADE`/`HOME`, `render_template_string`)
  was removed from `app.py`. Every route now returns JSON (or, for images,
  raw PNG bytes).
- `/register` and `/login` (GET+POST, HTML) became `POST /api/register` and
  `POST /api/login` (JSON in, JSON out).
- `/logout` became `POST /api/logout`.
- `GET /upgrade` (HTML) became `GET /api/upgrade` (JSON), plus a new
  `GET /api/me` used by the frontend to render the account bar.
- `/api/checkout` and `/api/billing/portal` used to 303-redirect straight to
  Stripe; they now return `{"url": "..."}` and the frontend does
  `location.href = url`. Stripe's own success/cancel/return URLs now point at
  the **frontend** (`FRONTEND_URL`), not the backend.
- Added `flask-cors` with `supports_credentials=True`, restricted to
  `FRONTEND_ORIGIN`.
- Session cookie changed from `SameSite=Lax` to `SameSite=None; Secure` (see
  above) — this only works over HTTPS.
- Added `GET /api/csrf` so the static frontend can fetch a CSRF token before
  its first POST (previously the token was embedded server-side in the HTML).

Everything else — the SQLite schema, quota logic, Stripe verification logic,
llama.cpp/SD calls, CLI commands — is unchanged.
