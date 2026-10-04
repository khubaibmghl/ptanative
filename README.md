# PTA Native: Dual-App Cross-Platform Cellular Relay System

A commercial-grade native relay system replacing Termux and web PWAs with an unkillable Android host service on **Vivo S1** and a native **iPhone 15 Pro Liquid Glass** companion app.

---

## Architecture Overview

```
                      +---------------------------------------+
                      |               VIVO S1                 |
                      |  MediaTek Helio P65 • Android 11     |
                      |  Zong 4G SIM • Unkillable Service     |
                      +---------------------------------------+
                                          |
                      Embedded WebSocket Server (:8080)
                      Sub-10ms local transport (Wi-Fi/Hotspot)
                                          |
                      +---------------------------------------+
                      |            IPHONE 15 PRO              |
                      |  iOS 18+ Liquid Glass Native App      |
                      |  Native Apple CallKit ("Slide to Ans")|
                      |  Embedded SQLite (1-to-many numbers)  |
                      |  Bank OTP Extractor & 1-Tap Copy      |
                      |  Zong GSM vs WhatsApp Action Picker   |
                      +---------------------------------------+
```

### Key Modules:
1. **`pta_host`**: Android companion app running an unkillable Android Foreground Service, embedded WebSocket/HTTP server on port 8080, native Android Telephony listener, and hardware ADB loopback (:5555) for 1-tap call drops.
2. **`pta_phone`**: Native iOS Flutter app with iPhone 15 Pro Liquid Glass theme (Dynamic Island safe-area, frosted glass dock), Apple CallKit integration, local embedded SQLite database for offline contacts and call history, and unified WhatsApp VoIP routing.
3. **`pta_shared`**: Shared Dart protocol engine with 1-to-many contact schemas, Pakistani phone number normalization (`0300...` <-> `+92300...`), and sub-20ms WebSocket frames.

---

## Building the Apps (Zero-Mac Cloud CI/CD)

Because iOS compilation requires macOS, this repository includes an automated GitHub Actions pipeline (`.github/workflows/build_native_apps.yml`) that compiles the unsigned `.ipa` for iPhone 15 Pro and `.apk` for Vivo S1 on free GitHub-hosted macOS runners.

### Step 1: Push Repository to GitHub
```bash
git init
git add .
git commit -m "feat: complete PTA Native dual-app system"
git branch -M main
git remote add origin https://github.com/<your-username>/pta-native.git
git push -u origin main
```

### Step 2: Download Artifacts from GitHub
1. Open your repository on GitHub.
2. Click on the **Actions** tab.
3. Select the latest run of **Build PTA Native Apps**.
4. Download the artifacts:
   - **`PTA_Phone_iPhone15Pro_LiquidGlass_IPA`**: Unsigned `.ipa` ready for SideStore / AltStore.
   - **`PTA_Host_Vivo_S1_Engine_APK`**: Release `.apk` ready for Vivo S1.

---

## Installing on iPhone 15 Pro (SideStore / AltStore)

1. Transfer `PTA_Phone_iOS_LiquidGlass.ipa` to your iPhone 15 Pro (via AirDrop, iCloud Drive, or Telegram saved messages).
2. Open **SideStore** or **AltStore** on your iPhone.
3. Tap the **+** (Add App) icon and select `PTA_Phone_iOS_LiquidGlass.ipa`.
4. SideStore will sign the app with your personal free Apple ID and install it.
5. In iOS **Settings > General > VPN & Device Management**, tap your developer certificate and select **Trust**.

---

## Installing on Vivo S1

1. Transfer `PTA_Host_Vivo_S1_Release.apk` to your Vivo S1 via USB or WhatsApp.
2. Tap the APK to install.
3. Grant required runtime permissions:
   - Telephony (`Phone`, `Call Logs`, `Contacts`, `SMS`)
   - Battery Optimization (`Ignore battery optimizations` for unkillable service)
4. Tap the glowing master toggle switch to turn ON the Foreground Relay Engine.

---

## Daily Operation & Wireless Link

1. Ensure both devices are on the same Wi-Fi network or connected via Vivo S1 Hotspot.
2. Open **PTA Phone** on iPhone 15 Pro. In **Settings**, verify the Host IP matches Vivo S1's IP (default: `192.168.23.68`).
3. The top status capsule under the Dynamic Island will glow green (`Vivo S1 • Connected`).
4. **Incoming Calls**: When someone calls your Zong 4G SIM, your iPhone 15 Pro screen immediately turns on with the native Apple CallKit green slider ("Slide to Answer").
5. **Outgoing Calls**: Tap the green Call button in Keypad to dial via Zong GSM; long press to pick between Zong GSM or WhatsApp Voice Call.
6. **Bank OTPs**: Any received SMS appears in the **Messages** tab with large gold digits and a 1-tap `[ Copy OTP ]` button.
