# Ebb App Store assets

## Icon (`icon/`)
- `AppIcon-1024.png`: App Store icon, 1024 × 1024, no transparency. App Store Connect uses the icon from the uploaded build, so this copy is for reference, the website and marketing.
- `AppIcon-1024-Dark.png`, `AppIcon-1024-Tinted.png`: the iOS dark and tinted variants.

## Screenshots (`screenshots/`)
iPhone 6.9" (1320 × 2868), the size App Store Connect requires; it scales them down for smaller iPhones. Upload in this order:

1. `01-welcome.png`: welcome and what Ebb does
2. `02-home.png`: main screen with the widget preview
3. `03-widgets.png`: app widgets and style
4. `04-settings.png`: settings overview
5. `05-plus.png`: Ebb Plus
6. `06-colors.png`: colors and matching wallpaper

App Store Connect accepts up to 10 screenshots per size. Ebb's strongest screenshot would be a real Home Screen with its widgets and matching wallpaper. That's best taken on a real iPhone (side button + volume up), then cropped to 1320 × 2868 or uploaded at its native size if it's a 6.9" phone.

## Regenerating
On the iPhone 17 Pro Max simulator:

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl launch booted mpbunce.Ebb -hasOnboarded YES
xcrun simctl io booted screenshot assets/screenshots/02-home.png
```

`-hasOnboarded YES` skips onboarding; leave it off to capture the welcome screen.
