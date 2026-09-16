# Farmboard

![Farmboard](docs/images/Farmboard-Icon-400.png)

**Farmboard** is a lightweight farming goal tracker for **World of Warcraft: Midnight**.

Create multiple customizable farming boards, drag items into tracking slots, set collection goals, and monitor your progress directly in-game.

## Features

- Multiple independent Farmboards
- Drag & drop item tracking
- Custom farming goals from **1 to 9999**
- Live counts for bags, character bank and Warband/Account Bank
- Midnight crafting/reagent quality markers
- Free slot count from **1 to 24** per board
- Horizontal and vertical layouts
- Movable and lockable boards
- Rename, duplicate, show/hide and delete boards
- Minimap button with global board management
- Goal-complete marker, custom sound and centered **“- Ziel Erreicht! -”** notification
- Persistent settings through SavedVariables
- No external libraries required

## Screenshots

### Multiple Farmboards
![Horizontal Farmboards](docs/images/horizontal.png)

Track multiple farming goals at once with independent horizontal Farmboards.

### Vertical Layout
![Vertical Layout](docs/images/vertikal.png)

Switch any Farmboard between horizontal and compact vertical layouts.

### Board Settings
![Board Settings](docs/images/bar_menue.png)

Configure slots, goal notifications, names, duplication, locking and positioning for each Farmboard.

### Minimap Management
![Minimap Management](docs/images/minimap_menue.png)

Create and manage your Farmboards quickly through the minimap button.

## How It Works

1. Drag an item from your bags onto a free Farmboard slot.
2. Right-click the occupied slot and enter your farming target.
3. Collect the item and watch your progress update automatically.
4. When the target is reached, Farmboard can play a sound and show a completion notification.

## Controls

- **Drag item onto slot** — Add or replace an item
- **Right-click occupied slot** — Set target amount
- **Shift + Right-click occupied slot** — Remove item
- **Drag Farmboard** — Move board while unlocked
- **Right-click Farmboard** — Open board-specific options
- **Left-click minimap button** — Show/hide all Farmboards
- **Right-click minimap button** — Open global Farmboard menu
- **Drag minimap button** — Reposition it around the minimap

## Slash Commands

```text
/farmboard or /fb  - Show / hide all Farmboards
/fb new            - Create a new Farmboard
/fb show           - Show all Farmboards
/fb hide           - Hide all Farmboards
/fb reset          - Reset all Farmboard positions
```

## Installation

Extract the `Farmboard` folder to:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

After updating, use `/reload` or restart World of Warcraft.

## Version

Current release: **v1.0.0**

## Author

**Loyftwa**
