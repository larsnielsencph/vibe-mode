# VibeMode

A native macOS menu bar app for Apple Silicon MacBook Air (macOS 14+). It has two modes:

- **Normal** — stock macOS. Closing the lid sleeps the Mac. Switching back to Normal restores the original `SleepDisabled` value and drops every keep-awake hold.
- **Vibe** — the Mac stays awake with the lid closed, Wi-Fi / iPhone Personal Hotspot stays up, and non-coding apps are asked to Quit so a closed laptop in a bag keeps agents, terminals, and dev servers alive without hauling Safari, Slack, and Mail along for the ride.

Danish step-by-step install from GitHub: **[INSTALL-DA.md](INSTALL-DA.md)**.

Private repo: [github.com/larsnielsencph/vibe-mode](https://github.com/larsnielsencph/vibe-mode). This is a local Xcode app, not a website and not on the App Store.

## Closed-lid wake: what we chose

Idle-sleep tools (`caffeinate`, KeepingYouAwake, Amphetamine’s assertions) **do not** keep an Apple Silicon MacBook awake when the lid closes. Lid-close sleep is a separate hardware trigger.

| Approach | Lid closed, no dummy HDMI | Root? | Survives reboot? | Notes |
|---|---|---|---|---|
| IOPM assertions / `caffeinate` | No | No | No | Only idle sleep |
| IOKit `kPMSetClamshellSleepState` (selector 12 on `IOPMrootDomain`) | Often yes | No | No | Undocumented SPI; macOS can clear it on power-source changes (charger / hotspot) |
| `sudo pmset -a disablesleep 1` (`SleepDisabled`) | Yes, most reliable | Yes | **Yes — until you set it back to 0** | The flag this app is built around |
| SMAppService privileged helper | Same as pmset | One-time approval | Helper lives in `/Library/LaunchDaemons` | Apple’s long-term pattern; unreliable for an ad-hoc signed app you build in Xcode |
| HDMI dummy / official clamshell mode | Yes | No | N/A | Needs an external display (and usually AC). Useless in a bag |

**VibeMode uses a layered hold:**

1. **Primary (admin):** `pmset -a disablesleep 1`. This is the reliable lid-close override on current macOS. The first time, macOS shows the standard administrator password dialog (`osascript` → `with administrator privileges`). Nothing stores your password.
2. **Supplement / fallback (no admin):** IOKit clamshell selector 12 + `PreventUserIdleSystemSleep` assertion + CoreWLAN `setPower(true)` so Wi-Fi is not powered down. Re-applied every few seconds because hotspot / power flaps can drop the IOKit flag.
3. **Privilege after the first time:** optional **tight sudoers rule** that allows only  
   `pmset -a disablesleep 0` and `pmset -a disablesleep 1`  
   plus a **boot LaunchDaemon** that always sets `disablesleep 0` at startup.

We did **not** ship an SMAppService LaunchDaemon helper. That is the “correct” Apple API, but it expects a stable Developer ID signature and user approval under System Settings → Login Items. An app Lars builds with ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) typically cannot register that daemon. A visudo-checked sudoers snippet is the workable, auditable substitute on a personal machine.

Idle sleep is *not* rewritten in Energy Saver. An IOPM assertion covers it, so Normal mode does not have to replay a pile of `pmset` keys. The only persistent system setting Vibe changes is `SleepDisabled`, and Normal restores the snapshot taken before Vibe started.

## Safety: the Mac must always be able to sleep again

`SleepDisabled` is process-independent and **persists across reboot**. That is the dangerous part of `pmset`. VibeMode counters it several ways:

- Snapshot the flag before enabling Vibe; Normal / Quit restore it.
- A dirty-session flag in `~/Library/Application Support/VibeMode`. On next launch the app restores Normal (and will prompt for admin if sudoers is not installed).
- Optional boot LaunchDaemon (`dk.lars.vibemode.safetynet`) that runs `pmset -a disablesleep 0` at load — so a crash + reboot cannot leave the machine stuck awake even if VibeMode never starts.
- Auto-revert to Normal at a configurable battery floor (default **15%**) with a notification.
- Optional heat warning (`ProcessInfo.thermalState`) and auto-revert on **critical** thermal pressure.
- Menu bar icon: `moon.zzz` = Normal, `bolt.horizontal.fill` = Vibe.

Manual undo, any time, in Terminal:

```bash
sudo pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled
```

## Allowlist quitting

On the first Vibe switch (and later, unless you tick “Don’t ask again”) a confirmation lists the apps that will be sent a **normal Quit** (`NSRunningApplication.terminate()`, the same as ⌘Q — they can save). Never `kill -9`, never `forceTerminate`.

Left alone:

- This app, Finder, Dock, loginwindow, and anything under `/System/Library`
- Default allowlist: **ChatGPT/Codex**, **Cursor**, **Claude**, **Grok Bot**, **Gemini**, **Perplexity**, **Terminal**, **iTerm2**, **Warp**, **Ghostty**
- Any process **listening on a local TCP port** (dev servers, etc.)

Edit the list in **Settings → Allowlist** (pick an `.app` from `/Applications`).

## Menu

- Status line: battery % and which apps / listeners are being kept
- Vibe / Normal
- Settings (launch at login, battery floor, heat, allowlist, password-free helper)
- Quit VibeMode (restores Normal)

## Requirements

- MacBook Air with Apple Silicon, macOS 14 or later
- Xcode 15 or 16 from the Mac App Store
- Admin password once for `SleepDisabled` (or the optional sudoers install)

## Build & run

See [INSTALL-DA.md](INSTALL-DA.md) (Danish, written for Lars) or:

```bash
git clone https://github.com/larsnielsencph/vibe-mode.git
cd vibe-mode
./scripts/install-local.sh
```

That builds a Release app with the rocket icon and copies it to `/Applications/VibeMode.app`. Look in the menu bar (no Dock icon).

Alternatively:

1. Open `VibeMode.xcodeproj` in Xcode.
2. Signing: the project ships **ad-hoc** (`Sign to Run Locally` / `CODE_SIGN_IDENTITY = "-"`). That is enough to run on the Mac that built it. You can switch to your Personal Team if Xcode complains.
3. Product → Run (⌘R). A moon icon appears in the menu bar; there is no Dock icon.
4. Click **Vibe mode**. If Wi-Fi/hotspot is missing, cancel and join it first. Confirm the quit list. Enter an admin password when macOS asks.
5. Optional: Settings → Power → **Install password-free toggle + boot safety net**.
6. Optional: enable **Launch VibeMode at login**.

## Limitations

- A closed Mac in a poorly ventilated bag **will heat up**. Light agent work is usually fine; local LLM / GPU jobs are not. Heat warning + battery revert are guards, not a license to cook the machine.
- iPhone hotspot: join the hotspot **before** closing the lid. Vibe keeps Wi-Fi powered; it cannot invent a network that was never associated.
- Apps can refuse Quit if they have unsaved documents and show their own save sheet. VibeMode will not force-quit them.
- The IOKit selector is private SPI. Apple can change it. That is why `SleepDisabled` is the primary hold.
- Firmware thermal protection can still sleep or throttle the machine; VibeMode cannot override that.
- `kill -9` on VibeMode while Vibe is on leaves `SleepDisabled` until: next VibeMode launch, the boot safety net, or the manual `pmset` command above. Install the helper.
- Not sandboxed (required to Quit other apps and to talk to `pmset`). Not for the Mac App Store.

## Project layout

```
VibeMode.xcodeproj/     Xcode project (arm64, macOS 14)
VibeMode/               Swift sources, Info.plist, entitlements
scripts/                install-local.sh, emergency restore, optional sudoers
INSTALL-DA.md           Danish GitHub install guide
LICENSE                 MIT (Lars Nielsen)
```

## License

[MIT](LICENSE) © 2026 Lars Nielsen

