# ClimateEye

This repository contains **both**:

1. **Flutter app** (`lib/`, `android/`, `ios/`, `web/`, …) — ClimateEye mobile/web client  
2. **Web dashboard** (`src/`, `package.json`, `public/`, …) — SKY EYE environmental monitoring frontend

---

## Flutter app

```bash
flutter pub get
flutter run -d chrome
```

See [Flutter docs](https://docs.flutter.dev/) for setup help.

---

## Web dashboard (Vite)

A modern environmental monitoring dashboard with dark theme and teal accents.

### Features

- Login system with admin credentials
- Date range selector (default: one week before today → today)
- Dark theme with teal accents
- Responsive UI

### Install & run

```bash
npm install
npm run dev
```

App: `http://localhost:3000`

### Notes

- India construction tiles are hosted on R2; see `docs/construction-tiles.md`
- Backend APIs are configured per environment (see `.env.example`)
