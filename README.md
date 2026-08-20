# 🎵 Hibiki (響き)
> **A sleek, modern, and private local music player for Android & Windows.**  
> *Pure sound, zero telemetry, crafted for music lovers who own their audio.*

<p align="center">
  <img src="https://github.com/user-attachments/assets/ae0d71b2-2593-4641-a76b-ab620c1aab34" alt="Hibiki Logo" width="130" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows-blue?style=for-the-badge&logo=android&logoColor=white" alt="Platforms" />
  <img src="https://img.shields.io/badge/Flutter-v3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/.NET-9.0-512BD4?style=for-the-badge&logo=dotnet&logoColor=white" alt=".NET 9" />
  <img src="https://img.shields.io/badge/Offline-100%25-success?style=for-the-badge" alt="Offline First" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

---

## ✨ Overview

**Hibiki** (Japanese for *echo*, *resonance*, or *sound*) is a high-performance, offline-first music player built from the ground up for people who curate their own audio libraries. 

No subscriptions. No tracking. No forced cloud sync. Just a blazing-fast, gorgeous audio experience designed to make your local and Hi-Res music collection shine across your phone and desktop.

---

## 🚀 Key Features

### 🎨 1. Immersive Glassmorphism & Aesthetics
- **Rotating Vinyl & Disc Visuals**: Interactive vinyl artwork animation that brings your album art to life.
- **Dynamic Themes**: Tailor your mood with curated palettes:
  - 🌑 **Dark Mode** & **Material Dark** (OLED-optimized deep blacks)
  - 🌸 **Cherry Blossom** (Soft blush & rose accents)
  - ☕ **Coffee** (Warm espresso & latte tones)
  - ☀️ **Light Mode** & **Material Light**
- **Fluid Floating Mini-Player**: Bottom-docked player that smoothly expands into a full-screen player experience with live waveforms and lyrics support.
- **Mica & Acrylic Materials**: Native Windows 11 backdrops and Android frosted glass blurs.

---

### 📂 2. Folder-First & Smart Library Indexing
- **Natural Folder Hierarchy**: Subfolders automatically form albums, while standalone tracks in your root directory stay clean as singles.
- **Ultra-Fast Tag Extraction**: Instant multi-threaded scanning of ID3v2, Vorbis, FLAC, and AAC tags with automatic high-res embedded artwork caching.

---

### 🎧 3. Audiophile-Grade Playback & Safety
- **High-Res Audio Engine**: Low-latency WASAPI output on Windows and background audio isolate on Android.
- **Supported Formats**: `FLAC`, `MP3`, `M4A`, `AAC`, `WAV`, `OGG`, `OPUS`, `WMA`.
- **Smart Sleep Timer**: Set a timer to gently fade out music as you fall asleep.

---

### 📋 4. Powerful Playlist & Queue Management
- **Interactive Batch Addition**: Add dozens of tracks to any playlist simultaneously with live debounced search filtering.
- **Drag-and-Drop Reordering**: Rearrange queues and playlists effortlessly.
- **Batch Removal Mode**: Select multiple tracks for clean, single-tap library pruning.
- **Listening Statistics**: Track your offline listening habits and yearly stats.

---

### 🔄 5. Resilient In-App Updater
- **One-Click In-App Updates**: Automatically queries GitHub Releases for updates without needing third-party app stores.
- **Simultaneous Cross-Platform Releases**: Android (`.apk`) and Windows (`.exe`) updates published synchronously under matching release tags.

---

## 📱 Platform Architecture

Hibiki is architected as two native frontends sharing a unified design philosophy:

| Component | Android Mobile | Windows Desktop |
| :--- | :--- | :--- |
| **Framework** | Flutter / Dart | C# 13 / .NET 9 (WPF / WinUI) |
| **Audio Pipeline** | `just_audio` + `audio_service` | `NAudio` (WASAPI low-latency) |
| **Tagging Engine** | `audiotags` | `TagLib#` (TagLibSharp) |
| **System Controls** | Android `MediaSessionCompat` | Windows System Media Transport Controls (SMTC) |
| **Window Backdrop** | Frosted Glass / Flutter Filters | Windows 11 Mica & Acrylic |

---

## 🛠️ Getting Started

### 📱 Android
1. Download the latest **`Hibiki.x.x.x.apk`** from the [Releases](https://github.com/prady2005/MusicApp/releases) page.
2. Install the APK on your device (enable *Install unknown apps* if prompted).
3. Select your music folder on the first launch and enjoy!

### 💻 Windows Version Releasing Soon!

---

## 🔒 Privacy & Freedom

- **100% Offline**: Hibiki never uploads your listening history, files, or telemetry to external servers.
- **No Ads, No Subscriptions**: Free and open source forever.
- **Local Storage**: All caches, playlists, and settings remain solely on your local device.

---

## 🤝 Contributing

Contributions, feature suggestions, and pull requests are welcome! Feel free to open an issue for bugs or enhancements.

---

<p align="center">
  Crafted with ❤️ for music enthusiasts.
</p>
