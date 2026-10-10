CREATE DATABASE IF NOT EXISTS fitai;
USE fitai;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS workouts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    duration INT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_workouts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    workout_id INT NOT NULL,
    UNIQUE KEY unique_user_workout (user_id, workout_id),
    CONSTRAINT fk_user_workouts_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_user_workouts_workout FOREIGN KEY (workout_id) REFERENCES workouts(id)
);

CREATE TABLE IF NOT EXISTS workout_progress (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    workout_id INT NOT NULL,
    duration_minutes INT NOT NULL,
    completed BOOLEAN DEFAULT TRUE,
    completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_progress_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_progress_workout FOREIGN KEY (workout_id) REFERENCES workouts(id)
);

INSERT INTO workouts (name, duration)
SELECT 'Push-ups', 15 WHERE NOT EXISTS (SELECT 1 FROM workouts WHERE name='Push-ups');
INSERT INTO workouts (name, duration)
SELECT 'Squats', 10 WHERE NOT EXISTS (SELECT 1 FROM workouts WHERE name='Squats');
INSERT INTO workouts (name, duration)
SELECT 'Plank', 5 WHERE NOT EXISTS (SELECT 1 FROM workouts WHERE name='Plank');
INSERT INTO workouts (name, duration)
SELECT 'Jumping Jacks', 5 WHERE NOT EXISTS (SELECT 1 FROM workouts WHERE name='Jumping Jacks');
INSERT INTO workouts (name, duration)
SELECT 'Lunges', 8 WHERE NOT EXISTS (SELECT 1 FROM workouts WHERE name='Lunges');
