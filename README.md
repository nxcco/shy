# Shy

The shy browser, for the Mac. It stays out of the way.

![Shy, with its tabs down the left and a page taking the rest of the window](.github/screenshot.png)

macOS 14 or later · free · around 8 MB · a fork of [Search](https://github.com/driceroland/Search) by Office Commun

---

## Why shy

Most browsers want something from you: a start page, a feed, an account, a sidebar of suggestions, a badge to clear. Shy wants nothing. A row of tabs, the page, and one field to type in. Everything else waits until you reach for it, and stays out of sight when you don't.

- **Small.** It runs on WebKit, the engine already inside every Mac, the one Safari uses. There is no second copy of Chromium to download, update and hold in memory, so the whole app is a few megabytes and opens at once.
- **Efficient.** A tab from yesterday costs nothing until you click it. A tab you leave alone lets its page go and comes back where you left it. Ads and trackers are stopped inside WebKit's networking before a request is made, so there is nothing to draw and nothing to slow down.
- **Tidy.** Tabs, pins, groups, spaces and profiles, each doing one clear job, organized the way Arc taught people to like.
- **Quiet.** No toolbar, no start page, no telemetry, nothing that asks for attention.
- **Helpful, if you ask.** Claude can browse in Shy for you, in private pages of its own, out of sight. It is off until you turn it on, and it never touches your tabs.

## Its own line

Shy is a fork of [Search](https://github.com/driceroland/Search), and follows a line of its own: keep the accidental complexity low, add no feature it doesn't need, and grow no more than necessary. When in doubt, it leaves something out. Stay shy.

It is built with AI agents, and safety and security are among its first concerns. Shy is a thin layer over WebKit, the engine macOS already ships and Apple keeps patched, so the code that could be attacked is small, and the hardest parts — running pages, isolating sites, the network — are WebKit's. What Shy adds is kept to that same standard: nothing listens on the network, what an agent may do is narrow and off by default, and every change is reviewed for what it opens up.

## Tabs, kept tidy

- **A column.** Tabs down the side of the window, left or right. `⌘S` folds it away until the pointer reaches the edge.
- **Pins, as in Arc.** Squares for the sites you live in, rows under them for pages you keep, and a line with Clear above the tabs that come and go. A pin stays on its site: a link elsewhere opens over it, and `⌘W` or a relaunch takes it back to the page it was pinned at. Press a pin's `⌘` number again to go back to where you were.
- **Groups.** Right-click a tab › New Tab Group. Click a group's heading to fold it.
- **Spaces.** Separate sets of tabs for separate parts of your life. Switch with `⌃1`–`⌃9`, two fingers sideways over the tabs, or a click on the space's icon, which opens a small drawer of your spaces: click to go, drag to reorder, `+` to add. Right-click the icon to rename it, give it an icon or a downloads folder, move it to another profile, or delete it.
- **Profiles.** A profile holds its own sign-ins and site data, history, bookmarks and passwords; every space belongs to one. Going to a space goes to its profile, in the same window: Work signed in to work mail, Personal to yours. Make one in Settings › Tabs › Profiles or from a space's menu.
- **Two pages side by side.** Drag a tab onto a page, or press `⌥⌘N`. `⌃⌘←` / `⌃⌘→` move between them.
- **Sleeping and closing.** Tabs you aren't using sleep sooner, later or never, your choice, and tabs you leave alone can close by themselves after a day, a week or a month. A site you need running, like a chat or a player, can be kept awake from its site card.
- **`⌘K`** finds any open tab by name; **`⌃Tab`** walks through them, with `⌃W`, `⌃R` and `⌃M` to close, reload or mute the one picked; holding **`⌘`** shows each tab's number.

## Less in the way

- **One field.** Type an address and you go there; type words and you search. Type the start of a site's name and `Tab` to search that site, or `settings` to go to Settings. Nothing you type leaves the Mac until you press Return, unless you turn on your engine's suggestions.
- **Hide anything, for good.** `⇧⌘H`, then click a cookie banner, a newsletter overlay or a rail of "related" links. It goes, and it is still gone on that site next time, before the page draws a frame.
- **Ad and tracker blocking**, on by default, off per site if something breaks.
- **Reading mode.** `⇧⌘R` keeps the article and drops the rest.
- **Video that follows you.** `⇧⌘P` floats a video in a small window above everything; it can also float by itself when you switch tabs or apps.
- **Peek.** Shift-click a link and its page opens over the one you are reading; Escape puts it away.
- **Passwords in your keychain.** Shy offers to save a sign-in once it has worked, and offers your accounts and the Mac's passkeys under the field when you click it, never filling anything on its own. Bring yours in from Chrome, Arc, Dia, Brave or Edge; nothing leaves the Mac.
- **Chrome extensions, without Chrome**, on WebKit's own extension engine (macOS 15.4 or later). Paste a Chrome Web Store link in Settings › Extensions.

## Claude, low-key

Turn on **Settings › Agents › Let Claude open pages**, copy the command it shows, and run it once:

```
claude mcp add search -- /Applications/Search.app/Contents/MacOS/search-mcp
```

Claude Code can then open web pages in Shy, read them, take pictures of them, click and type. That's all it can do, and all of it happens in Claude's own pages:

- They are private pages out of sight, never your tabs. Each has its own store, forgotten when it closes, with none of your cookies, sign-ins, passwords or extensions.
- They open http and https and nothing else: no files on your Mac, no downloads, no pop-up windows, no camera, microphone or location.
- No network port is opened. Claude's side talks to Shy over a socket in Shy's folder that only your user can reach, and the switch only counts if you turned it on in Settings.
- Settings › Agents shows how many pages Claude has open, with a button to close them all, and has a switch for each thing it may do: open pages, read them, take pictures, click, type.

There is no assistant pane, no chat button, and no AI anywhere you didn't ask for it.

## What it doesn't do

On purpose:

- No sync, no account, no cloud. Your tabs, history and passwords stay on your Mac.
- No telemetry, analytics or crash reports. What leaves your Mac is the pages you ask for, their icons, and one small request a day to check for an update.
- No start page, no feed, no suggestions you didn't ask for.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| Passwords | The macOS keychain, as items tagged `Search` (Personal) or `Search · <profile>` | Shy. Any other app gets the system's permission dialog. |
| History, bookmarks, open tabs, hidden elements | Small JSON files in `~/Library/Application Support/Search/`, history and bookmarks one file per profile | You. |
| Cookies and site data | WebKit's own stores: one per profile, and one for each space that kept sign-ins of its own | The sites that set them, as in any browser. |
| Claude's pages | In memory only, gone when closed | Nothing is kept. |
| Extensions | `~/Library/Application Support/Search/Extensions/`, their data in WebKit's extension store | Each extension, within the permissions you accepted. |
| Anything else | Nowhere. There is no server. | — |

A **private tab** (`⇧⌘N`) has its own cookie jar and leaves nothing behind. A page opened from a folder on your Mac can show the pictures beside it but can't read the other files there.

## Keyboard

| | |
|---|---|
| `⌘L` address · `⌘K` find a tab · `⌘T` new tab · `⌘W` close · `⇧⌘T` reopen | `⌘[` `⌘]` back, forward · `⇧⌘[` `⇧⌘]` previous, next tab · `⌘1`–`⌘9` jump |
| `⌘S` fold the column · `⌃1`–`⌃9` spaces | `⇧⌘R` reading mode · `⇧⌘P` float the video · `⇧⌘H` hide something |
| `⌥⌘N` split the page · `⌃⌘←` `⌃⌘→` between the two | `⌘F` find · `⌘Y` history · `⇧⌘J` downloads · `⌘,` settings |

Shortcuts can be changed in Settings › Shortcuts. `esc` puts away whatever is open.

---

## For developers

### Building it

- macOS 14 or later, Xcode 16 / Swift 6 toolchain. No dependencies beyond what Apple ships.
- `swift build` builds the app and `search-mcp`; `./build.sh` assembles a double-clickable app in `build/`, ad-hoc signed so it runs on your Mac. `SEARCH_DEV=1 ./build.sh` makes a dev build on a yellow icon, named for its branch.
- The app still builds as `Search.app`, with Search's bundle id and folders, so it shares settings, sign-ins and passwords with an installed Search.
- A build you make yourself isn't notarized, so the first launch needs right-click › Open.

### How it's put together

- **SwiftUI** for what is drawn, **AppKit** where SwiftUI doesn't reach, **WKWebView** for pages. One file per concern in `Sources/Search/`.
- `Tab.swift`: one tab per page, its web view built only when needed. `Spaces.swift` and `Profiles.swift`: which store, history, bookmarks and keychain drawer a space uses. `Vault.swift`: the keychain. `Shield.swift`: the ad blocker, a `WKContentRuleList`. `Curtain.swift`: hidden elements. `Session.swift`: what comes back at launch.
- `Agent.swift`: Claude's pages and their socket. `Sources/SearchMCP/`: `search-mcp`, the MCP server Claude runs, which only passes calls to that socket. It is signed on its own, with none of the app's entitlements. `LocalSocket.swift`: the user-only socket and the keychain mark behind both scripting switches.
- Extensions run on `WKWebExtension`; `ExtensionShims.swift` fills in the Chrome APIs WebKit lacks.

### Testing

- `swift test` runs the unit tests.
- `python3 Tests/<suite>.py`, after `./build.sh debug`, drives a hidden test run of the app with its own settings and files, removed afterwards. There is one suite per feature; `Tests/agent_mcp.py` covers Claude's pages and `Tests/file_siblings.py` local files.
- **Settings › General › Let a script drive Search** opens a socket that `./bench` speaks, for driving the running app from the shell: `./bench open https://example.com`, `./bench text <id>`, `./bench shot <id> out.png`, `./bench close all`.

### Contributing

Small changes, no new dependencies, nothing that phones home. See [CONTRIBUTING.md](CONTRIBUTING.md); report security problems privately, as [SECURITY.md](SECURITY.md) says.

### License

MIT, see [LICENSE](LICENSE). Shy is a fork of [Search](https://github.com/driceroland/Search) by Office Commun; "Search" and its icon are theirs.
