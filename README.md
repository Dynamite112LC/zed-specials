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

It runs again at 12:00.

### When a shop refuses GitHub's servers

Shoprite's main site (www.shoprite.co.zm) blocks GitHub's servers; the
host that serves its leaflets (specials.shoprite.co.zm) does not. So the
job cannot see which leaflets Shoprite currently lists, but it can read
any leaflet it already knows about.

A shop that cannot be reached is therefore filled in with the leaflets it
had on the last run that did reach it, each until its own end date
(`tool/src/scrape_memory.dart`). The other shops keep updating. What gets
missed is a new leaflet from the blocked shop. Once a shop has been out of
reach for more than three days the job still publishes, then fails its
last step so that GitHub emails you.

The list of known leaflets is kept on the `data` branch as
`last-scrape.json`. To bring a blocked shop up to date, run this on a
computer the shop does answer (a home connection works):

```
pwsh -File tool/update-leaflet-lists.ps1
```

It asks each shop's specials page once, writes today's lists, and pushes
them to the `data` branch. When it finds a leaflet GitHub did not know
about, it also starts the GitHub job, which reads the new leaflet from the
leaflet host and publishes it. It takes a few seconds and needs neither
Python nor the OCR setup. Its log is `.cache/leaflet-lists.log`.

### Daily run on your own computer

To have Windows run that script every day (at 07:30, or as soon as the
computer is next switched on and online):

```
$script = (Resolve-Path tool/update-leaflet-lists.ps1).Path
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -WindowStyle Hidden -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At 7:30am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName 'Zed Specials leaflet lists' -Action $action -Trigger $trigger -Settings $settings
```

The task runs as you, while you are signed in, and pushes with the git
sign-in already saved on the computer. Remove it with
`Unregister-ScheduledTask -TaskName 'Zed Specials leaflet lists'`. If the
project folder moves, register it again from the new place.

The job runs with `--strict`: if a shop fails that has never been reached,
or a leaflet's pages are missing, it stops and leaves the last complete
feed online, and GitHub emails you about the failed run.
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
| Shoprite | shoprite.co.zm/specials.html, one store per province and kind of shop | page images |
| Pick n Pay | picknpayzambia.com/specials | PDF |
| Game | game.co.zm promotions (served by Guzzle) | page images |

### Shoprite's stores

Shoprite shows each store the leaflets for its province and its kind of
shop (Shoprite, Select, Mini, LiquorShop). The feed builder asks about one
store for each such area, 17 requests a couple of seconds apart, and reads
a leaflet listed in several areas once. Each leaflet in the feed says where
it applies ("All Shoprite supermarkets", "Shoprite LiquorShop stores"), and
in the app's settings you can choose your own store to see only its
leaflets. The list of stores is in `lib/src/shoprite_stores.dart`; it was
copied by hand from Shoprite's store locator and needs a hand edit when
Shoprite opens or closes a store.

### How the leaflets are read

Prices are read by OCR and each shop has its own reader in
`tool/src/extract.dart`. Multi-buys ("ANY 2 FOR K70") are shown as the
price of one, with the deal in the name. Shoprite's prices are also read a second way, by
their colours (`find_flashes` in `tool/ocr.py`): general OCR gets the small
print right but misreads about a third of the big stylised price digits,
while a red-on-yellow or yellow-on-red price can be cut out cleanly and
its kwacha and raised ngwee read separately. Descriptions are then matched
to the nearest price, whether they sit under it (food), beside or above it
(toys, homeware) or around a price box (Game's appliances).

`test/readers_test.dart` checks the readers against four real pages kept
in `test/fixtures`. When a shop changes its leaflet design, add a page of
the new design there with the prices you can see on it.

Readings can still be wrong: the app says so on every
item and links back to the leaflet page. `dart run tool/dump_items.dart
<shop> .cache/<folder>` prints what a reader finds, for checking by eye
after a shop changes its leaflet design.

Products are matched across shops in `tool/src/matching.dart` by brand,
name and pack size.
