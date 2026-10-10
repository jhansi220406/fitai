import os
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path

import jwt
import mysql.connector
from flask import Flask, jsonify, request, g
from mysql.connector import IntegrityError
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)

# Allow the Flutter web development server to call this local API.
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = request.headers.get("Origin", "http://localhost:5000")
    response.headers["Vary"] = "Origin"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    return response

@app.route("/<path:path>", methods=["OPTIONS"])
def cors_preflight(path):
    return ("", 204)

MYSQL_PASSWORD = os.environ.get("FITAI_MYSQL_PASSWORD")
JWT_SECRET = os.environ.get("FITAI_JWT_SECRET")


def get_db_connection():
    if MYSQL_PASSWORD is None:
        raise RuntimeError("Set FITAI_MYSQL_PASSWORD before starting FitAI.")
    return mysql.connector.connect(
        host=os.environ.get("FITAI_MYSQL_HOST", "localhost"),
        port=int(os.environ.get("FITAI_MYSQL_PORT", "3306")),
        user=os.environ.get("FITAI_MYSQL_USER", "root"),
        password=MYSQL_PASSWORD,
        database=os.environ.get("FITAI_MYSQL_DATABASE", "fitai"),
    )


def token_required(function):
    @wraps(function)
    def wrapper(*args, **kwargs):
        if not JWT_SECRET:
            return jsonify({"error": "Server JWT secret is not configured"}), 500
        parts = request.headers.get("Authorization", "").split()
        if len(parts) != 2 or parts[0].lower() != "bearer":
            return jsonify({"error": "Authentication token required"}), 401
        try:
            payload = jwt.decode(parts[1], JWT_SECRET, algorithms=["HS256"])
            g.current_user_id = int(payload["sub"])
        except (jwt.InvalidTokenError, ValueError, TypeError, KeyError):
            return jsonify({"error": "Invalid or expired token. Please log in again."}), 401
        return function(*args, **kwargs)
    return wrapper


def current_user_only(function):
    @wraps(function)
    def wrapper(user_id, *args, **kwargs):
        if user_id != g.current_user_id:
            return jsonify({"error": "You can access only your own data"}), 403
        return function(user_id, *args, **kwargs)
    return wrapper


@app.route("/")
def home():
    return jsonify({"message": "FitAI API is running", "status": "running"})


@app.get("/api/health")
def health():
    return jsonify({"message": "Welcome to FitAI!", "status": "running"})


@app.post("/api/register")
def register():
    data = request.get_json(silent=True) or {}
    name, email, password = data.get("name"), data.get("email"), data.get("password")
    if not all(isinstance(v, str) and v.strip() for v in (name, email, password)):
        return jsonify({"error": "Name, email and password are required"}), 400
    if len(password) < 8:
        return jsonify({"error": "Password must contain at least 8 characters"}), 400
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)",
            (name.strip(), email.strip().lower(), generate_password_hash(password)),
        )
        conn.commit()
        return jsonify({"message": "Registration successful", "id": cursor.lastrowid}), 201
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Email already exists"}), 409
    finally:
        cursor.close()
        conn.close()


@app.post("/api/login")
def login():
    data = request.get_json(silent=True) or {}
    email, password = data.get("email"), data.get("password")
    if not isinstance(email, str) or not isinstance(password, str):
        return jsonify({"error": "Email and password are required"}), 400
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, name, email, password_hash FROM users WHERE email=%s", (email.strip().lower(),))
        user = cursor.fetchone()
        if not user or not check_password_hash(user["password_hash"], password):
            return jsonify({"error": "Invalid email or password"}), 401
        if not JWT_SECRET:
            return jsonify({"error": "Server JWT secret is not configured"}), 500
        now = datetime.now(timezone.utc)
        token = jwt.encode({"sub": str(user["id"]), "iat": now, "exp": now + timedelta(hours=2)}, JWT_SECRET, algorithm="HS256")
        return jsonify({"message": "Login successful", "id": user["id"], "name": user["name"], "email": user["email"], "token": token, "token_type": "Bearer", "expires_in_seconds": 7200})
    finally:
        cursor.close()
        conn.close()


@app.get("/api/profile")
@token_required
def profile():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, name, email FROM users WHERE id=%s", (g.current_user_id,))
        user = cursor.fetchone()
        if not user:
            return jsonify({"error": "User not found"}), 404
        return jsonify(user)
    finally:
        cursor.close()
        conn.close()


@app.get("/api/workouts")
def get_workouts():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, name, duration FROM workouts ORDER BY id")
        return jsonify(cursor.fetchall())
    finally:
        cursor.close()
        conn.close()


@app.post("/api/workouts")
@token_required
def add_workout():
    data = request.get_json(silent=True) or {}
    name, duration = data.get("name"), data.get("duration")
    if not isinstance(name, str) or not name.strip():
        return jsonify({"error": "Workout name is required"}), 400
    if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
        return jsonify({"error": "Duration must be a positive integer"}), 400
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO workouts (name, duration) VALUES (%s, %s)", (name.strip(), duration))
        conn.commit()
        return jsonify({"message": "Workout added successfully", "id": cursor.lastrowid}), 201
    finally:
        cursor.close()
        conn.close()


@app.put("/api/workouts/<int:workout_id>")
@token_required
def update_workout(workout_id):
    data = request.get_json(silent=True) or {}
    name, duration = data.get("name"), data.get("duration")
    if not isinstance(name, str) or not name.strip():
        return jsonify({"error": "Workout name is required"}), 400
    if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
        return jsonify({"error": "Duration must be a positive integer"}), 400
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE workouts SET name=%s, duration=%s WHERE id=%s", (name.strip(), duration, workout_id))
        conn.commit()
        if cursor.rowcount == 0:
            cursor.execute("SELECT id FROM workouts WHERE id=%s", (workout_id,))
            if cursor.fetchone() is None:
                return jsonify({"error": "Workout not found"}), 404
        return jsonify({"message": "Workout updated successfully"})
    finally:
        cursor.close()
        conn.close()


@app.delete("/api/workouts/<int:workout_id>")
@token_required
def delete_workout(workout_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM workouts WHERE id=%s", (workout_id,))
        conn.commit()
        if cursor.rowcount == 0:
            return jsonify({"error": "Workout not found"}), 404
        return jsonify({"message": "Workout deleted successfully"})
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Workout is assigned to a user or has progress records"}), 409
    finally:
        cursor.close()
        conn.close()


@app.route("/api/me/workouts", methods=["GET", "POST"])
@token_required
def user_workouts():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        if request.method == "GET":
            cursor.execute("""SELECT w.id, w.name, w.duration FROM user_workouts uw
                              JOIN workouts w ON w.id=uw.workout_id
                              WHERE uw.user_id=%s ORDER BY uw.id""", (g.current_user_id,))
            return jsonify(cursor.fetchall())
        data = request.get_json(silent=True) or {}
        workout_id = data.get("workout_id")
        if isinstance(workout_id, bool) or not isinstance(workout_id, int) or workout_id <= 0:
            return jsonify({"error": "A valid workout_id is required"}), 400
        cursor.execute("INSERT INTO user_workouts (user_id, workout_id) VALUES (%s, %s)", (g.current_user_id, workout_id))
        conn.commit()
        return jsonify({"message": "Workout added to your plan"}), 201
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Workout does not exist or is already in your plan"}), 409
    finally:
        cursor.close()
        conn.close()


@app.route("/api/me/progress", methods=["GET", "POST"])
@token_required
def progress():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        if request.method == "POST":
            data = request.get_json(silent=True) or {}
            workout_id, duration = data.get("workout_id"), data.get("duration_minutes")
            if isinstance(workout_id, bool) or not isinstance(workout_id, int) or workout_id <= 0:
                return jsonify({"error": "A valid workout_id is required"}), 400
            if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
                return jsonify({"error": "duration_minutes must be a positive integer"}), 400
            cursor.execute("SELECT id FROM workouts WHERE id=%s", (workout_id,))
            if cursor.fetchone() is None:
                return jsonify({"error": "Workout not found"}), 404
            cursor.execute("""INSERT INTO workout_progress (user_id, workout_id, duration_minutes, completed)
                              VALUES (%s, %s, %s, TRUE)""", (g.current_user_id, workout_id, duration))
            conn.commit()
            return jsonify({"message": "Workout progress recorded", "progress_id": cursor.lastrowid}), 201
        cursor.execute("""SELECT wp.id AS progress_id, w.id AS workout_id, w.name AS workout_name,
                          wp.duration_minutes, wp.completed, wp.completed_at
                          FROM workout_progress wp JOIN workouts w ON w.id=wp.workout_id
                          WHERE wp.user_id=%s ORDER BY wp.completed_at DESC, wp.id DESC""", (g.current_user_id,))
        rows = cursor.fetchall()
        for row in rows:
            row["completed"] = bool(row["completed"])
            row["completed_at"] = row["completed_at"].isoformat(sep=" ", timespec="seconds")
        return jsonify(rows)
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Invalid user or workout"}), 400
    finally:
        cursor.close()
        conn.close()


@app.get("/api/me/progress/summary")
@token_required
def progress_summary():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""SELECT COUNT(*) AS completed_workouts,
                          COALESCE(SUM(duration_minutes), 0) AS total_minutes
                          FROM workout_progress WHERE user_id=%s AND completed=TRUE""", (g.current_user_id,))
        return jsonify(cursor.fetchone())
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    if not JWT_SECRET:
        raise RuntimeError("Set FITAI_JWT_SECRET before starting FitAI.")
    app.run(debug=True)
