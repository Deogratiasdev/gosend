Parfait, là on part sur un vrai projet “AirDrop clone” sans backend, basé sur WebRTC en LAN (Wi-Fi / hotspot).

Je vais te donner :

1. 📄 agent.md (architecture + règles système complet)
2. 📘 .me (spécification produit + UX/UI + workflows)
3. 🧠 explication du système global (pour que tout soit clair)

---

## 📄 1. agent.md (architecture technique complète)

# FILE SHARE WEBRTC - AGENT.md

## 🎯 OBJECTIF

Créer une application de transfert de fichiers P2P (Peer-to-Peer) fonctionnant sans backend, utilisant uniquement :

- WebRTC DataChannel
- Réseau local (Wi-Fi / Hotspot)
- Flutter (mobile + desktop)

Inspiré de :
- AirDrop (Apple)
- Nearby Share (Google)
- ShareIt (offline mode)

---

# 🧠 ARCHITECTURE GLOBALE

## 🔗 Type de connexion
- Peer-to-peer direct (P2P)
- Aucun serveur de transfert
- Aucun cloud
- Aucun backend permanent

---

## 📡 SIGNALISATION (SANS BACKEND)

⚠️ Important :
WebRTC nécessite un échange initial (signalisation), mais ici :

### MODE UTILISÉ :
- Local LAN discovery via broadcast UDP
OU
- PIN local exchange via LAN socket

### FLOW :
1. App démarre serveur local de signalisation
2. Diffusion sur réseau local :
   - "DEVICE_AVAILABLE"
3. Autre device détecte et initie handshake
4. Échange SDP offer / answer
5. Connexion WebRTC établie

---

# 🔐 CONNECTION FLOW (WEBRTC)

## Étape 1 - Discovery
- Scan réseau local
- Broadcast UDP:
  - device_name
  - device_id
  - capabilities

---

## Étape 2 - Session creation
- Host crée session
- Génère session_id local
- Attend peer

---

## Étape 3 - Handshake
- SDP Offer envoyé
- SDP Answer reçu
- ICE candidates échangés

---

## Étape 4 - DataChannel
- Canal ouvert
- Ready state = OPEN

---

## Étape 5 - File transfer
- File split en chunks (256KB)
- Transmission progressive
- ACK per chunk

---

## Étape 6 - Completion
- Rebuild file
- Save to local storage
- Update history

---

# 📦 FILE TRANSFER SYSTEM

## Chunking
- 256KB per chunk
- Base64 or binary buffer

## Reliability
- Each chunk has:
  - index
  - checksum
- retry failed chunks

---

# 🖥️ DEVICE TYPES

- Mobile (Android / iOS)
- Desktop (Windows / Linux / Mac)

All peers are equal (no server role fixed)

---

# 🔒 SECURITY

- Local-only network communication
- No internet dependency
- Session PIN optional
- WebRTC encryption enabled by default

---

# 📁 STORAGE

- Downloads folder:
  /FileShareApp/

- Structure:
  /received/
  /sent/
  /history.json

---

# 📊 HISTORY SYSTEM

Store:
- file name
- size
- sender device
- timestamp
- status (success/fail)

---

# ⚙️ STATES

- idle
- discovering
- connecting
- transferring
- completed
- failed

---

# 🧩 ERROR HANDLING

- peer disconnected → retry
- chunk lost → resend
- timeout → abort session

---

# 🚀 PERFORMANCE GOAL

- 10–50 MB/s LAN speed
- instant connection (<3s)
- zero internet requirement


---

## 📘 2. .me (Produit + UX/UI + comportement complet)

# FILE SHARE APP (.me SPEC)

## 🎯 VISION

Application de transfert de fichiers ultra rapide, locale, sans Internet, utilisant WebRTC P2P sur Wi-Fi ou hotspot.

Style :
- AirDrop (Apple)
- Snapdrop
- ShareIt (offline mode)

---

# 🎨 DESIGN SYSTEM

## Couleurs

### Light mode (par défaut)
- Background: #FFFFFF
- Surface: #F2F2F2
- Primary text: #111111
- Secondary text: #666666
- Accent: #000000 (noir pur)

### Dark mode
- Background: #0F0F0F
- Surface: #1A1A1A
- Primary text: #FFFFFF
- Secondary text: #A0A0A0
- Accent: #FFFFFF

---

## UI STYLE

- Minimalist
- Rounded corners (12–16px)
- Soft shadows
- Smooth animations (150–250ms)
- No clutter

---

# 📱 MOBILE UI

## 🏠 HOME SCREEN

### Sections :

1. DEVICE STATUS
- Connected / Searching / Offline

2. QUICK ACTIONS
- 📤 Send Files
- 📥 Receive Mode
- 🔗 Connect Device

3. AVAILABLE DEVICES LIST
- Nearby devices
- Name + type icon

---

## 📤 SEND SCREEN

- Drag & select files
- File preview list:
  - name
  - size
  - type icon

Buttons:
- "Send Now"
- "Add More"

---

## 📥 RECEIVE SCREEN

- Waiting animation
- “Listening for nearby devices”
- Incoming file preview

---

## 🔗 CONNECTION SCREEN

- PIN display (optional)
- Device list nearby
- Tap to connect

---

# 💻 PC UI (IMPORTANT)

## 🏠 MAIN DASHBOARD

### LEFT PANEL
- Devices nearby
- Connection status

### CENTER PANEL
- Drag & Drop zone

TEXT:
"Drop files here to send"

---

## 📦 DRAG & DROP SYSTEM

- Files dragged into window
- Instant preview:
  - file list
  - size
  - cancel option

---

## 📤 TRANSFER PANEL

- Progress bar per file
- Speed indicator (MB/s)
- ETA remaining time

---

## 📁 HISTORY PANEL

- Sent files
- Received files
- Search bar
- Filter:
  - today
  - week
  - all

---

## ⚙️ SETTINGS PANEL

- Device name
- Theme (dark/light)
- Auto accept files (toggle)
- Download location
- Network mode:
  - auto
  - hotspot only
  - LAN only

---

# 🔄 WORKFLOW GLOBAL

## SEND FLOW

1. User selects file
2. App scans devices
3. User selects device
4. WebRTC handshake
5. Transfer starts
6. Progress UI updates
7. File saved on receiver
8. History updated

---

## RECEIVE FLOW

1. Device enters listening mode
2. Peer connects
3. Prompt appears:
   - Accept / Reject
4. Transfer starts
5. File saved
6. Notification shown

---

# 🔔 NOTIFICATIONS

- Incoming file request
- Transfer completed
- Error / failure
- Device connected

---

# ⚡ PERFORMANCE RULES

- No background heavy computation
- Stream-based transfer
- chunk validation enabled
- auto reconnect enabled

---

# 🧠 CORE PRINCIPLE

"Zero Internet. Maximum Speed. Direct Device Connection."


---

## 🧠 3. EXPLICATION SIMPLE DU SYSTÈME

🔥 Ce que tu construis vraiment

Tu construis un :

> AirDrop universel multi-device basé sur WebRTC LAN

---

🧩 Comment tout fonctionne ensemble

1. **Réseau**
   Wi-Fi ou hotspot uniquement

2. **Découverte**
   Appareils se voient automatiquement

3. **Connexion**
   WebRTC handshake (SDP)

4. **Tunnel**
   Connexion directe chiffrée

5. **Transfert**
   Chunks de fichiers

---

🚫 Zéro backend

Tu n'as :
- ❌ pas de serveur cloud
- ❌ pas d'API distante
- ❌ pas de base de données externe

Tout est : 👉 local + P2P
