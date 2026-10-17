# 📡 Beamo v1.0.0 — first release

*Beam files from your phone to your TV — no internet, no cloud, no account.*

Local-network file sharing — **phone → TV** (main) + phone → phone over the same Wi-Fi or hotspot.

## What's inside

- Phone → TV file sharing with live progress on both ends
- Phone → phone sharing on the same network
- mDNS discovery (`_beamo._tcp`) + manual-IP fallback for hotspots that block multicast
- Offer → Accept → Upload protocol: receiver sees an Accept/Decline dialog per file
- TV-friendly Receive screen (Accept button autofocused for D-pad remotes)

## Install

1. Download `beamo-v1.0.0.apk` below
2. **Phone:** open the APK to install (allow "Install unknown apps" when asked)
3. **Android TV:** sideload the same APK (USB stick or an app like "Send Files to TV"), open it, tap **Receive files**

## Known limitations

- One file at a time per peer; no resume if the connection drops mid-transfer
- No transfer encryption — LAN only, don't use on untrusted networks
- Receiver can't browse the sender's files (push-only for now)

Built with Flutter · package `com.nuvishh.beamo` · version 1.0.0 (build 1)
