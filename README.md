# Frontend (static, for GitHub Pages)

Plain HTML/CSS/JS, no build step, no framework.

## Before deploying

Edit `config.js`:

```js
window.API_BASE = 'https://your-backend-url';  // no trailing slash, must be https in production
```

This must point at wherever `backend/` is running (see the top-level README
for how to expose it, e.g. via a Cloudflare Tunnel).

## Deploy

Push this folder's contents to a GitHub repo and enable GitHub Pages on it
(Settings → Pages → choose the branch/folder). No build step is needed.

## Files

- `index.html` — chat + image generation (the main app)
- `login.html`, `register.html` — auth
- `upgrade.html` — plan/billing (Stripe checkout, customer portal)
- `config.js` — the one thing you edit per-deployment
- `app.js` — shared API/auth helpers used by every page
- `style.css` — shared styling (ported from the original app)
