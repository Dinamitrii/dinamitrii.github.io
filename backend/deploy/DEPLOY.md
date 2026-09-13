# Deploying the backend on your own server (real IP + domain + Let's Encrypt)

Replace `api.yourdomain.example` and `/opt/local-ai-portal` everywhere below
with your real domain and path. Run as a user with sudo, on the same machine
where llama.cpp and the SD webui already run (see the top-level README for why).

## 0. DNS

At your domain registrar, add an A record:

```
api.yourdomain.example  ->  YOUR.SERVER.PUBLIC.IP
```

Wait for it to resolve (`dig api.yourdomain.example` or `nslookup ...`) before continuing.

## 1. Firewall / router

Forward TCP 80 and 443 from your router to this machine, and open them locally:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## 2. Put the code in place

```bash
sudo mkdir -p /opt/local-ai-portal
sudo cp -r backend /opt/local-ai-portal/backend
sudo useradd -r -m -s /usr/sbin/nologin aiportal   # skip if it already exists
sudo chown -R aiportal:aiportal /opt/local-ai-portal
```

## 3. Python environment

```bash
cd /opt/local-ai-portal/backend
sudo -u aiportal python3 -m venv venv
sudo -u aiportal ./venv/bin/pip install -r requirements.txt
```

## 4. Configure .env

```bash
sudo -u aiportal cp .env.example .env
sudo -u aiportal nano .env
```

Set at minimum:

```
PUBLIC_URL=https://api.yourdomain.example
FRONTEND_URL=https://yourname.github.io/your-repo
FRONTEND_ORIGIN=https://yourname.github.io
COOKIE_SAMESITE=None
COOKIE_SECURE=1
```

Plus your real `STRIPE_*` keys when you're ready to take payments (leave
blank for now to keep billing disabled).

## 5. nginx (HTTP first, no TLS yet - Certbot adds that next)

```bash
sudo apt install -y nginx
sudo cp deploy/nginx-local-ai-portal.conf /etc/nginx/sites-available/local-ai-portal
sudo nano /etc/nginx/sites-available/local-ai-portal   # set server_name to your real domain
sudo ln -s /etc/nginx/sites-available/local-ai-portal /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## 6. Run the backend as a service

```bash
sudo cp deploy/local-ai-portal.service /etc/systemd/system/
sudo nano /etc/systemd/system/local-ai-portal.service   # confirm paths/user match steps above
sudo systemctl daemon-reload
sudo systemctl enable --now local-ai-portal
sudo systemctl status local-ai-portal
```

At this point `http://api.yourdomain.example/api/health` should return `{"ok":true}`.
If not, check `journalctl -u local-ai-portal -f` and `sudo nginx -t`.

## 7. TLS certificate (Let's Encrypt via Certbot)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.yourdomain.example
```

Certbot edits the nginx config to add the certificate and a 80->443 redirect,
and installs a systemd timer that renews the certificate automatically. Verify
the timer exists:

```bash
systemctl list-timers | grep certbot
```

Test renewal without actually renewing:

```bash
sudo certbot renew --dry-run
```

## 8. Point the frontend at it

In `frontend/config.js`:

```js
window.API_BASE = 'https://api.yourdomain.example';
```

Push that to GitHub Pages. Open your GitHub Pages site, register an account,
and confirm chat/image requests succeed - that confirms CORS, cookies, and
the reverse proxy are all wired correctly end to end.

## 9. Stripe webhook (only if you're enabling payments)

In the Stripe dashboard, point the webhook endpoint at:

```
https://api.yourdomain.example/webhooks/payment
```

Copy the webhook signing secret into `STRIPE_WEBHOOK_SECRET` in `.env`, then:

```bash
sudo systemctl restart local-ai-portal
```

## Updating the app later

```bash
cd /opt/local-ai-portal/backend
sudo systemctl stop local-ai-portal
sudo -u aiportal git pull          # or copy in the new app.py
sudo -u aiportal ./venv/bin/pip install -r requirements.txt
sudo systemctl start local-ai-portal
```
