# Elu Tracker

A highly comprehensive and self-sufficient productivity, utility, and recruitment tracker designed specifically for ArcheAge Classic. This addon modernizes and heavily expands upon classic tracking capabilities to give players complete transparency over their daily activities.

**Packed with features:**
- **Trade Pack Profit Tracker** that allows you to pull weekly average prices or set your own manual prices.
- **Fishing Profit Tracker** and a **Fishing Spots Time Tracker**.
- **Fishing Tools** that display the required skill under the fish's HP bar, along with a dead fish timer tracking how much time is left before its loot expires.
- **Raid Management** featuring an Auto Raid system with Whitelist and Auto-Givelead, plus a "Quick Auto Raid" mode for fast open-world events.
- **Guild Check** to easily identify the guilds of both players and vessels (ships).
- **Range Finder** with fully customizable dynamic colors.
- **Crash Alert**, a high memory monitor that warns you when it's time to relog to prevent client crashes.
- **Regrade Log** to track server success and failure regrades.
- **Customizable Zeal Alert** that allows you to move and change size.
- **Everyday Tools** including a built-in Stopwatch and Trip Counter.
- **Quick Equip** gear-set swapper, letting you save and instantly re-equip full loadouts with one click.

## Acknowledgments & Credits
Elu Tracker is a standalone project heavily expanded from its original scope. While the overall addon has evolved independently, the Packs and Loss Regrade algorithms were originally inspired by and adapted from *Your Paystub* and *LossPorn*, created by **Michaelqt**. 

Huge thanks to Michaelqt for providing a great foundation for developing these specialized features.

## Tutorial & Usage (How to Use)
1. **Accessing the Main Interface:**  
A custom interactive button is injected directly into your main Inventory (Bag) window. Click the custom icon to toggle the main Elu Tracker control panel.

2. **Accessing the Auto Raid Manager:**  
The recruitment manager is injected directly into the native Raid window. You can access it instantly by pressing **Shift + R** (the default Raid UI keybind).

3. **Accessing the Regrade Log:**  
The regrade log can be opened in two different ways: by navigating to the **Misc** tab within the main Elu Tracker interface, or by opening the game menu (**ESC**) in **Addon Settings**.


## Features

### 1. Raid & Recruitment Manager (Elu Auto Invite & Quick Auto Invite)
*A massive overhaul of the native raid recruitment system, seamlessly integrated into the Raid Info window.*

#### Elu Auto Invite:
- **Whitelist:** Custom whitelist and blacklist (manage large lists of friends and foes. Blacklisted players are ignored completely. Includes a one-click "Add Raid" button to instantly whitelist your current raid members, and features easy export and import options), alongside an option to bypass whitelist requirements when receiving the keyword in private channels (e.g., guild and family chats).
- **Auto Givelead (x givelead):** Enables the "x givelead" command, allowing anyone in the raid to instantly claim leadership.
- **Floating Status Icon:** A draggable, clickable screen icon that visually tells you if recruitment is ON or OFF, and displays the active keyword so you never accidentally leave auto-invite running.

#### Quick Auto Invite: 
*A specialized, separate mode designed for fast invites during open-world events, featuring its own independent Fast Blacklist.*

### 2. Fishing Tracker & Enhancements
- **Catch & Profit Logging:** Tracks exact fish turn-ins and total gold generated. View your financial breakdown by Today's Profit, Yesterday's Profit, and Lifetime Total.
- **Dynamic Fishing Spot Tracker:** Bind a modifier key (Alt, Shift, or Ctrl), hover over a spot, and instantly open a persistent tracking toggle showing the spot's name and remaining time (supports up to 3 spots simultaneously).
- **Midnight Session Transfer:** Features a smart rollover mechanism. If your fishing session goes past midnight, manually transfer "Today's" earnings into "Yesterday's" profit with a single click.
- **Dead Fish Timers (Visual Overlay):** Automatically draws a visible 5-minute countdown timer directly floating over the bodies of dropped Large Fishes so you know exactly when they will despawn.
- **Skill Indicators (Visual Overlay):** Automatically detects what skill a hooked fish requires and displays the required skill icon directly above the fish in the 3D world.

### 3. Commerce Tracker (Packs)
*Calculates the value of pending packs, pulls weekly average prices for pack resources, and features an option to set manual prices of your choice.*

### 4. System Stability & Anti-Crash
- **Live RAM Monitor:** Displays a live memory tracker on-screen to monitor ArcheAge's RAM consumption.
- **Crash Preventer Warning:** Monitors RAM usage and pops an on-screen warning when it hits a critical threshold (e.g., 3200 MB or 96% of the 32-bit limit), so you know it's time to relog before a fatal crash happens. The actual client restart is manual — click the warning's "Crash NOW" button, or use the Crash Command below — it is never triggered automatically.
- **Crash Command:** Features a customizable chat command (default is `/crash`) that forcefully and instantly restarts the client.

### 5. Regrade Log 
*Tracks server success and failure regrades, and allows you to toggle whether failures are displayed in your System chat.*

### 6. Combat & Target Utilities
- **Range Meter:** A tiny, minimalist overlay that displays the exact distance (in meters) to your current target. It overrides all other game windows and addons natively so it never gets hidden behind bags or maps. You can customize colors for up to 3 different range thresholds and choose exactly where it anchors onto the enemy's health bar.
- **Guild Check:** Instantly displays the guild of your current target. Creates a customizable floating box at the top of the screen and also adds the guild name directly above the target's health bar.
- **Zeal Alert:** Pops a customizable visual alert on your screen the moment the Zeal buff activates.

### 7. Misc & Utility
- **Integrated Chronometer (Stopwatch):** A highly accurate, low-overhead live timer mapped into the user interface.
- **Trip Counter:** A persistent counter for your trade runs featuring anti-DC protection (your progress is safely cached and only resets if you click it). 

### 8. Quick Equip
*A gear-set swapper: save your currently equipped gear as a named preset, then re-equip the whole set with a single click. Disabled by default on a fresh install; enable it from the **Misc** tab's Tools section, and your choice is saved across reload/relog like every other Elu Tracker setting.*
- **One-Click Loadouts:** Save your current gear as a named preset and re-equip the entire set instantly, without dragging items one by one.
- **Ctrl + Click a Preset:** Opens a context menu with **Replace** (overwrite the preset with your currently equipped gear, same name), **Rename**, and **Delete**.
- **Shift + Drag to Reorder:** Hold Shift and drag a preset to change its position among the others.
- **Shift + Drag the Bar:** Hold Shift and drag empty space on the bar itself to reposition the whole Quick Equip window.