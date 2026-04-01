# Tardy

A macOS menu bar app that takes over your screen to make sure you're never late to a meeting.

Tardy reads your calendar events directly from macOS Calendar.app and displays a full-screen alert before each event starts — a blurred overlay with a floating card showing the event name, countdown, and a one-click button to join the call.

<img width="1470" height="956" alt="Screenshot 2026-04-01 at 8 38 57 AM" src="https://github.com/user-attachments/assets/d1b3b1ac-e2f5-4496-bc1f-545386cb4fa6" />


## Features

- **Full-screen takeover alerts** — impossible to miss, with a frosted glass backdrop and countdown timer
- **One-click join** — automatically detects Zoom, Google Meet, Teams, Webex, and other conference links from your events and surfaces them as a button
- **Phone number detection** — if there's no video link, Tardy finds the dial-in number
- **Multiple calendar support** — works with any calendar configured in macOS Calendar.app (Google, iCloud, Outlook, Exchange)
- **Configurable timing** — alert 1 minute, 30 seconds, 15 seconds, or right at event time
- **Snooze** — dismiss now, get reminded again in 2 minutes
- **Alert sounds** — three bundled sounds (Crystal, Pulse, Deep Bell) with preview in settings
- **Auto-launch on login** — starts silently on boot, lives in your menu bar
- **Real-time updates** — picks up new/changed/deleted events immediately via EventKit change notifications, with a 5-minute safety poll

## Requirements

- macOS 14 (Sonoma) or later
- Calendar access permission

## Building from Source

```bash
git clone https://github.com/nikp29/tardy.git
cd tardy
swift build
swift run Tardy
```

On first launch, Tardy will ask for calendar access and open the settings window.

## Install via Homebrew

```bash
brew tap nikp29/tardy
brew install --cask tardy
```

> **Note:** Tardy is not notarized with Apple. On first launch, right-click the app and select "Open" to bypass Gatekeeper, or allow it in System Settings > Privacy & Security.

## How It Works

Tardy runs as a menu bar app with no dock icon. It fetches your events from the macOS calendar store on launch, subscribes to change notifications for real-time updates, and schedules a timer for each upcoming event. When a timer fires, it plays a sound and presents the full-screen alert.

The alert extracts conference information from your events using a priority fallback: video call URL > phone number > event notes. It checks `event.url`, `event.notes`, and `event.location` for known conference provider patterns.

All-day events and declined invitations are automatically filtered out.
