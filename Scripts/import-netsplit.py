#!/usr/bin/env python3
"""Import all hostname rows from Netsplit's linked TLD directory pages."""
import concurrent.futures, datetime, html, json, pathlib, re, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = 'https://netsplit.de'
def fetch(path):
    return subprocess.check_output(['curl', '--fail', '--silent', '--show-error', '--location', '--retry', '2', '--max-time', '40', BASE + path], text=True)
def parse_group(path):
    page = fetch(path).replace('<b>one IRC server</b>', '<b>1 IRC server</b>')
    if not re.search(r'<b>([0-9]+) IRC servers?</b>', page):
        raise ValueError(f'Missing count: {path}')
    expected = int(re.search(r'<b>([0-9]+) IRC servers?</b>', page)[1])
    cells = re.findall(r'<td valign="top"[^>]*>(.*?)</td>', page, re.S)
    hosts = []
    for cell in cells:
        for entry in re.split(r'<br\s*/?>', cell):
            reversed_host = html.unescape(re.sub(r'<[^>]+>', '', entry)).strip()
            if not reversed_host:
                continue
            host = '.'.join(reversed_host.split('.')[::-1]).lower()
            if not re.fullmatch(r'[a-z0-9_.*-]+', host):
                raise ValueError(f'Unexpected hostname {host!r}')
            hosts.append(host)
    if len(hosts) != expected:
        raise ValueError(f'{path}: expected {expected}, parsed {len(hosts)}')
    return path, hosts
index = fetch('/servers/')
paths = sorted(set(re.findall(r'href="(/servers/[a-z]+/)"', index)))
if not paths:
    raise ValueError('No directory groups found')
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    groups = list(pool.map(parse_group, paths))
hosts = sorted({host for _, entries in groups for host in entries})
excluded = [host for host in hosts if not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}', host)]
hosts = [host for host in hosts if host not in excluded]
servers = [dict(name=host, host=host, port=6697, tls=True, channel='') for host in hosts]
(ROOT / 'Assets/netsplit-servers.json').write_text(json.dumps(servers, indent=2) + '\n')
metadata = dict(source=BASE + '/servers/', fetchedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), count=len(hosts), excludedHostnames=excluded, filter='Concrete DNS hostnames only; wildcard and malformed entries excluded.', defaultPortNote='Directory lists hostnames only; TLS/6697 is an editable default, not verified server support.', groups={path:len(entries) for path,entries in groups})
(ROOT / 'Assets/netsplit-source.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(f'Imported {len(hosts)} unique servers from {len(groups)} groups; every group count matched.')
