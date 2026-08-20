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

Idle, it widens the notch a little to the right and shows how many people you've
reached out to today. It never reaches below the menu bar, so it can't cover
anything in the app underneath.

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
- **Star anything important** — starred cards sort to the top of their column and
  get a gold edge. No separate bucket to keep in sync.
- **Assign to a teammate** — click the avatar on a card.
- **Deleting asks first** — the card flips to a confirmation instead of
  vanishing under the pointer.
- **Tasks left today** — the left rail counts everything not yet Done across the
  team, with the split per column and how many are on you.
- **Outreach counter** — per person, per day. `+` / `−` on the right, with a
  confirmation before reset. The panel also shows the team's total for the day.
- **A nudge** — once a minute the idle number turns into a face, blinks, and
  smiles at you, so outreach doesn't quietly fall off the day.
  <img src="docs/nudge.png" width="60" align="center" alt="the nudge face">
  Turn it off by right-clicking the notch.
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

## Install

Grab `NotchCounter.zip` from [Releases](../../releases), unzip, and drop
`Notch Counter.app` in `/Applications`.

It's ad-hoc signed (no paid Apple Developer account), so macOS quarantines it on
first launch. Clear that once:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Counter.app"
```

Nothing appears in the Dock — the number just shows up next to the notch.
To start it at login: **System Settings → General → Login Items → +**.
Right-click the notch to quit.

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
| [`BoardView.swift`](Sources/NotchCounter/BoardView.swift) | Columns, cards, the outreach rail. |
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

**Writes are optimistic.** The UI updates immediately, the query goes out, and
the next poll reconciles. Polling is every 3 s while the panel is open, 25 s
while it's closed — and opening the panel forces a refresh, so a hover never
shows you a board that's 25 s stale.

**Avatar colours are hashed from the UUID's bytes**, not `hashValue` — that one
is seeded per process, so everyone would change colour on every launch and look
different on each teammate's Mac.

**`Menu` labels flatten custom backgrounds** on macOS, which ate the avatar
colours — the assignee picker pops an `NSMenu` from a plain button instead.

## License

MIT — see [LICENSE](LICENSE).
