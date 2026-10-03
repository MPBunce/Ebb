# Ebb App Store assets

## Icon (`icon/`)
- `AppIcon-1024.png`: App Store icon, 1024 × 1024, no transparency. App Store Connect uses the icon from the uploaded build, so this copy is for reference, the website and marketing.
- `AppIcon-1024-Dark.png`, `AppIcon-1024-Tinted.png`: the iOS dark and tinted variants.

## Screenshots (`screenshots/`)
Three sets with the same images:

- `6.5-inch/`: 1284 × 2778. Use this if App Store Connect asks for 1242 × 2688 or 1284 × 2778.
- `6.9-inch/`: 1320 × 2868, for the 6.9" display slot.
- `13-inch-ipad/`: 2064 × 2752, for the 13" iPad display slot (taken on an iPad Pro 13-inch simulator). App Store Connect scales these down for smaller iPads.

App Store Connect scales these down for smaller iPhones. Upload in this order:

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
xcrun simctl io booted screenshot assets/screenshots/6.9-inch/02-home.png
```

Make the 6.5" copies with `swift assets/resize.swift assets/screenshots/6.9-inch assets/screenshots/6.5-inch` (scales to 1284 wide and trims a few pixels top and bottom).

`-hasOnboarded YES` skips onboarding; leave it off to capture the welcome screen. In development builds, `-EbbScreen widgets|apps|colors|help|settings|plus` opens that screen directly, `-ebbPlusActive '<false/>'` shows Ebb Plus as not bought (with its buy button), and `-backgroundHex '#000000' -textHex '#F2F2F2'` forces the Midnight colors.
