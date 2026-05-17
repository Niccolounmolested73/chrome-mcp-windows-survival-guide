# Chrome MCP — Windows Survival Guide

Six real gotchas I hit installing and operating [`hangwin/mcp-chrome`](https://github.com/hangwin/mcp-chrome) on Windows 11 — the MCP server that drives your *actual* logged-in Chrome (not a fresh sandbox) so AI tools like [Claude Code](https://claude.ai/code) can act on your real accounts, cookies, sessions and bookmarks.

The official README covers the happy path. This guide covers the failure modes you'll hit on Windows 11 — each with the symptom you'll see, the root cause I traced, and the fix that actually worked. Two of them (#5 and #6) are upstream issues I opened and PR'd on 2026-05-18 — the rest are pure operator knowledge.

> **Audience:** anyone using `chrome-mcp` with Claude Code (or any MCP client) on Windows, especially with multiple Chrome profiles or alongside Anthropic's first-party Claude for Chrome extension.

---

## Table of contents

- [Quick install](#quick-install) — the happy path that *does* work
- [Diagnose first](#diagnose-which-gotcha-are-you-hitting) — which gotcha are you hitting?
- [Gotcha 1 — Chrome 136+ silently drops `--remote-debugging-port`](#gotcha-1--chrome-136-silently-drops---remote-debugging-port-on-the-default-profile)
- [Gotcha 2 — MCP boot has no auto-retry · install bridge BEFORE Claude CLI starts](#gotcha-2--mcp-boot-has-no-auto-retry--install-the-bridge-before-claude-cli-starts)
- [Gotcha 3 — bridge ↔ extension version sync](#gotcha-3--bridge-and-extension-versions-must-match)
- [Gotcha 4 — Claude for Chrome and chrome-mcp fight over `chrome.debugger`](#gotcha-4--claude-for-chrome-and-chrome-mcp-fight-over-chromedebugger-per-tab)
- [Gotcha 5 — Multi-session orphaning · singleton MCP Server reassigns transport](#gotcha-5--multi-session-orphaning--singleton-mcp-server-reassigns-transport)
- [Gotcha 6 — Multi-profile port collision · Approach B workaround](#gotcha-6--multi-profile-port-collision--approach-b-workaround)
- [Appendix · Upstream contributions](#appendix--upstream-contributions)
- [Sponsors](#sponsors)

---

## Quick install

The path that works on Windows 11 (Chrome 148, Node 22, Claude Code 2.1.x):

```powershell
# 1. Install the bridge npm package globally
npm install -g mcp-chrome-bridge

# 2. Download the extension from hangwin's releases
#    https://github.com/hangwin/mcp-chrome/releases
#    Extract to a stable folder (NOT in Downloads — Chrome warns daily about unpacked extensions from temp paths)
#    Example: D:\tools\chrome-extensions\mcp-chrome\

# 3. Chrome -> chrome://extensions -> Developer mode ON -> Load unpacked -> select the folder
#    Note the extension ID (should be hbdgbgagpkpjffpklnamcljpakneikee if the manifest has the `key` field set)

# 4. Click the extension icon -> Connect
#    Bridge process auto-spawns via Native Messaging · listens on 127.0.0.1:12306

# 5. Add the MCP entry to your client config
#    For Claude Code: ~/.claude.json (or whatever CLAUDE_CONFIG_DIR points to)
#       "chrome-mcp": { "type": "http", "url": "http://127.0.0.1:12306/mcp" }

# 6. Restart Claude CLI · tools should appear under mcp__chrome-mcp__*
```

Verify with: `mcp-chrome-bridge doctor` (returns OK once the extension is Connected).

---

## Diagnose: which gotcha are you hitting?

| Symptom | Likely gotcha |
|---|---|
| Tried CDP attach mode (`--remote-debugging-port=9222`) · port never opens · `DevToolsActivePort` file never appears | [#1](#gotcha-1--chrome-136-silently-drops---remote-debugging-port-on-the-default-profile) |
| Extension popup says "Connected" but Claude CLI reports `chrome-mcp` as failed/dead at startup · tool calls return "MCP server not available" | [#2](#gotcha-2--mcp-boot-has-no-auto-retry--install-the-bridge-before-claude-cli-starts) |
| Extension and bridge both run · handshake fails silently · `mcp-chrome-bridge doctor` warns about version mismatch | [#3](#gotcha-3--bridge-and-extension-versions-must-match) |
| `chrome-mcp` tools work *until* you open a tab where Anthropic's Claude for Chrome extension is active · then that tab returns "Cannot attach debugger" or silently no-ops | [#4](#gotcha-4--claude-for-chrome-and-chrome-mcp-fight-over-chromedebugger-per-tab) |
| Open a second Claude Code session · the first one's `chrome-mcp` tools stop responding · every context switch needs Disconnect/Connect on the extension popup | [#5](#gotcha-5--multi-session-orphaning--singleton-mcp-server-reassigns-transport) |
| Installed extension in multiple Chrome profiles · only one profile's tools work · the others show "Connected" but fail | [#6](#gotcha-6--multi-profile-port-collision--approach-b-workaround) |

---

## Gotcha 1 — Chrome 136+ silently drops `--remote-debugging-port` on the default profile

### Symptom

You're trying to drive your real Chrome (the one with your logins) via Chrome DevTools Protocol — adding `--remote-debugging-port=9222` to your Chrome shortcut so `chrome-devtools-mcp --browser-url=http://127.0.0.1:9222` can attach. The Chrome process command line contains the flag, but:

- `Get-NetTCPConnection -LocalPort 9222 -State Listen` returns empty
- `%LOCALAPPDATA%\Google\Chrome\User Data\DevToolsActivePort` never gets created
- Direct connect to `http://127.0.0.1:9222/json` fails

### Root cause

Chrome 136+ refuses to expose the debug port when `--user-data-dir` resolves to the default profile location. This was a deliberate Chromium security change (~Q1 2024) to prevent credential theft via an attacker's local process spamming `/json/version` against your logged-in browser. Even though the flag is *parsed*, the listener is *not started* when the data-dir matches default.

Confirmed on Chrome 148 (verified 2026-05-17).

### Fix · don't fight Chrome — pivot to the extension model

The clean fix is to stop using CDP attach mode entirely and use `hangwin/mcp-chrome` instead. It uses [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) — a different transport that Chrome explicitly trusts because the bridge process is registered under HKCU and the extension manifest lists `nativeMessaging` permission. No debug port, no security tradeoff.

If you still need CDP attach mode for a specific tool that can't speak MCP:

```
# Workaround: explicit user-data-dir (NOT default · use a separate Chrome profile dir)
"chrome.exe" --remote-debugging-port=9222 --user-data-dir="D:\chrome-cdp-profile"
```

This works because the security rule only applies to the *default* profile dir. But you lose your logged-in sessions — defeating the point. The extension model wins.

---

## Gotcha 2 — MCP boot has no auto-retry · install the bridge BEFORE Claude CLI starts

### Symptom

Extension popup says "Connected" (green badge). `mcp-chrome-bridge doctor` reports OK. But Claude Code reports `chrome-mcp` as failed in the MCP list, and tool calls return "MCP server not available". Restarting the bridge doesn't help.

### Root cause

Claude CLI does one MCP handshake at boot. If the bridge isn't ready exactly when the CLI fires its HTTP request to `127.0.0.1:12306/mcp`, the CLI marks the server permanently dead for that session lifetime. No auto-retry. No backoff. The bridge can come up 100ms later — the CLI doesn't notice.

This is upstream MCP client behavior, not chrome-mcp specific. But chrome-mcp's bridge is lazy-launched via Native Messaging — it only spawns when the extension calls `chrome.runtime.connectNative()`. Race condition during CLI startup is easy to trigger.

### Fix

Boot order matters:

```powershell
# 1. Start Chrome FIRST
# 2. Click the chrome-mcp extension icon -> Connect -> wait for "Connected" badge
# 3. Verify the bridge is listening:
Get-NetTCPConnection -LocalPort 12306 -State Listen   # should show 1 entry
# 4. THEN launch Claude Code
claude   # or your wrapper
```

If you skip step 3 and the CLI starts before the bridge is bound, `/exit` and restart. There's no in-session recovery.

`/mcp reconnect chrome-mcp` will revive the connection IF the server was loaded at boot and just dropped. It will NOT load new MCP entries that you added to `.claude.json` mid-session — those require a full process restart.

---

## Gotcha 3 — Bridge and extension versions must match

### Symptom

Both processes appear healthy individually. The bridge is listening on 12306. The extension popup is green. But MCP tool calls return cryptic errors like "Invalid MCP request" or hang indefinitely.

### Root cause

The npm `mcp-chrome-bridge` package and the Chrome extension speak a Native Messaging protocol whose message shape changes between minor versions. Mixing extension v1.0.x with bridge v1.1.x (or vice versa) sometimes works for `get_windows_and_tabs` but breaks `chrome_get_web_content` and other tools that use newer message types.

### Fix

Pin both to the same release. The extension version is whatever you downloaded; the bridge version is `mcp-chrome-bridge --version` (or `npm list -g mcp-chrome-bridge`).

```powershell
# Check both
npm list -g mcp-chrome-bridge   # bridge version
# Extension: chrome://extensions -> Chrome MCP Server card -> version line under name
```

If they don't match, prefer upgrading both to the latest tagged release on [hangwin/mcp-chrome/releases](https://github.com/hangwin/mcp-chrome/releases). The bridge installs via npm; the extension is unpacked load — replace the folder contents and click "Reload" on the extension card.

After upgrade: Disconnect/Connect on the popup, then `/exit` + restart Claude CLI (because of Gotcha 2).

---

## Gotcha 4 — Claude for Chrome and chrome-mcp fight over `chrome.debugger` per tab

### Symptom

`chrome-mcp` works fine on most tabs. But certain tabs — typically ones you've recently asked Anthropic's official Claude for Chrome extension to look at — return "Cannot attach debugger" on `chrome_get_web_content` / `chrome_screenshot`, or silently no-op. The bridge is fine, the extension popup is green; only one specific tab is broken.

### Root cause

Both extensions use the [`chrome.debugger` API](https://developer.chrome.com/docs/extensions/reference/api/debugger) to read DOM, take screenshots, click elements. Chrome enforces **one debugger attachment per tab at a time**. Whichever extension attaches first wins; the second gets `Cannot attach to the target with an attached client`.

The chrome-mcp extension popup shows "Connected" because the *bridge ↔ extension* native messaging handshake succeeded. The per-tab debugger collision is invisible to the popup state — you have to know to look.

This is distinct from the [documented Claude Desktop ↔ Claude Code conflict](https://github.com/anthropics/claude-code/issues/20546) where two Anthropic products register the *same* native messaging host name. That's a host-level clash. This one is two *different* extensions (different IDs, different vendors) fighting over a *per-tab* Chrome API.

### Fix

Pick one of:

| Option | Trade-off |
|---|---|
| Disable Claude for Chrome on tabs you'll drive via chrome-mcp | Easiest · lose Claude for Chrome on those tabs |
| Use a dedicated Chrome profile for chrome-mcp work (no Claude for Chrome installed in that profile) | Cleanest separation · pairs naturally with [Gotcha #6](#gotcha-6--multi-profile-port-collision--approach-b-workaround) |
| Disable Claude for Chrome globally during chrome-mcp sessions | Heavy-handed · works if you don't need both at once |
| Open the target page in a new tab AFTER chrome-mcp attaches first | Race-condition fragile · not recommended |

There's no Chrome-level fix — the one-debugger-per-tab rule is the API contract.

---

## Gotcha 5 — Multi-session orphaning · singleton MCP Server reassigns transport

### Symptom

You open a second Claude Code session (different terminal, same machine). The second session's `chrome-mcp` works. But the first session's `chrome-mcp` tool calls now hang or return errors. Disconnect/Connect on the extension popup brings the second session back; the cycle repeats every context switch.

### Root cause

I traced this through the bridge source. The HTTP server's `transportsMap` already routes incoming requests by `mcp-session-id` header — multi-session capable at the routing layer. But every new MCP `initialize` request calls `getMcpServer().connect(transport)` on a **singleton** MCP Server instance:

```ts
// app/native-server/src/mcp/mcp-server.ts
export let mcpServer: Server | null = null;
export const getMcpServer = () => {
  if (mcpServer) return mcpServer;   // singleton — same instance for every session
  mcpServer = new Server({...});
  setupTools(mcpServer);
  return mcpServer;
};
```

```ts
// server/index.ts, MCP POST init branch
await getMcpServer().connect(transport);   // <-- second call replaces _transport
```

The `@modelcontextprotocol/sdk` `Server.connect(transport)` assigns `this._transport = transport`, replacing whatever was there. So the second client's `initialize` orphans the first client's transport: requests still arrive at session 1's transport object, but the underlying SDK server writes responses to session 2's transport (which by then may have closed). Session 1 hangs.

### Fix (upstream PR pending) · or install patched fork locally

The fix is small — replace the singleton with a factory:

```ts
// mcp/mcp-server.ts
export const createMcpServer = () => {
  const server = new Server({...});
  setupTools(server);
  return server;
};
```

```ts
// server/index.ts, in both /mcp POST init and SSE branches
await createMcpServer().connect(transport);
```

Each session gets its own Server with its own transport binding. `setupTools` is per-instance pure. The extension-side native messaging pipe already routes by `requestId` UUIDs, so concurrency at the per-tab boundary stays correct.

**I filed this as [Issue #345](https://github.com/hangwin/mcp-chrome/issues/345) and put up [PR #346](https://github.com/hangwin/mcp-chrome/pull/346) with end-to-end verification.** If/when it merges, just `npm install -g mcp-chrome-bridge@latest`.

**Until then**, install the patched fork:

```powershell
git clone https://github.com/MankhongGarden/mcp-chrome.git
cd mcp-chrome
git checkout fix/multi-session-mcp-server
pnpm install --filter mcp-chrome-bridge... --ignore-scripts
pnpm --filter chrome-mcp-shared build
cd app/native-server
pnpm build
npm install -g .   # global mcp-chrome-bridge becomes a junction to your local clone
# In Chrome: Disconnect -> Connect on the extension popup
# Restart Claude CLI to re-establish MCP sessions
```

Revert at any time: `npm install -g mcp-chrome-bridge@latest` (removes the junction, installs stock).

After the fix is active, two Claude Code sessions can both call `chrome-mcp` tools without orphaning. Verified with direct HTTP POST simulating a second MCP client mid-call — session 1's tools keep responding correctly.

---

## Gotcha 6 — Multi-profile port collision · Approach B workaround

### Symptom

You want `chrome-mcp` available in multiple Chrome profiles (work, personal, per-project sandbox). You install the extension in each. Only one profile's tools actually work. The others show "Connected" but every tool call fails.

### Root cause

Chrome Native Messaging spec: `chrome.runtime.connectNative()` spawns a **new bridge process per profile**. So N profiles → N bridge processes. All N processes try to bind `127.0.0.1:12306` (the default). First wins; the rest silently fail their HTTP server bind, but the *extension ↔ native host* handshake succeeded so the popup still shows green.

### Fix (Approach B · workaround until upstream lands a proper solution)

Give each profile a unique port + matching MCP entry in your client. Below is a 5-profile setup. Adapt to however many profiles you have.

**1. Plan the mapping:**

| Port | Chrome profile slot | MCP entry name |
|---|---|---|
| 12306 | Profile A (e.g. main dev) | `chrome-mcp` (default) |
| 12307 | Profile B | `chrome-mcp-B` |
| 12308 | Profile C | `chrome-mcp-C` |
| 12309 | Profile D | `chrome-mcp-D` |
| 12310 | Profile E | `chrome-mcp-E` |

**2. In each profile**, install the extension once, then open the extension's options / popup and set the bridge port (the extension stores this in `chrome.storage.local` under `nativeServerPort`). Click Connect — the bridge for that profile binds the unique port.

**3. Add the matching MCP entries to your client config.** For Claude Code (`~/.claude.json` or `$CLAUDE_CONFIG_DIR/.claude.json`):

```json
{
  "mcpServers": {
    "chrome-mcp":   { "type": "http", "url": "http://127.0.0.1:12306/mcp" },
    "chrome-mcp-B": { "type": "http", "url": "http://127.0.0.1:12307/mcp" },
    "chrome-mcp-C": { "type": "http", "url": "http://127.0.0.1:12308/mcp" },
    "chrome-mcp-D": { "type": "http", "url": "http://127.0.0.1:12309/mcp" },
    "chrome-mcp-E": { "type": "http", "url": "http://127.0.0.1:12310/mcp" }
  }
}
```

A PowerShell helper in `scripts/add-chrome-mcp-profiles.ps1` does the JSON edit idempotently with auto-backup. Run it via your client's shell-passthrough if your AI agent can't self-modify its own config (Claude Code has a self-modification safety block that prevents the agent from writing `.claude.json` directly — you the user must invoke the script).

**4. Restart your client.** New MCP entries load at boot, not on reconnect.

**5. Verify.** From inside the client, call `get_windows_and_tabs` from each prefix — each should return a *different* tab set (matching that profile's Chrome instance).

### Tool prefix selection rule

Pick prefix based on which Chrome profile owns the relevant accounts/cookies/sessions for the task. If you have an AI agent making tool calls, keep a mapping in its persistent memory (a markdown file the agent loads at session start) and put a short selection rule there:

> "Use `chrome-mcp-{X}` for tasks involving project X's accounts. Default to `chrome-mcp` for the most-active profile. Never mix prefixes within one task — that drives multiple Chrome windows simultaneously and state diverges."

### Long-term: profile-aware bridge proposal

The cleaner architecture is a single bridge process that multiplexes across profiles, with the client selecting a profile via header or session metadata. I filed this as [Issue #347](https://github.com/hangwin/mcp-chrome/issues/347) — open to maintainer's preference between two candidate architectures. If/when something like it lands, Approach B's per-profile MCP entries collapse to a single entry with a profile selector.

---

## Appendix · Upstream contributions

If you want the diagnostic walkthrough rather than the answers, the issue + PR thread tells the full story:

- [Issue #345](https://github.com/hangwin/mcp-chrome/issues/345) — initial report with source-level analysis (the singleton-and-replaced-transport hypothesis)
- [PR #346](https://github.com/hangwin/mcp-chrome/pull/346) — 14 LoC fix + unit tests proving identity (factory returns distinct instances) and behavior (two transports route correctly)
- [Issue #347](https://github.com/hangwin/mcp-chrome/issues/347) — follow-up feature request for profile-aware multi-profile support

The PR description includes a verification comment showing two real MCP clients (one Claude Code session, one direct HTTP POST simulating a second client) operating concurrently against a single bridge with no orphaning. Reproducible if you check out the branch and install with the steps in [Gotcha #5](#gotcha-5--multi-session-orphaning--singleton-mcp-server-reassigns-transport).

---

## Sponsors

This guide is free and the patches above are upstream-PR'd. If it saved you the half-day I spent debugging, consider:

- ⭐ Star this repo so others find it (GitHub search ranks by stars)
- ⭐ Star [`hangwin/mcp-chrome`](https://github.com/hangwin/mcp-chrome) — the actual project doing the heavy lifting
- 💛 [GitHub Sponsors](https://github.com/sponsors/MankhongGarden) — sustains weekend OSS work like this

If you hit a Windows install pain not in this guide, [open an issue](https://github.com/MankhongGarden/chrome-mcp-windows-survival-guide/issues) — I'd rather add a Gotcha 7 than have you debug alone.

---

## License

MIT — see [LICENSE](LICENSE). Use anything here however you want.

The scripts in `scripts/` are also MIT and have no external dependencies beyond what `hangwin/mcp-chrome` itself requires (Node 22+, PowerShell 7+ recommended, Chrome 136+).
