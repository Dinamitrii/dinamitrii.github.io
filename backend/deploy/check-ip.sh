#!/usr/bin/env bash
# Read-only diagnostics, apart from one public, non-secret HTTP probe file.
set -eu
if [[ $EUID -ne 0 ]]; then
    echo "Run: sudo bash $0" >&2
    exit 1
fi
probe_dir=/var/www/flask-ai-acme/.well-known/acme-challenge
install -d -m 755 "$probe_dir"
printf 'flask-ai-port80-ok\n' > "$probe_dir/portal-check"
chmod 644 "$probe_dir/portal-check"
printf '\n=== Latest certificate errors ===\n'
if [[ -f /var/log/letsencrypt/letsencrypt.log ]]; then
    tail -n 250 /var/log/letsencrypt/letsencrypt.log | grep -E 'Detail:|Type:|Timeout during connect|Invalid response|urn:ietf:params:acme:error|too many|rateLimited' | tail -n 12 || true
fi
printf '\n=== Firewall ===\n'
if command -v ufw >/dev/null; then ufw status verbose; fi
printf '\n=== Local HTTP challenge file ===\n'
curl --noproxy '*' --max-time 5 --silent --show-error -D - -H 'Host: 95.111.68.174' http://192.168.100.11/.well-known/acme-challenge/portal-check || true
printf '\n=== Recent incoming nginx requests ===\n'
tail -n 15 /var/log/nginx/access.log
printf '\nFrom a phone with Wi-Fi OFF, open:\nhttp://95.111.68.174/.well-known/acme-challenge/portal-check\nExpected text: flask-ai-port80-ok\n'
