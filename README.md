# Shy

An indie browser for the Mac. Small, safe, and out of your way.

macOS 14 or later · 8.6 MB installed, 4.2 MB zipped · MIT

## Why Shy

Browsers keep growing: more panels, more services, more things asking for your attention, and more code that can go wrong. Shy goes the other way. It is the smallest set of features you need to get real work done, built on WebKit, the engine already in macOS, with security weighed before anything else.

Shy isn't a toy or a demo. Its goal is to be a real, independent alternative to the browsers made by the biggest companies, one you can use all day.

## What it does

- **Tabs down the side.** Pins that always go back to the page you pinned, folders, spaces (`⌃1`–`⌃9`), and profiles that keep their sign-ins and history apart. `⌘1`–`⌘9`, `⌘K` to switch, two pages side by side.
- **Quiet pages.** Ads and trackers are blocked before they load. Hide anything on a site for good (`⇧⌘H`), read without the clutter (`⇧⌘R`), float a video (`⇧⌘P`), Shift-click a link to peek at it.
- **Light on your Mac.** Tabs you don't use go to sleep, and nothing runs that you didn't open.
- **Agents you can watch.** Turn on Settings › Agents and any MCP client can browse for you, in private pages in an Agent folder you can see and use. Your tabs, sign-ins and passwords stay yours. To let an agent use one site as you, right-click a tab and choose **Hand Over to Agent…**. It gets a copy of that one site's sign-in, read-only unless you say otherwise, locked to that site, and deleted when the time you chose is up. Every step it takes is written down.

## Security first

- **A small surface.** A thin layer over WebKit. The less code, the less there is to go wrong, and WebKit does the hard parts.
- **Nothing phones home.** No account, no sync, no telemetry, no update check. Nothing listens on the network.
- **Your secrets stay in macOS.** Passwords live in the keychain, behind Touch ID.
- **Off unless you ask.** Anything that could reach your data, such as agents or scripts driving the browser, is off until you turn it on in Settings.
- **Reviewed for what it opens.** Every change is read for what it lets in, not only for what it adds.

## Built with agents, and with you

Shy is engineered with AI agents and reviewed by a person. It's an indie project, and it grows by people who want a browser like this one. If you do, come build it together:

- Use it, and [open an issue](https://github.com/nxcco/shy/issues) when something is wrong or missing.
- Pick an [open issue](https://github.com/nxcco/shy/issues), or propose something small that belongs in Shy.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) first: what gets merged, and why Shy stays small.

Report security issues privately, as [SECURITY.md](SECURITY.md) explains.

## Building

```bash
./install.sh     # build Shy and put it in /Applications
swift build      # the app and shy-mcp
./build.sh       # build/Shy.app
swift test       # unit tests; Tests/*.py drive a hidden copy of the app
```

Shy began as a fork of [Search](https://github.com/driceroland/Search) by Office Commun and follows its own line: low complexity, no feature it doesn't need, no more growth than necessary. Stay shy.

MIT, see [LICENSE](LICENSE).
