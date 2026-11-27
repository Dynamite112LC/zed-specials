# Zed Specials

Tracks the specials leaflets of Shoprite, Pick n Pay and Game in Zambia,
reads the prices off them, and compares the same or similar items across
shops. Flutter app for Android and web.

## How it fits together

```
tool/update_feed.dart   scrapes the shops, reads the leaflets, writes the feed
assets/data/feed.json   catalogues + every price read (bundled with the app)
assets/data/pages/      leaflet pages, shrunk for phones
assets/data/crops/      a small product picture per price
lib/                    the app, which only reads the feed
```

The app shows the feed bundled at build time. If you host the `assets/data`
folder somewhere (GitHub Pages, any static host) and enter the address of
`feed.json` in the app's settings, it downloads fresh specials on refresh
instead.

## Running the app

```
flutter run -d chrome
flutter run            # with a phone or emulator connected
```

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
`tool/src/extract.dart`. Readings can be wrong: the app says so on every
item and links back to the leaflet page. `dart run tool/dump_items.dart
<shop> .cache/<folder>` prints what a reader finds, for checking by eye
after a shop changes its leaflet design.

Products are matched across shops in `tool/src/matching.dart` by brand,
name and pack size.
