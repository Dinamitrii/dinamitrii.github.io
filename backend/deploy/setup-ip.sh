#!/usr/bin/env bash
# Run with sudo from this checkout. The router must forward TCP 80 and 443
# to 192.168.100.11. No AI service or router settings are changed here.
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run: sudo bash $0" >&2
  exit 1
fi
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
portal_user=$(stat -c '%U' "$project_dir")
portal_group=$(stat -c '%G' "$project_dir")
public_ip=95.111.68.174
backup_dir="/var/backups/flask-ai-split/$(date +%Y%m%d-%H%M%S)"
certbot_bin=/opt/flask-ai-certbot/bin/certbot
site_file=/etc/nginx/sites-available/flask-ai-ip
cert_dir="/etc/letsencrypt/live/$public_ip"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
for existing in "$site_file" /etc/systemd/system/flask-ai-ip.service /etc/systemd/system/flask-ai-certbot.service /etc/systemd/system/flask-ai-certbot.timer; do
  if [[ -f $existing ]]; then cp -a "$existing" "$backup_dir/"; fi
done
[[ -x "$project_dir/.venv/bin/gunicorn" ]] || { echo 'Project gunicorn is missing.' >&2; exit 1; }
[[ -f "$project_dir/backend/.env" ]] || { echo 'backend/.env is missing.' >&2; exit 1; }

apt-get update
apt-get install -y nginx python3-venv
if [[ ! -x $certbot_bin ]]; then
  python3 -m venv /opt/flask-ai-certbot
fi
/opt/flask-ai-certbot/bin/python -m pip install 'certbot>=5.4,<6'
"$certbot_bin" --version
install -d -m 755 /var/www/flask-ai-acme/.well-known/acme-challenge

cat > /etc/systemd/system/flask-ai-ip.service <<EOF
[Unit]
Description=Flask AI public IP backend
After=network.target

[Service]
User=$portal_user
Group=$portal_group
WorkingDirectory=$project_dir/backend
Environment=PUBLIC_URL=https://$public_ip
Environment=FRONTEND_URL=https://dinamitrii.github.io/flask-ai-split-new
Environment=FRONTEND_ORIGIN=https://dinamitrii.github.io
Environment=COOKIE_SECURE=1
Environment=COOKIE_SAMESITE=None
Environment=LLAMA_MODEL=local
ExecStart=$project_dir/.venv/bin/gunicorn --bind 127.0.0.1:5006 --workers 1 --threads 8 --timeout 1900 --access-logfile - --error-logfile - app:app
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

# HTTP serves only ACME challenges and redirects; credentials never use HTTP.
write_http() {
cat <<EOF
server {
    listen 80;
    server_name $public_ip;
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/flask-ai-acme;
        default_type text/plain;
        try_files \$uri =404;
    }
    location / { return 301 https://$public_ip\$request_uri; }
}
EOF
}
write_https() {
cat <<EOF
server {
    listen 443 ssl;
    server_name $public_ip;
    ssl_certificate $cert_dir/fullchain.pem;
    ssl_certificate_key $cert_dir/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 16m;
    location / {
        proxy_pass http://127.0.0.1:5006;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 1900s;
        proxy_send_timeout 1900s;
    }
}
EOF
}
write_http > "$site_file"
# Preserve working HTTPS when this script is rerun.
if [[ -f $cert_dir/fullchain.pem ]]; then write_https >> "$site_file"; fi
ln -sfn "$site_file" /etc/nginx/sites-enabled/flask-ai-ip
nginx -t
systemctl daemon-reload
systemctl enable --now flask-ai-ip.service nginx.service
systemctl restart flask-ai-ip.service
systemctl reload nginx.service
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    ufw allow 80/tcp
    ufw allow 443/tcp
fi
for attempt in {1..10}; do
    if curl --noproxy '*' --fail --silent http://127.0.0.1:5006/api/health; then break; fi
    sleep 1
done
curl --noproxy '*' --fail --silent http://127.0.0.1:5006/api/health
printf '\nBackend is ready. Router: TCP 80 -> 192.168.100.11:80; TCP 443 -> 192.168.100.11:443.\n'

# IP certificates require the shortlived profile and reachable public port 80.
# Failure leaves HTTP challenge serving ready; fix router forwarding and rerun.
"$certbot_bin" certonly --non-interactive --agree-tos --register-unsafely-without-email \
    --preferred-profile shortlived --webroot -w /var/www/flask-ai-acme \
    --ip-address "$public_ip" --cert-name "$public_ip" --keep-until-expiring
write_http > "$site_file"
write_https >> "$site_file"
nginx -t
systemctl reload nginx.service

install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/flask-ai-nginx <<'EOF'
#!/bin/sh
set -e
/usr/sbin/nginx -t
/usr/bin/systemctl reload nginx.service
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/flask-ai-nginx
cat > /etc/systemd/system/flask-ai-certbot.service <<EOF
[Unit]
Description=Renew Flask AI IP certificate
[Service]
Type=oneshot
ExecStart=$certbot_bin renew --quiet --cert-name $public_ip
EOF
cat > /etc/systemd/system/flask-ai-certbot.timer <<'EOF'
[Unit]
Description=Check Flask AI certificate renewal twice daily
[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now flask-ai-certbot.timer
"$certbot_bin" renew --dry-run --cert-name "$public_ip"
curl --noproxy '*' --fail --resolve "$public_ip:443:127.0.0.1" "https://$public_ip/api/health"
systemctl --no-pager --full status flask-ai-ip.service flask-ai-certbot.timer
printf '\nReady: https://%s/api/health\nBackups: %s\n' "$public_ip" "$backup_dir"
