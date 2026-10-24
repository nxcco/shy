# Shy

A quiet browser for the Mac. It stays out of the way.

![Shy, with its tabs down the side and a page taking the rest of the window](.github/screenshot.png)

macOS 14 or later · around 8 MB · MIT

## What it is

A column of tabs, the page, and one field to type in. Nothing else asks for your attention.

- **Small and fast.** A thin layer over WebKit, the engine already in macOS. Tabs you don't look at sleep; ads and trackers are blocked before they load.
- **Tidy tabs.** Pins as in Arc, groups, spaces (`⌃1`–`⌃9`), and profiles that keep their own sign-ins, history, bookmarks and passwords. Two pages side by side with `⌥⌘N`.
- **Less distraction.** Hide any element for good (`⇧⌘H`), reading mode (`⇧⌘R`), a floating video (`⇧⌘P`), Shift-click to peek at a link.
- **Agents, if you want them.** Off by default. Turn on Settings › Agents and any MCP client (Claude Code, Cursor, Codex) can open pages, read, click and type — in private pages of its own, never your tabs. Each ability can be switched off.
- **Private.** No account, no sync, no telemetry. Passwords stay in the macOS keychain.

## Its own line

Shy is a fork of [Search](https://github.com/driceroland/Search) with a line of its own: low accidental complexity, no feature it doesn't need, no more growth than necessary. Stay shy.

It is built with AI agents, and safety comes first. Shy is a tiny wrapper around WebKit, so its attack surface is small and WebKit takes on the hard parts. Nothing listens on the network, and every change is reviewed for what it opens up.

## Building

```bash
swift build      # the app and search-mcp
./build.sh       # build/Search.app, ad-hoc signed
swift test       # unit tests; Tests/*.py drive a hidden copy of the app
```

The app still builds as `Search.app` and shares its folders with an installed Search. Report security issues privately, as [SECURITY.md](SECURITY.md) says.

MIT, see [LICENSE](LICENSE). "Search" and its icon are Office Commun's.
