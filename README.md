# P2P Talk

A cross-platform P2P encrypted chat application supporting Windows and Android. Messages are end-to-end encrypted and transmitted via WebRTC DataChannel (P2P direct connection), bypassing servers entirely.

一款跨平台（Windows + Android）P2P 加密聊天应用。消息端到端加密，通过 WebRTC DataChannel 直传，不经过服务器。

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Android-blue" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-3.44-blue" alt="flutter">
  <img src="https://img.shields.io/badge/Go-1.22-00ADD8" alt="go">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

---

## ✨ Features / 功能

- 🔐 **E2EE Encryption** — ECDH + AES-256-GCM, messages encrypted before leaving the device
- 🚀 **P2P Direct Transfer** — WebRTC DataChannel, messages don't pass through any server
- 🌐 **LAN + Internet** — mDNS auto-discovery on LAN, signaling server assisted connection over the internet
- 📱 **Cross Platform** — Single Flutter codebase for Windows and Android
- 🟢 **Online Status** — Real-time presence via WebSocket heartbeat
- 💬 **Text Messages** — UTF-8 support, offline queue with auto-retry
- 🎨 **Contact Avatars** — Deterministic color letter avatars generated from nickname
- 📋 **QR Code Sharing** — Share your PeerId via QR, copy to clipboard
- 📦 **Local Storage** — SQLite persistence, zero server storage cost
- 🔄 **DB Migration** — Built-in schema migration protects user data on upgrade

---

## 🏗️ Architecture / 架构

```
┌──────────────────────────┐          ┌──────────────────────────┐
│   Alice (Windows/Android) │          │   Bob (Windows/Android)   │
│                          │          │                          │
│  ┌────────────────────┐  │  WebRTC  │  ┌────────────────────┐  │
│  │  UI Layer          │  │◄═══════►│  │  UI Layer          │  │
│  │  · HomeScreen      │  │ DataCh. │  │  · HomeScreen      │  │
│  │  · ChatScreen      │  │ (E2EE)  │  │  · ChatScreen      │  │
│  │  · AddContact      │  │          │  │  · AddContact      │  │
│  │  · MyQR            │  │          │  │  · MyQR            │  │
│  ├────────────────────┤  │          │  ├────────────────────┤  │
│  │  Services          │  │          │  │  Services          │  │
│  │  · ChatService     │  │          │  │  · ChatService     │  │
│  │  · ContactService  │  │          │  │  · ContactService  │  │
│  │  · StorageService  │  │          │  │  · StorageService  │  │
│  ├────────────────────┤  │          │  ├────────────────────┤  │
│  │  P2P Core          │  │          │  │  P2P Core          │  │
│  │  · WebRTC Connect  │  │          │  │  · WebRTC Connect  │  │
│  │  · SignalingClient │  │          │  │  · SignalingClient │  │
│  │  · ConnectionMgr   │  │          │  │  · ConnectionMgr   │  │
│  │  · mDNS Discovery  │  │          │  │  · mDNS Discovery  │  │
│  ├────────────────────┤  │          │  ├────────────────────┤  │
│  │  E2EE + Identity   │  │          │  │  E2EE + Identity   │  │
│  │  · ECDH AES-GCM    │  │          │  │  · ECDH AES-GCM    │  │
│  │  · ECDSA PeerId    │  │          │  │  · ECDSA PeerId    │  │
│  └────────┬───────────┘  │          │  └────────┬───────────┘  │
│           │              │          │           │              │
└───────────┼──────────────┘          └───────────┼──────────────┘
            │                                     │
            │  WebSocket (signaling only / 仅信令)  │
            └──────────────────┬──────────────────┘
                               │
                     ┌─────────▼─────────┐
                     │  Signaling Server │
                     │  (Go, single bin)  │
                     │                   │
                     │  · Peer registry  │
                     │  · SDP/ICE relay  │
                     │  · Presence       │
                     └───────────────────┘
```

### Message Flow / 消息流程

```
Alice types "Hello"
  │
  └─► ChatService.sendMessage()
       ├─ utf8.encode()
       ├─ E2EE.encrypt() ──► AES-256-GCM ciphertext
       ├─ ConnectionManager.sendMessage()
       │    ├─ WebRTC DataChannel (primary) ──► Bob's DataChannel.onMessage
       │    └─ WebSocket relay (fallback)
       └─ SQLite storage (local)

Bob receives
  │
  └─► ConnectionManager.onMessage
       ├─ base64.decode
       ├─ E2EE.decrypt() ──► plaintext
       └─ SQLite storage ──► UI displays bubble
```

### Connection Establishment / 连接建立

```
Alice                           Server                          Bob
  │                                │                              │
  │──── WS: register(peerId) ────►│◄─── WS: register(peerId) ───│
  │◄── WS: presence(Bob online) ──│─── WS: presence(Alice) ────►│
  │                                │                              │
  │ Alice clicks Bob's contact     │                              │
  │──── WS: call(Bob, SDP offer) ─►│──── WS: incoming call ─────►│
  │                                │                              │
  │◄─── ICE candidates ───────────│─── ICE candidates ──────────│
  │◄─── WS: answer(SDP) ──────────│──── WS: accept(SDP) ────────│
  │                                │                              │
  │═══════════ WebRTC DataChannel (P2P, E2EE) ════════════════════│
  │                                │                              │
  │       (messages never touch server / 消息不经过服务器)         │
```

---

## 📂 Project Structure / 项目结构

```
p2p_talk/
├── lib/
│   ├── main.dart                      # Entry, Provider setup, --profile
│   ├── core/
│   │   ├── avatar.dart                # Letter avatar generator
│   │   ├── constants.dart             # Server URL, STUN, timeouts
│   │   ├── crypto.dart                # E2EE: ECDH + AES-256-GCM
│   │   └── identity.dart              # ECDSA key pair, PeerId
│   ├── models/
│   │   ├── contact.dart               # Contact data model
│   │   ├── message.dart               # Message + status enum
│   │   └── peer_info.dart             # mDNS peer info
│   ├── p2p/
│   │   ├── connection_manager.dart    # Call/accept/ICE orchestration
│   │   ├── mdns_discovery.dart        # LAN mDNS auto-discovery
│   │   ├── signaling_client.dart      # WebSocket signaling client
│   │   └── webrtc_connection.dart     # RTCPeerConnection + DataChannel
│   ├── services/
│   │   ├── chat_service.dart          # Send/receive/encrypt/offline queue
│   │   ├── contact_service.dart       # CRUD + online status
│   │   └── storage_service.dart       # SQLite persistence + migrations
│   └── ui/screens/
│       ├── add_contact_screen.dart     # Add by PeerId or QR
│       ├── chat_screen.dart           # Chat bubbles + status
│       ├── home_screen.dart           # Contact list (online dots)
│       ├── my_qr_screen.dart          # QR code + Copy PeerId
│       └── settings_screen.dart       # Identity info
├── signaling_server/
│   ├── main.go                        # Go WebSocket hub (219 lines)
│   └── go.mod
├── android/                           # Android platform files
├── windows/                           # Windows platform files
└── pubspec.yaml
```

---

## 🚀 Quick Start / 快速开始

### Prerequisites / 环境要求

- Flutter SDK ≥ 3.16 (`D:\flutter`)
- Go ≥ 1.22 (`D:\Go`)
- JDK 17 (`D:\Jdk17`)
- Android SDK 36 (`D:\Android\SDK`)
- Visual Studio 2022 (for Windows builds)

### Environment Variables / 环境变量

```powershell
$env:ANDROID_HOME = "D:\Android\SDK"
$env:JAVA_HOME = "D:\Jdk17"
$env:PATH += ";D:\flutter\bin;D:\Go\bin"
```

### Build Windows / 编译 Windows

```bash
cd p2p_talk
flutter pub get
flutter build windows
# output: build\windows\x64\runner\Release\p2p_talk.exe

# Fix install (run once after clean)
mkdir -p build/native_assets/windows
cmake -DBUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="build/windows/x64/runner/Release" -P build/windows/x64/cmake_install.cmake
```

### Build Android / 编译 Android

```bash
flutter build apk
# output: build\app\outputs\flutter-apk\app-release.apk
```

### Run Signaling Server / 启动信令服务器

```bash
cd signaling_server
go build -o signaling-server.exe main.go
./signaling-server.exe    # listens on :8080
```

### Run Two Instances for Testing / 测试双人聊天

```powershell
# Profile "alice"
Start-Process p2p_talk.exe -ArgumentList '--profile=alice'

# Profile "bob"
Start-Process p2p_talk.exe -ArgumentList '--profile=bob'
```

Each profile has its own PeerId and database. Add each other via PeerId → chat!

---

## 🔐 Encryption / 加密

| Layer | Algorithm | Purpose |
|------|------|------|
| Identity | ECDSA secp256r1 | PeerId generation, message signing |
| Key Exchange | ECDH secp256r1 | Shared secret negotiation |
| Message Encryption | AES-256-GCM | Authenticated encryption, one key per peer pair |
| Transport | DTLS (WebRTC) | Native WebRTC transport layer encryption |

---

## 🗄️ Database / 数据库

SQLite, local only. Three tables:

```
contacts: peer_id, nickname, public_key, is_online, added_at, last_seen
messages: id, sender_id, receiver_id, ciphertext, timestamp, seq, status, chat_with
identity: peer_id, public_hex, private_hex
```

Schema upgrades are handled by the built-in migration system (`_dbVersion` + `_migrations` map). Old user data is never lost on upgrade.

---

## 🛠️ Tech Stack / 技术栈

| Component | Technology | Notes |
|------|------|------|
| Framework | Flutter 3.44 | Single codebase for Windows + Android |
| P2P Transport | flutter_webrtc 1.5.0 | DataChannel on native libwebrtc |
| Signaling Server | Go + gorilla/websocket | Single binary, ~8MB, < 10MB RAM |
| Crypto | pointycastle 3.9 | ECDSA + ECDH + AES-GCM |
| DB | sqflite + sqflite_common_ffi | SQLite on all platforms |
| State | Provider + ChangeNotifier | Lightweight reactive state |

---

## 📝 Configuration / 配置

Edit `lib/core/constants.dart`:

```dart
// Signaling server URL
static const signalingServerUrl = 'ws://192.168.1.x:8080/ws';

// STUN servers for NAT traversal
static const iceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
];
```

---

## 🚢 Deployment / 部署

Signaling server can run on anything — a cheap VPS, Raspberry Pi, or even your home PC with Cloudflare Tunnel.

```bash
# Deploy to VPS
scp signaling-server.exe user@server:/opt/p2p/
ssh user@server ./opt/p2p/signaling-server.exe &

# Zero-cost: Cloudflare Tunnel + home PC
cloudflared tunnel create p2p-signal
cloudflared tunnel route dns p2p-signal signal.yourdomain.com
cloudflared tunnel run --url http://localhost:8080 p2p-signal
```

---

## 🧪 Testing / 测试

```bash
# Windows desktop
flutter run -d windows --profile=alice
flutter run -d windows --profile=bob
# Add each other's PeerId → click chat → send message

# Android
flutter run -d android
# Connect to same WiFi → use PC's LAN IP as server address
```

---

## 📋 Roadmap / 后续计划

- [x] P2P text chat with E2EE
- [x] LAN auto-discovery (mDNS)
- [x] Online/offline presence
- [x] Offline message queue
- [x] Contact avatars
- [x] Database migration system
- [ ] File transfer
- [ ] Group chat
- [ ] Voice/video calls
- [ ] iOS support
- [ ] Real key exchange on contact add
- [ ] DHT-based peer discovery (no server)

---

## 📄 License

MIT
