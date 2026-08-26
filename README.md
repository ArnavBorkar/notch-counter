<p align="center">
  <img src="docs/icon.png" width="128" alt="Notch Counter icon">
</p>

<h1 align="center">Notch Counter</h1>

<p align="center">
  A shared kanban board and a daily outreach counter, living in the MacBook notch.<br>
  Inspired by <a href="https://github.com/TheBoredTeam/boring.notch">TheBoringNotch</a> — but instead of a smiley, it shows your number.
</p>

<p align="center">
  <img src="docs/idle.png" width="420" alt="Idle state">
</p>

Idle, it widens the notch both ways: what day you're on since you started on the
left, how many people you've reached out to today on the right. It never reaches
below the menu bar, so it can't cover anything in the app underneath.

Hover it and the whole board drops down. The board is shared — every person
running the app against the same database sees the same cards, and changes show
up within a few seconds.

<p align="center">
  <img src="docs/board.png" width="900" alt="The board">
</p>

Tasks left on the team's plate down the left, three columns in the middle, your
outreach counter on the right.

## What's in it

- **Kanban** — Backlog / In Progress / Done. Drag a card between columns, or use
  the arrows that appear on hover.
- **Drag to prioritise** — drop a card between two others to place it exactly
  where you want in the stack. Only the dragged row is written: its position
  becomes the midpoint between its new neighbours. Starred cards still float to
  the top of their column, so manual order applies within each group.
- **Card details** — click a card to open it: an editable title, a formatted body
  for notes, links or acceptance criteria, plus status, assignee, star, delete
  and Done in one place. Edits autosave as you type, so leaving never loses work.
  Cards carrying details show a small ≡ mark on the board.
- **Basic rich text** — bold, italic, underline and bullet lists, from the
  toolbar or ⌘B / ⌘I / ⌘U. Typing `- ` or `* ` at the start of a line turns it
  into a bullet, Return continues the list, and an empty bullet ends it. Bodies with formatting are stored as RTF; plain notes stay plain
  text in the database so they're still readable straight out of psql.
- **Star anything important** — starred cards sort to the top of their column and
  get a gold edge. No separate bucket to keep in sync.
- **Assign to a teammate** — click the avatar on a card.
- **Deleting asks first** — the card flips to a confirmation instead of
  vanishing under the pointer.
- **Day counter** — days since 15 August in the notch, so the clock is always in
  front of you. Override the date with `"countingSince": "2026-08-15"` in
  config.json.
- **Tasks left today** — the left rail counts everything not yet Done across the
  team, with the split per column and how many are on you.
- **Outreach counter** — per person, per day. `+` / `−` on the right, with a
  confirmation before reset. The panel also shows the team's total for the day.
- **A nudge** — every eight minutes a short band of light crawls around the
  notch outline, then the face scowls, then the day count warms and pings. The
  glow is drawn behind the black fill, so it only ever spills outward and the
  interior stays pure black.
  <img src="docs/nudge-fire.png" width="34" align="center" alt="the flame">
  <img src="docs/nudge.png" width="52" align="center" alt="the nudge face">
  Turn it off by right-clicking the notch.
- **Haptics on everything** — the panel lands with a double thunk, the counter
  ticks, moving a card gives a rising pair, deleting buzzes twice, and the nudge
  stutters. macOS only exposes three feedback patterns, so the character comes
  from how they're sequenced. Right-click the notch to turn them off.
- **A menu bar item** — open the board, refresh, toggle the nudge and haptics,
  log out, restart, or quit, without going near the notch.
- **Accounts** — email and a 4-digit PIN. Anyone can create one.

Everything lives in Postgres (a free Neon database works well). The count is
keyed by date, so it starts fresh each morning on its own — the Reset button is
there for when you miscount.

## Setup

**1. Make a database.** Any Postgres will do. On [Neon](https://neon.tech),
create a project and copy the connection string — it looks like
`postgresql://user:password@ep-something.region.aws.neon.tech/neondb?sslmode=require`.

**2. Point the app at it.** Either paste the string into the setup screen the
first time you hover the notch (it's stored in your login keychain), or drop it
in a config file:

```bash
mkdir -p ~/.config/notch-counter
echo '{ "databaseURL": "postgresql://..." }' > ~/.config/notch-counter/config.json
```

The app creates its tables (`nc_users`, `nc_tasks`, `nc_outreach`) on first
connect — see [docs/schema.sql](docs/schema.sql).

**3. Everyone else does the same.** Same connection string, their own account.

### A word on the security model

The app talks to Postgres directly, so **the connection string is the real
credential** — anyone holding it has full read/write access to the board,
whatever their PIN is. The 4-digit PIN only decides which name your cards get
filed under; it is not a security boundary. That's a deliberate trade for a
small team tool with nothing to deploy. Don't put anything sensitive on this
board, and don't commit the connection string.

If you outgrow that, put a small API in front of Neon and have the app talk to
that instead — `Database.swift` is the only file that would change.

## Updates

The app checks GitHub for a newer release on launch and every six hours. When
there is one, a blue dot appears next to the day count in the notch and a banner
offers it at the top of the board — **Install** downloads it, replaces the app in
place, and relaunches. There's also **Check for updates** in the menu bar item.

To publish one:

```bash
echo "2.2.0" > VERSION
./release.sh "What changed."
```

`release.sh` refuses to publish if the tag already exists or if the version
inside the built bundle doesn't match `VERSION` — a release whose bundle claims
an older version than its tag would make every client update, come back looking
old, and update again forever. The app also remembers the last tag it installed
as a second line of defence.

## Install

Grab `NotchCounter.zip` from [Releases](../../releases), unzip, and drop
`Notch Counter.app` in `/Applications`.

It's ad-hoc signed (no paid Apple Developer account), so macOS quarantines it on
first launch. Clear that once:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Counter.app"
```

Nothing appears in the Dock. There's a menu bar item — a small notch glyph —
with Open board, Refresh, the nudge and haptics toggles, Log out, Restart, and
Quit. Right-clicking the notch itself gets you a shorter version of the same.
To start it at login: **System Settings → General → Login Items → +**.

## Build

Requires Xcode 15+ / Swift 5.9+, macOS 14+.

```bash
git clone https://github.com/ArnavBorkar/notch-counter.git
cd notch-counter
./build-app.sh
open "dist/Notch Counter.app"
```

To develop against a local database instead of Neon:

```bash
createdb notchboard_dev
NOTCH_DB_URL="postgresql://$USER@localhost:5432/notchboard_dev?sslmode=disable" ./.build/release/NotchCounter
```

## How it works

| File | What it does |
| --- | --- |
| [`Geometry.swift`](Sources/NotchCounter/Geometry.swift) | Reads the real notch bounds from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, and sizes the panel per state. |
| [`NotchShape.swift`](Sources/NotchCounter/NotchShape.swift) | The silhouette — concave shoulders on top, rounded corners below. |
| [`NotchWindow.swift`](Sources/NotchCounter/NotchWindow.swift) | A borderless non-activating `NSPanel` pinned above the menu bar level. |
| [`Database.swift`](Sources/NotchCounter/Database.swift) | Every query, over PostgresNIO. Swap this file to move behind an API. |
| [`AppState.swift`](Sources/NotchCounter/AppState.swift) | One observable object: phase, session, board, polling, optimistic writes. |
| [`BoardView.swift`](Sources/NotchCounter/BoardView.swift) | Columns, cards, the two rails. |
| [`TaskDetail.swift`](Sources/NotchCounter/TaskDetail.swift) | The opened card — title, details body, properties, autosave. |
| [`RichText.swift`](Sources/NotchCounter/RichText.swift) | The formatted editor: trait toggling, bullets, ⌘B/I/U, and RTF round-tripping. |
| [`Updater.swift`](Sources/NotchCounter/Updater.swift) | Checks GitHub releases, downloads the zip, and swaps the bundle after this process exits. |
| [`MenuBarItem.swift`](Sources/NotchCounter/MenuBarItem.swift) | The status item and its menu, including the relaunch-after-exit restart. |
| [`Haptics.swift`](Sources/NotchCounter/Haptics.swift) | Every buzz, and the sequences that give each action its own feel. |
| [`Tools/make-icon.swift`](Tools/make-icon.swift) | Draws `AppIcon.icns` from scratch with Core Graphics. |

Details worth knowing if you're reading the code:

**Clicks pass through.** The panel is always as large as the biggest state, so
`PassthroughContainer.hitTest` returns `nil` for anything outside the currently
visible shape. The rest of your menu bar keeps working.

**Hover is polled, not tracked.** An 80 ms poll of `NSEvent.mouseLocation` beats
`NSTrackingArea` here: it works regardless of which app is focused, and it
doesn't flicker when the window resizes under the pointer. Opening waits ~180 ms
so a stray pointer doesn't drop the whole board on you; clicking into the panel
pins it open until you press Esc or click away.

**Writes are optimistic, and a poll can't undo them.** The UI updates
immediately, the query goes out, and the next poll reconciles. Polling is every
3 s while the panel is open, 25 s while it's closed — and opening the panel
forces a refresh, so a hover never shows a board that's 25 s stale.

The subtle part is that a fetch already in flight when you move a card was read
*before* your move, so applying it would snap the card back until the write's
own refresh arrived. `AppState` counts edits: a refresh records the count when
it starts and drops its result if the count changed or a write is still in
flight. Optimistic moves also take the position the server will give them, so
the card doesn't reshuffle when the real row arrives.

**Avatar colours are hashed from the UUID's bytes**, not `hashValue` — that one
is seeded per process, so everyone would change colour on every launch and look
different on each teammate's Mac.

**`Menu` labels flatten custom backgrounds** on macOS, which ate the avatar
colours — the assignee picker pops an `NSMenu` from a plain button instead.

## License

MIT — see [LICENSE](LICENSE).
