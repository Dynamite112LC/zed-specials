"""Reads leaflet pages a second time, with a vision model.

The feed builder (tool/update_feed.dart) reads every page with OCR and lists
the pages still waiting for a second reading in <dir>/pending.json. This
script shows each of those pages to a vision model, asks for every product
and its price, and saves what it says as <dir>/<page>.json. The next feed
build puts the two readings together (tool/src/second_reader.dart).

The model runs on this machine, behind a server that speaks the OpenAI chat
API: llama.cpp's llama-server (what the scheduled job uses), or Ollama.
Nothing is sent anywhere else and no account is needed.

  python tool/second_reader.py --images assets/data --dir data/second

  --server URL        the model's server (default http://127.0.0.1:8080)
  --model NAME        model name to ask for; llama-server ignores it, Ollama
                      needs it (for example qwen3.5:4b)
  --images WHERE      folder or web address the page images are under
  --dir DIR           where pending.json is and the readings go
  --budget-minutes N  stop starting new pages after this long (default 300)
  --limit N           read at most N pages

Only the Python standard library is used.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.request

PROMPT = (
    'This is a page from a supermarket specials leaflet in Zambia. List every product '
    'on it with its price in kwacha. Two small raised digits after a price are ngwee '
    '(cents): a big 149 with a small 99 is 149.99. Give each product once, with the '
    'name as printed.'
)
SCHEMA = {
    'type': 'object',
    'properties': {
        'items': {
            'type': 'array',
            'items': {
                'type': 'object',
                'properties': {'name': {'type': 'string'}, 'price': {'type': 'number'}},
                'required': ['name', 'price'],
                'additionalProperties': False,
            },
        },
    },
    'required': ['items'],
    'additionalProperties': False,
}
# A crowded page has 35 to 40 products; this leaves room for twice that.
MAX_TOKENS = 3200
# A page takes 1.5 to 3 minutes on four processors.
PAGE_TIMEOUT = 1500


def load_image(where, name):
    if where.startswith('http://') or where.startswith('https://'):
        with urllib.request.urlopen(where.rstrip('/') + '/' + name, timeout=120) as res:
            return res.read()
    with open(os.path.join(where, name), 'rb') as f:
        return f.read()


def ask(server, model, image):
    body = {
        'messages': [{
            'role': 'user',
            'content': [
                {'type': 'image_url', 'image_url': {
                    'url': 'data:image/jpeg;base64,' + base64.b64encode(image).decode()}},
                {'type': 'text', 'text': PROMPT},
            ],
        }],
        'temperature': 0,
        'max_tokens': MAX_TOKENS,
        'response_format': {
            'type': 'json_schema',
            'json_schema': {'name': 'reading', 'strict': True, 'schema': SCHEMA},
        },
    }
    if model:
        body['model'] = model
    req = urllib.request.Request(
        server.rstrip('/') + '/v1/chat/completions',
        data=json.dumps(body).encode(),
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=PAGE_TIMEOUT) as res:
        answer = json.load(res)
    choice = answer['choices'][0]
    # Cut off by the token limit: the list is incomplete and may not parse.
    if choice.get('finish_reason') == 'length':
        raise ValueError('the answer was cut off')
    items = json.loads(choice['message'].get('content') or '')['items']
    out = []
    for it in items:
        name, price = it.get('name'), it.get('price')
        if isinstance(name, str) and isinstance(price, (int, float)) and not isinstance(price, bool):
            out.append({'name': name.strip(), 'price': price})
    return out, answer.get('model') or model or ''


def write_json(path, doc):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--server', default='http://127.0.0.1:8080')
    ap.add_argument('--model', default='')
    ap.add_argument('--images', default='assets/data')
    ap.add_argument('--dir', default='data/second')
    ap.add_argument('--budget-minutes', type=float, default=300)
    ap.add_argument('--limit', type=int, default=0)
    args = ap.parse_args()

    pending_file = os.path.join(args.dir, 'pending.json')
    if not os.path.exists(pending_file):
        print('No list of pages to read (run the feed builder first).')
        return 0
    with open(pending_file, encoding='utf-8') as f:
        pending = json.load(f)
    if args.limit:
        pending = pending[:args.limit]
    print(f'{len(pending)} pages to read a second time', flush=True)

    started = time.time()
    done = failed = 0
    slowest = 0.0
    for n, page in enumerate(pending, 1):
        key, image_name = page['key'], page['image']
        out = os.path.join(args.dir, key + '.json')
        # Stop while there is still time to save what has been read.
        spent = (time.time() - started) / 60
        if spent + max(slowest, 3.0) > args.budget_minutes:
            print(f'Out of time after {spent:.0f} minutes; the rest wait for the next run.')
            break
        attempts = 0
        if os.path.exists(out):
            try:
                with open(out, encoding='utf-8') as f:
                    earlier = json.load(f)
                if 'items' in earlier:
                    continue
                attempts = int(earlier.get('failed', 0))
            except (ValueError, OSError):
                pass
        t0 = time.time()
        try:
            items, model = ask(args.server, args.model, load_image(args.images, image_name))
        except Exception as e:  # noqa: BLE001 - any failure is recorded, the run goes on
            took = time.time() - t0
            failed += 1
            write_json(out, {'failed': attempts + 1, 'error': str(e)[:200]})
            print(f'[{n}/{len(pending)}] {key}: failed after {took:.0f}s: {e}', flush=True)
            continue
        took = time.time() - t0
        slowest = max(slowest, took / 60)
        done += 1
        write_json(out, {
            'model': model,
            'read': time.strftime('%Y-%m-%d', time.gmtime()),
            'seconds': round(took),
            'items': items,
        })
        print(f'[{n}/{len(pending)}] {key}: {len(items)} products in {took:.0f}s', flush=True)

    left = len(pending) - done - failed
    print(f'Read {done} pages, {failed} failed, {left} left.', flush=True)
    gh = os.environ.get('GITHUB_OUTPUT')
    if gh:
        with open(gh, 'a', encoding='utf-8') as f:
            f.write(f'read={done}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
