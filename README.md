# ShareLiveLoc

Aplikasi berbagi lokasi secara real-time. Pengguna dapat membagikan lokasi GPS mereka ke dalam sebuah group, dan pengguna lain yang memantau group tersebut dapat melihat posisi mereka di peta secara langsung.

## Arsitektur

```
shareliveloc/
├── shareliveloc-api/       # Backend REST API + WebSocket (Go)
├── shareliveloc-mobile/    # Aplikasi mobile (Flutter)
├── docker-compose.yml      # PostgreSQL + API container
└── README.md
```

## Tech Stack

| Komponen | Teknologi |
|----------|-----------|
| Backend | Go, Gin, GORM, gorilla/websocket |
| Database | PostgreSQL 16 |
| Mobile | Flutter, flutter_map (OpenStreetMap), Geolocator |
| Real-time | WebSocket |
| Dev tools | Air (hot-reload), Docker Compose |

---

## Prasyarat

- **Go** >= 1.21
- **Flutter** >= 3.x
- **Docker & Docker Compose** (untuk PostgreSQL, bisa di WSL)
- **Air** (opsional, untuk hot-reload dev) - `go install github.com/air-verse/air@latest`

---

## Quick Start

### 1. Jalankan PostgreSQL

```bash
docker compose up -d postgres
```

### 2. Jalankan API

**Development (dengan hot-reload):**

```bash
cd shareliveloc-api
air
```

**Atau tanpa Air:**

```bash
cd shareliveloc-api
go run main.go
```

**Atau via Docker (API + PostgreSQL):**

```bash
docker compose up -d
```

API berjalan di `http://localhost:8080`

### 3. Jalankan Mobile App

```bash
cd shareliveloc-mobile
flutter pub get
flutter run
```

Konfigurasi API URL di `lib/config.dart`:

```dart
class AppConfig {
  static const String baseUrl = 'http://<IP_ANDA>:8080';
  static const String wsUrl = 'ws://<IP_ANDA>:8080';
}
```

- Android emulator ke localhost: `http://10.0.2.2:8080`
- Device fisik: gunakan IP lokal komputer (contoh: `http://192.168.x.x:8080`)

---

## shareliveloc-api

### Environment Variables

| Variable | Default | Keterangan |
|----------|---------|------------|
| `DB_HOST` | localhost | Host PostgreSQL |
| `DB_PORT` | 5432 | Port PostgreSQL |
| `DB_USER` | shareliveloc | Username database |
| `DB_PASSWORD` | shareliveloc | Password database |
| `DB_NAME` | shareliveloc | Nama database |

### API Endpoints

#### Groups

| Method | Endpoint | Keterangan |
|--------|----------|------------|
| `POST` | `/api/groups` | Buat group baru `{"name": "..."}` |
| `GET` | `/api/groups` | List groups. Query: `?search=xxx&active_only=true` |
| `GET` | `/api/groups/:id` | Detail group |

- Jika total group <= 5, langsung tampilkan semua (tidak perlu search)
- Jika > 5, parameter `search` minimal 3 karakter
- `active_only=true` hanya menampilkan group yang punya share aktif

#### Shares

| Method | Endpoint | Keterangan |
|--------|----------|------------|
| `POST` | `/api/shares` | Mulai berbagi lokasi |
| `PUT` | `/api/shares/:id/location` | Update koordinat GPS |
| `PUT` | `/api/shares/:id/stop` | Berhenti berbagi |
| `GET` | `/api/shares?group_id=x` | List share aktif per group |

**POST /api/shares body:**

```json
{
  "name": "Bus Transjakarta 1",
  "icon": "bus",
  "category": "Transportasi Umum",
  "group_name": "Nama Group",
  "duration_hours": 2
}
```

- `icon`: `bus`, `car`, `person`
- `category`: `Transportasi Umum`, `Lainnya`
- `duration_hours`: 1-8 jam, atau `0` untuk manual (tanpa batas waktu)
- Group otomatis dibuat jika belum ada

#### WebSocket

| Endpoint | Keterangan |
|----------|------------|
| `WS /ws/location/:group_id` | Real-time location updates per group |

**Message format:**

```json
{
  "share_id": 1,
  "name": "Bus Transjakarta 1",
  "icon": "bus",
  "latitude": -6.2088,
  "longitude": 106.8456,
  "is_active": true,
  "updated_at": "2026-04-14T10:00:00Z"
}
```

- `is_active: false` dikirim saat share dihentikan atau expired (client harus hapus marker)

### Database

Auto-migrate saat startup: tabel dan kolom baru otomatis ditambahkan, kolom yang tidak ada di struct otomatis dihapus.

### Struktur Project

```
shareliveloc-api/
├── main.go                 # Entry point, router setup, port :8080
├── models/
│   └── models.go           # GORM models, DB init, auto-migrate
├── handlers/
│   ├── group.go            # Handler CRUD groups
│   ├── share.go            # Handler shares + location update
│   └── websocket.go        # WebSocket hub + broadcast
├── Dockerfile              # Multi-stage build
├── .air.toml               # Air hot-reload config
└── .env                    # Default environment variables
```

---

## shareliveloc-mobile

### Fitur

- **Dashboard**: Peta OpenStreetMap dengan marker real-time per group
  - Filter group (autocomplete jika <= 5, search 3 huruf jika > 5)
  - Hanya tampilkan group yang punya share aktif
  - Marker emoji: bus, mobil, orang
  - Tombol center ke lokasi sendiri
  - Update posisi real-time via WebSocket
- **Share**: Form untuk mulai berbagi lokasi
  - Input: Nama Shareloc, Icon, Kategori, Nama Group (autocomplete + free text), Durasi
  - Durasi: Manual (tanpa batas) atau 1-8 jam
  - Countdown timer saat sharing aktif
  - GPS tracking di background (foreground service) - tetap jalan walau app di-minimize
  - Notifikasi persistent saat berbagi aktif
  - Session tersimpan - buka ulang app tetap menampilkan status sharing
  - Tombol "Berhenti Berbagi" untuk stop manual

### Android Permissions

- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` - GPS
- `ACCESS_BACKGROUND_LOCATION` - GPS di background
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION` - Background service
- `INTERNET` - Koneksi ke API
- `WAKE_LOCK` / `RECEIVE_BOOT_COMPLETED` - Keep service alive

### Struktur Project

```
shareliveloc-mobile/lib/
├── main.dart                       # App entry, bottom navigation
├── config.dart                     # API base URL
├── models/
│   ├── group.dart                  # Model Group
│   └── share.dart                  # Model ShareLocation
├── services/
│   ├── api_service.dart            # HTTP calls ke API
│   ├── location_service.dart       # GPS tracking + background service + session
│   └── websocket_service.dart      # WebSocket client
├── screens/
│   ├── dashboard_screen.dart       # Peta + filter group
│   └── share_screen.dart           # Form share + status + stop
└── widgets/
    ├── group_search_field.dart     # Autocomplete group input
    └── map_widget.dart             # flutter_map + markers
```

### Package ID

```
com.ombapit.shareliveloc
```
