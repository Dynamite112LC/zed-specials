# Zed Specials

Tracks the specials leaflets of Shoprite, Pick n Pay and Game in Zambia,
reads the prices off them, and compares the same or similar items across
shops. Flutter app for Android and web.

## How it fits together

```
tool/update_feed.dart   scrapes the shops, reads the leaflets, writes the feed
assets/data/feed.json   catalogues + every price read (bundled with the app)
assets/data/pages/      leaflet pages, shrunk for phones (not in git)
assets/data/crops/      a small product picture per price (not in git)
data/history.json       every price from every leaflet seen ("data" branch)
lib/                    the app, which only reads the feed
```

Only `feed.json` is packed into the app. Leaflet pictures change weekly, so
the app loads them from the hosted feed instead of carrying them around.

## Automatic updates

`.github/workflows/update-feed.yml` rebuilds the feed every day at 06:00
Zambian time and publishes it with GitHub Pages at:

    https://dynamite112lc.github.io/zed-specials/feed.json

That address is built into the app. It checks for new specials every time
it opens, when it comes back to the foreground after a few hours, and on
pull to refresh.

It runs again at 12:00, because a shop's site sometimes refuses the server
the morning run happened to get. A shop that cannot be reached is filled
in with the leaflets it had on the last run that did reach it, for up to
three days (`tool/src/scrape_memory.dart`). That list is kept on the `data`
branch as `last-scrape.json`, so running the feed builder on your own
computer and pushing `data` also covers for the job when a shop refuses
GitHub's servers.

The job runs with `--strict`: if a shop stays out of reach beyond that, or
a leaflet's pages are missing, it fails and leaves the last complete feed
online, and GitHub emails you about the failed run.
To run it by hand, use "Run workflow" on the repository's Actions tab.

## Price history

Shops take a leaflet down when it ends, so the feed builder keeps its own
record: `data/history.json` holds what each product cost in each leaflet,
going back 18 months. When a product comes round again the feed carries
its earlier prices, at the same shop and at the others, and the app shows
them on the item ("Down K5", "It has been lower: K29.99 at Pick n Pay").

The file lives on the `data` branch, where the daily job commits it, so
those commits never collide with work on `main`. To have the same history
when running the feed builder on your own machine:

```
git fetch origin data
git worktree add data data
```

Without that, a local run starts an empty history in `data/`, which git
ignores. A leaflet that is still published is re-read on every run and its
recorded prices replaced, so a fix to a price reader also corrects the
history for current leaflets.

## Running the app

```
flutter run -d chrome
flutter build apk
```

To point a build at another feed, add
`--dart-define=FEED_URL=https://example.com/feed.json`, or change the
address in the app's settings.

## Updating the specials

One-time setup for the price reader (free, runs offline):

```
python -m venv tool/.venv
tool/.venv/Scripts/python -m pip install rapidocr onnxruntime
```

`pdftoppm` (Poppler) must be on the PATH for Pick n Pay's PDF leaflets.

Then, whenever you want fresh specials:

```
dart run tool/update_feed.dart
```

Pages and OCR results are cached in `.cache/`, so only new leaflets are
processed. To use a Python environment somewhere else, set `ZED_OCR_PYTHON`
to its `python` executable.

## Where the data comes from

| Shop | Source | Format |
|---|---|---|
| Shoprite | shoprite.co.zm/specials.html (Cairo Road, Lusaka leaflets) | page images |
| Pick n Pay | picknpayzambia.com/specials | PDF |
| Game | game.co.zm promotions (served by Guzzle) | page images |

Prices are read by OCR and each shop has its own reader in
`tool/src/extract.dart`. Multi-buys ("ANY 2 FOR K70") are shown as the
price of one, with the deal in the name. Readings can be wrong: the app says so on every
item and links back to the leaflet page. `dart run tool/dump_items.dart
<shop> .cache/<folder>` prints what a reader finds, for checking by eye
after a shop changes its leaflet design.

Products are matched across shops in `tool/src/matching.dart` by brand,
name and pack size.
