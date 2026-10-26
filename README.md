# Origins-Activity-Helper
Privacy-focused The Isle: Evrima activity helper for the Origins Discord. Automatically detects Origins, Official EU servers, Main Menu, Other Server and Offline without Steam passwords, Discord tokens, packet capture or manual server selection.

# Origins Activity Helper

A lightweight, privacy-focused helper for **The Isle: Evrima** that automatically reports a player's activity to the **Origins Discord**.

The helper can detect and report:

- **Origins**
- **Official EU servers**
- **Main Menu**
- **Other Server**
- **Offline**

It runs locally on the player's PC and updates automatically when they switch servers.

## How it works

The helper reads The Isle's local `TheIsle.log` file and detects the current server connection from the game's own connection data.

It then compares that server locally against the Origins / Official EU server directory and sends only the final resolved status back to the Origins bot.

For example:

`Official EU 6`

`Origins`

`Main Menu`

`Other Server`

`Offline`

Raw server IPs are not uploaded.

## Privacy

The helper is intentionally minimal and transparent.

It does **not**:

- ask for Steam passwords
- ask for Steam Guard codes
- require a Discord password or user token
- monitor browser activity
- inspect unrelated files
- packet-sniff network traffic
- modify The Isle
- install drivers
- require Administrator privileges
- contain advertising or analytics
- upload the raw game-server IP

The source is provided as readable PowerShell/Python scripts so users can inspect exactly what it does before running it.

## Windows Installation

1. Link and verify your Steam account with the Origins Discord bot.
2. Use the **PC Helper** button or `/activity-helper-setup` in Discord.
3. Copy the private **Server URL** and **Pairing Token**.
4. Download and extract this ZIP.
5. Open PowerShell in the extracted folder.
6. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Windows.ps1
```

7. Paste the Server URL and Pairing Token when prompted.

The helper installs into:

`%LOCALAPPDATA%\OriginsActivityHelper`

and automatically starts when the user signs into Windows.

No Administrator access is required.

## Security

Each member receives their own unique pairing secret.

Activity updates are signed using HMAC-SHA256, and the pairing secret itself is not sent with normal activity updates.

Generating a new pairing token automatically invalidates the previous one.

Users can revoke access at any time with:

`/activity-helper-remove`

## Supported Activity

The helper automatically handles:

- Origins
- Official EU servers
- Main Menu
- Other / unsupported community servers
- Offline state

Official EU server mappings are refreshed dynamically rather than permanently hard-coded.

## Project Goals

This helper was built to make the Origins activity board accurate without requiring invasive Steam authentication, Steam Rich Presence access, packet capture, or manual server selection.

**Install once, play normally, and let your activity update automatically.**
