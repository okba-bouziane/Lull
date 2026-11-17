# Lull

A small menu bar app for macOS that shows what is slowing your Mac down and lets you quit it in one click.

- **Menu bar gauge.** It turns orange when memory is under pressure or an app has been hogging the CPU. It can also show CPU % or memory % next to the icon.
- **Apps grouped the way you think of them.** Chrome and its 25 helper processes appear as one row called "Google Chrome", like in Activity Monitor.
- **Three lists.** Top (whatever uses the most right now), Apps, and Background (agents, updaters and helpers that start at login). Click the CPU or Memory column to sort.
- **Quit from the row.** Hover a row and click ×, or right-click for Force Quit (it asks first), Never Quit and Show in Finder. Apps are asked to quit normally, so any app with unsaved work asks before closing. Parts of macOS are shown but can't be quit.
- **Free Up Memory.** Lists the apps you aren't using. Apps with no open windows are ticked for you. Background tools such as a VPN, cloud sync or battery manager are listed but never ticked for you. After quitting, it shows your memory use before and after.
- **Heavy-app alerts.** If an app stays above 100% CPU (one full core) for 3 minutes while you aren't using it, Lull shows a banner and sends a notification. You can change both numbers.
- **Quit that sticks.** Lull quits the process that owns the app first (Steam's main process, not one of its helpers). Background agents that launchd keeps alive are stopped through launchd (`launchctl bootout`), so they stay stopped until the next login. If an app ignores a normal quit, its row says "Didn't quit · try Force Quit".
- **Spots apps that restart themselves.** If something comes back right after you quit it, Lull says so and links to Login Items, where you can turn it off.
- **Opens at login** through macOS Login Items. Turn it off in Settings.

## Light on resources

- Reads process data straight from the kernel (`libproc`). It never runs `ps` or `top`. One pass over about 400 processes takes about 2 ms.
- While the panel is closed it checks every 10 seconds by default (5 s to 1 min in Settings). Timer tolerance lets macOS batch these wake-ups with other work, and the process list is kept out of the UI while nobody is looking.
- With the panel open it refreshes every 2 seconds.
- The app is a 1.3 MB native Swift and AppKit build that uses about 10–15 MB of memory.

Lull can only measure and quit your own processes. macOS keeps other users' and root processes private, so the Top list never offers to quit system parts.

## Install

1. Download `Lull-1.0.0.dmg` from [Releases](../../releases/latest). It needs macOS 14 or later on an Apple Silicon Mac.
2. Open the DMG and drag **Lull** to **Applications**.
3. Open Lull. It isn't notarized by Apple, so the first time macOS says it can't verify the developer. Go to **System Settings → Privacy & Security**, click **Open Anyway** next to Lull, and confirm.

The gauge then appears in the menu bar, and Lull opens at every login from then on.

## Build from source

Requires macOS 14+ and the Xcode command line tools.

```bash
./scripts/build-app.sh --install   # builds, copies to /Applications, starts it
./scripts/build-app.sh --dmg       # builds dist/Lull-<version>.dmg for a release
swift test                         # grouping, CPU and memory sampling tests
```

On first launch Lull adds itself to Login Items and asks to send notifications.

`Lull --snapshot out.png --view main|freeup|settings [--dark]` renders a screen with live data to a PNG without showing a window. It is used for testing.
`Lull --quit-test "<app name>" [--force]` runs the same quit as the × button and reports 12 s later whether the app stayed closed. `LULL_LAUNCHD_TEST=1 swift test` also runs a real launchd test with a throwaway keep-alive job.

## Layout

| Path | What |
|---|---|
| `Sources/LullCore/ProcessSampler.swift` | Per-process CPU and memory via `proc_pid_rusage`, cached identities |
| `Sources/LullCore/SystemStats.swift` | Whole-Mac CPU, memory used, swap and memory pressure |
| `Sources/LullCore/Grouping.swift` | Groups helpers under their app, tracks heavy apps, formatting |
| `Sources/Lull/Monitor.swift` | Sampling schedule, app kinds, alerts, quit actions |
| `Sources/Lull/AppDelegate.swift` | Menu bar item and panel |
| `Sources/Lull/Views/` | Main list, Free Up Memory, Settings |
