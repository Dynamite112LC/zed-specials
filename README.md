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
| Pick n Pay | picknpayzambia.com/specials | PDF (its own text where it has it) |
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

Where a shop publishes its leaflet as a PDF that still holds its words as
text (two of Pick n Pay's three did when this was written), that text is
used instead of OCR (`tool/src/pdf_text.dart`). It is exact, where OCR was
misreading many of the small raised ngwee. OCR still runs on those pages,
as the check on the text and to fill in letter pairs such as "ff" that
some PDFs cannot name.

Each item in the feed records where it sits on its page, so the app can
show that part of the leaflet enlarged: tap an item's picture to compare
the reading with what is printed.

### The second reader

Pages read by OCR are read a second time by a vision model that looks at
the whole page and lists every product with its price. It is a small open
model (Qwen3.5 4B, Apache 2.0) run by llama.cpp on the scheduled job's own
machine: there is no account and no fee, and the pages are sent nowhere
else. A page takes two to three minutes there, so the `second-reader` job
runs after the feed is published, saves its readings in `second/` on the
`data` branch, and starts a new run that builds the feed with both
readings. Only new pages are read; a leaflet's readings are dropped when
the leaflet is.

The two readers fail differently, so they are put together rather than one
replacing the other (`tool/src/second_reader.dart`):

- A price both give is marked as agreed, and the app says so.
- Where the kwacha differ, the first reading is shown and the other one is
  carried; the app asks you to check the picture. The run's log lists
  these. Checked against the leaflets, either reader can be the one that
  is right here.
- Where only the ngwee differ, what is known of the second reader decides.
  It loses digits but does not make them up: it runs raised ngwee into the
  kwacha (2699 for 26.99), loses one doing so (2699 for 269.99), or leaves
  them out (399 for 399.99). So ngwee it reports where the first reader
  has none ("K399" for a printed K399.99) are shown, with the first
  reading carried for checking; ngwee it leaves out change nothing.
- Where the first reader could not read the raised ngwee and assumed
  ".99", a whole-kwacha price from the second reader replaces it only on a
  page both readers find priced in whole kwacha.
- A multi-buy ("2 for K70", shown as K35 each) agrees when the second
  reader gives the K70.
- Pack sizes the first reader garbled or lost ("2L" read as "2", "36cm" as
  "3b") are taken from the second. Words keep the first reader's spelling,
  which is the better one.
- An item only the second reader names is added when the page's own text
  shows its price and its words in one place; otherwise it is left out and
  listed in the log. Several products it gives one price (a combo listed
  piece by piece) are left out.

To run it on your own computer, start a model server that speaks the
OpenAI chat API with images (llama.cpp's `llama-server`, or Ollama) and,
after a feed build, run:

```
python tool/second_reader.py --server http://127.0.0.1:11434 --model qwen3.5:4b
dart run tool/update_feed.dart
```

### Corrections

When a reading is wrong, "Fix this reading" in the app takes the right
price or name. The fix shows on that device at once. "Save and send to the
feed" also opens a filled-in issue on this repository; once submitted, the
feed builder applies it at its next run (`tool/src/corrections.dart`), so
it reaches every device and the price history. Only issues written by the
repository's owner count, and each correction is checked field by field.
A correction is tied to the reading it was made against, so it lapses on
its own if the reader later gets the item right.

`test/readers_test.dart` and `test/second_reader_test.dart` check the
readers against real pages kept
in `test/fixtures`. When a shop changes its leaflet design, add a page of
the new design there with the prices you can see on it.

Readings can still be wrong: the app says so on every
item and links back to the leaflet page. `dart run tool/dump_items.dart
<shop> .cache/<folder>` prints what a reader finds, for checking by eye
after a shop changes its leaflet design.

Products are matched across shops in `tool/src/matching.dart` by brand,
name and pack size.
