# FitAI — Flutter + Flask + MySQL

This ZIP contains the FitAI Flask backend and a Flutter frontend source project. It does **not** include your database password, JWT secret, existing database records, or generated Flutter platform folders.

## Project folders
- `backend/` — Flask APIs with JWT authentication
- `database/schema.sql` — MySQL tables and starter workouts
- `frontend/lib/main.dart` — Flutter login/register, dashboard, workouts, plan, progress UI
- `frontend/pubspec.yaml` — Flutter dependencies

## 1. MySQL
If your existing `fitai` database and tables are already set up, keep using them and do not rerun schema setup unnecessarily. For a new database, run `database/schema.sql` in MySQL.

## 2. Start the backend (Windows PowerShell)
Open a terminal in `fitai_flutter_project`:

```powershell
cd backend
python -m venv venv
.env\Scripts\Activate.ps1
python -m pip install -r requirements.txt
$env:FITAI_MYSQL_PASSWORD = "YOUR_MYSQL_PASSWORD"
$env:FITAI_JWT_SECRET = python -c "import secrets; print(secrets.token_hex(32))"
python app.py
```

Keep this terminal running. Use your actual MySQL password. Do not share secrets or commit them to GitHub. The backend uses port 5000.

## 3. Generate Flutter platform files
Install Flutter and verify with `flutter doctor`. In a **second terminal**:

```powershell
cd frontend
flutter create --platforms=web,android .
flutter pub get
flutter run -d chrome
```

If `flutter create` asks about overwriting `lib/main.dart`, keep the existing file. If prompted, select the option to preserve it. This creates the platform scaffolding while keeping the included Flutter screen.

The app is configured for Chrome on the same computer at `http://127.0.0.1:5000/api`. For Android emulator testing, change `apiBase` in `lib/main.dart` to `http://10.0.2.2:5000/api`. For a physical phone, use your computer's LAN IP and configure the Flask server to listen on `0.0.0.0`; both devices must be on the same network.

## Features in this starter
- Register and log in using Flask APIs and JWT
- Browse workouts
- Add workouts to your personal plan
- Record completed workouts
- View progress history and total exercise minutes

The Flutter web app calls the API on localhost. This is a learning starter; before deployment, use HTTPS, disable Flask debug mode, and review production security.
