# EVESup

A macOS counterpart to [EVE-O Preview](https://github.com/Proopai/eve-o-preview) for the native EVE Online Mac client. It runs in the menu bar and gives you:

- **Cycle groups**: put characters into groups, give each group a "next" and a "previous" key, and step through them in your chosen order.
- **Character keys**: one key that jumps straight to a specific character.
- **Live previews**: a small, always-on-top thumbnail of every EVE client. Click one to switch to it.
- **Settings sync**: copy one character's or account's EVE settings over the others in the same profile, with an automatic backup.

EVESup only shows previews and brings EVE windows to the front. It never sends keystrokes or mouse clicks to EVE and doesn't touch the client. That is the same kind of tool CCP has said is fine for EVE-O Preview: one key press, one window switch.

## Install

Needs macOS 14 or later, on Apple Silicon or Intel.

1. Download `EVESup-<version>.dmg` from the [latest release](https://github.com/xingyueguji/eve-mac-preview/releases/latest), open it, and drag **EVESup** into **Applications**.
2. Open it. EVESup isn't signed by a registered Apple developer, so macOS blocks the first launch. Click **Done**, then go to System Settings → Privacy & Security, scroll down, and click **Open Anyway** next to EVESup. Or run `xattr -dr com.apple.quarantine /Applications/EVESup.app` in Terminal.
3. EVESup appears as an icon in the menu bar (no Dock icon). Click it for the client list and **Settings…**.

## Build from source

Needs Xcode (or the Swift toolchain).

```bash
./scripts/build.sh
```

```bash
open build/EVESup.app
```

To make a DMG for sharing, which contains a universal app plus a read-me, run:

```bash
./scripts/package.sh
```

That writes `dist/EVESup-<version>.dmg`. The version comes from `Resources/EVESup-Info.plist`. To redraw the icon, see the top of `scripts/make-icon.swift`.

### Permissions

On first launch, Settings opens on **General**:

1. **Screen Recording** (required). macOS only shares other apps' window titles, which hold the character name, and window images with apps that have it. Click **Allow…**, turn EVESup on in System Settings, then click **Relaunch EVESup**.
2. **Accessibility** (optional). A backup way to bring a client forward, and lets EVESup restore minimized clients.

The build is signed locally (ad-hoc), so macOS ties the permission to that exact build. **After rebuilding, remove EVESup from the Screen Recording list in System Settings and allow it again.** macOS may also ask now and then whether EVESup may keep recording the screen; choose Allow.

### Recommended EVE setup

Set each client's **Window Mode** to **Fixed Window** in EVE's Display settings. That window has no title bar or border. macOS doesn't let another app remove a window's frame, so EVE-O's "hide caption bar" option can't exist here, but Fixed Window gives the same result.

## Cycle groups

Settings → **Cycle Groups**:

1. Click **+** to add a group and give it a name (e.g. "DPS", "Logi").
2. Click the **Next client** button and press a key. Do the same for **Previous client**. Esc cancels, ⌫ clears. F13–F20 are good choices if you bind them to mouse or keypad buttons.
3. Add characters with **Add Character**, **Add All Logged-In**, or by typing a name. Use the arrows to set the order.

Next goes down the list and wraps around, and previous goes up. Characters who aren't logged in are skipped. A group with no characters cycles through every open client alphabetically, which is handy at character select. If you're not on a client in the group, next starts at the top and previous at the bottom.

- **Also work while ⌃ ⌥ ⇧ are held** registers the key with every modifier combination, so it still fires while you hold Ctrl to lock targets.
- ⇧-click a preview to skip that client in all groups until you ⇧-click it again.
- The list on the left shows each group's keys at a glance, and a ⚠︎ appears if a key is taken by another group, another app, or macOS.
- Keys used here are captured by EVESup and never reach EVE, so don't pick keys you use in game.

Names in **Add Character** come from clients you've had logged in and from your EVE settings folder (looked up through CCP's public ESI API).

## Previews

| Mouse | Effect |
| --- | --- |
| Click | Switch to that client |
| ⇧-click | Skip that client when cycling |
| Drag | Move the preview |
| Drag the bottom-right corner | Resize it |
| Right-click (or ⌃-click) | Menu: hide preview, lock positions, settings |

Settings → **Previews** has:

- **Previews:** frame rate, and showing them on every desktop.
- **Size:** width and height, applied to every preview.
- **Position:** **Snap to grid** with its own grid width and height (default 20 pt). Dragging moves a preview in grid steps and corner-resizing snaps to whole cells, so previews line up without fine adjustment. **Align All Previews to Grid** tidies up existing ones, **Rearrange Previews** lines them up in rows, and you can lock positions.
- **Appearance:** borderless previews (just the picture), opacity when not in front, and the highlight on the client you're on.
- **Character name:** font, size, bold, color, and how dark the box behind the name is, with a live sample. These apply to every preview.
- **Behavior:** hide the client you're on, or show previews only while EVE is in front.

Positions are saved per character.

## Settings sync

Settings → **Settings Sync** works on one EVE settings profile folder, such as `~/Library/Application Support/CCP/EVE/<server folder>/settings_Default`:

- **Characters (core_char files):** per-character UI, such as window layout, overview and chat windows.
- **Accounts (core_user files):** account-wide settings, such as keyboard shortcuts.

Pick the **Copy from** character and/or account, tick the targets (all others by default), and click **Back Up & Sync…**.

- Every sync first copies all `core_*` files of the profile to `~/Library/Application Support/EVESup/Backups/<server>-<profile>/<timestamp>/`. **Restore Backup** puts a backup back, and backs up the current files first.
- Syncing is disabled while EVE clients are running. EVE writes these files when a character logs out, which would undo the sync.
- Account files only have numbers. Give them nicknames in the list. "saved with <character>" means the account file was written at the same moment as that character's file, which usually means the character is on that account.

## Files

| What | Where |
| --- | --- |
| EVESup settings (hand-editable JSON) | `~/Library/Application Support/EVESup/config.json` |
| Log (switches, failures) | `~/Library/Logs/EVESup/EVESup.log` |
| Settings-sync backups | `~/Library/Application Support/EVESup/Backups/` |

If a key press doesn't switch clients, the log says which client EVESup picked and whether the switch was confirmed.

## Development

```bash
swift test
```

```bash
./scripts/build.sh --mock
```

`--mock` also builds `MockEVEClient.app`, a fake client window titled `EVE - <name>` for testing without the game: `open -n build/MockEVEClient.app --args Alpha`. To test with it, add `com.evesup.MockEVEClient` under General → Also treat as EVE.

Code layout:

- `Sources/EVESupCore`: config model, cycle logic, hotkey model, EVE settings files. No UI, covered by the tests.
- `Sources/EVESup`: the app. Client tracking (`ClientMonitor`), Carbon hotkeys (`HotkeyCenter`), switching (`WindowActivator`), previews with ScreenCaptureKit (`Previews/`), SwiftUI settings (`Settings/`).

## Legal

EVE Online and the EVE logo are trademarks of CCP hf. EVESup is not affiliated with or endorsed by CCP. Use it within the EVE Online EULA and Terms of Service: EVESup only previews and switches windows and never broadcasts input.
