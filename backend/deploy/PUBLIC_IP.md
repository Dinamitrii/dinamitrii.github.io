# Public HTTPS API at 95.111.68.174

Frontend: https://dinamitrii.github.io/flask-ai-split-new/

API: https://95.111.68.174 (TCP 443)

The router owns the public IP. The application computer is 192.168.100.11.
Reserve that local address in the router's DHCP settings, then forward:

| Protocol | External port | Internal address | Internal port |
| --- | --- | --- | --- |
| TCP | 80 | 192.168.100.11 | 80 |
| TCP | 443 | 192.168.100.11 | 443 |

Port 80 must remain reachable for automatic certificate renewal. Ports 5005,
5006, 8080 and 8081 do not need public forwarding for this deployment.

Run on this computer, in the existing checkout:

```bash
sudo bash /home/dinamitrii/PycharmProjects/flask-ai-split/backend/deploy/setup-ip.sh
```

The script installs nginx and a separate Certbot environment, backs up existing
deployment files under `/var/backups/flask-ai-split/`, and runs the backend as
the checkout owner on 127.0.0.1:5006. It uses the existing project environment
and data settings from `backend/.env`. It overrides public URL, frontend origin,
cookie flags and model alias in the new service. PyCharm's process on port 5005
and the AI services are not restarted.

It requests a trusted Let's Encrypt IP certificate with the shortlived profile,
accepting the CA subscriber agreement and registering without a contact email.
It installs a renewal timer that checks twice a day and reloads nginx after
renewal. A failed certificate request leaves the HTTP challenge server running:
correct router forwarding and rerun the same command. An HTTP response from
the router itself does not prove that forwarding works.

The command requires the computer's sudo password, entered locally. It can
also need outbound access to Ubuntu package repositories, PyPI and Let's Encrypt.

After installation, check from outside the home network (e.g. mobile data):

```text
https://95.111.68.174/api/health
```

Expected: `{"ok":true}` with a trusted certificate. A local request through the
public IP may require router NAT loopback. The script separately verifies local
HTTPS with the public IP certificate and runs a renewal dry run.

Once HTTPS is verified, publish the updated root `config.js` to GitHub Pages.
It must use `https://95.111.68.174`, without `:5005`. Test registration, login,
chat and image retrieval in the browser. Browsers that block third-party cookies
may require an exception for this split-site setup; SameSite=None and Secure are
already set. Stripe keys remain as configured; payments need their own live
verification and the webhook endpoint must use the new API URL.

Diagnostics:

```bash
sudo systemctl status flask-ai-ip nginx flask-ai-certbot.timer --no-pager
sudo journalctl -u flask-ai-ip -n 50 --no-pager
sudo /opt/flask-ai-certbot/bin/certbot certificates
```

To take down only this deployment, stop `flask-ai-ip` and `flask-ai-certbot.timer`,
remove `/etc/nginx/sites-enabled/flask-ai-ip`, run `sudo nginx -t`, and reload nginx.
Keep the database and certificate files. Existing deployment files, if any, are
in the timestamped backup directory printed by the script. Restore the previous
`config.js` deployment if reverting a published frontend.

IP certificate documentation:
https://letsencrypt.org/2026/03/11/shorter-certs-certbot/
