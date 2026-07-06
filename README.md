# EluTracker

A highly comprehensive and self-sufficient productivity, economy, and activity tracker designed specifically for ArcheAge Classic. This addon modernizes and heavily expands upon classic tracking capabilities to give players complete transparency over their economic activities, and gameplay loops.

## Acknowledgments & Credits
Elu_Tracker is a standalone project heavily expanded from its original scope. While the overall addon has evolved independently, the Commerce tab was specifically inspired by and adapted from Your Paystub, originally created by Michaelqt.

Huge thanks to Michaelqt for giving explicit permission to utilize his commerce logic as a baseline, which provided a great foundation for developing this specialized feature.

## Tutorial & Usage
1. Accessing the Interface
A custom interactive button is injected directly into your main Inventory (Bag) window.

<img width="148" height="158" alt="image" src="https://github.com/user-attachments/assets/28cdc6c6-773c-4d20-9fdd-004eefd9ac3a" />

Click the custom icon to toggle the main Elu_Tracker control panel.

## Features
### Commerce Tracker
Originally built upon the baseline framework by Michaelqt, this module has been heavily refactored.

#### Pending Payout Tracking: 
Real-time countdowns and monitoring for all pending merchant mail payouts.  

#### Enhanced Resource Accumulation: 
Dynamically aggregates data across all active cooldowns to display the exact total volume of pending resources currently en route to your mailbox.

#### Manual Pricing Engine: 
Features a dedicated manual price-entry interface for critical resources (such as Charcoal and Dragon Stabilizers), allowing you to define custom values to maintain perfectly accurate profit math regardless of server API status.  

#### Accurate Resource Logs: 
Categorizes and records exact delivery types, item amounts, and expected payout times for:  Gold  Charcoal Stabilizer  Gilda Stars  Dragon Essence Stabilizer

### Fishing Tracker
#### Catch & Profit Logging: 
Tracks exact fish turn-ins and total gold generated. You can view your financial breakdown by Today’s Profit, Yesterday’s Profit, and Lifetime Total.

#### Session Performance: 
Aggregates real-time session statistics, detailing total gold accumulated. You can view your financial breakdown by Today’s Profit, Yesterday’s Profit, and Lifetime Total, and your most frequently caught fish type.

#### Midnight Session Transfer: 
Features a smart rollover mechanism. If your fishing session goes past midnight, you can manually transfer "Today's" earnings into "Yesterday's" profit with a single click, resetting your daily tracker without losing your session data.

### Misc.
#### Integrated Chronometer (Stopwatch): 
A highly accurate, low-overhead live timer mapped into the user interface

#### Trip Counter: 
A persistent counter for your trade runs. It features anti-DC protection, meaning your progress is safely cached and will only reset if you manually click the "Reset" button. You can set a specific run goal (e.g., 18) and save up to 5 favorite route presets to load them instantly

#### Dynamic Fishing Spot Tracker: 
An advanced utility designed to actively record and time active fishing and schools fish.

Hot-Key Capture: Bind a modifier key (Alt, Shift, or Ctrl) in the Misc settings, hover over a spot, and instantly open a persistent tracking toggle showing the spot's name and remaining time.

Multi-Slot Memory: Keep up to 3 active toggles simultaneously without needing external notes. Attempting to track a 4th spot will trigger a quick confirmation prompt; pressing your hotkey again will automatically overwrite your oldest active tracker.

### Guild Check
Instantly displays the guild of your current target. It creates a customizable floating box at the top of the screen and also adds the guild name directly above the target's health bar.
