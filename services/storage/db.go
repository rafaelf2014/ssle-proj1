package main

import (
	"database/sql"
	"time"

	_ "modernc.org/sqlite"
)

type Reading struct {
	ID          int64     `json:"id"`
	DeviceID    string    `json:"device_id"`
	Temperature float64   `json:"temperature"`
	Timestamp   time.Time `json:"timestamp"`
}

type DB struct {
	sql *sql.DB
}

const schema = `
CREATE TABLE IF NOT EXISTS temperatures (
	id          INTEGER PRIMARY KEY AUTOINCREMENT,
	device_id   TEXT NOT NULL,
	temperature REAL NOT NULL,
	timestamp   TEXT NOT NULL
);`

func OpenDB(dsn string) (*DB, error) {
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	if _, err := conn.Exec(schema); err != nil {
		conn.Close()
		return nil, err
	}
	return &DB{sql: conn}, nil
}

func (d *DB) Close() error { return d.sql.Close() }

func (d *DB) Store(deviceID string, temp float64) error {
	_, err := d.sql.Exec(
		`INSERT INTO temperatures (device_id, temperature, timestamp) VALUES (?, ?, ?)`,
		deviceID, temp, time.Now().UTC().Format(time.RFC3339Nano),
	)
	return err
}

// most recent readings, optionally just one device
func (d *DB) Query(deviceID string, limit int) ([]Reading, error) {
	if limit <= 0 {
		limit = 100
	}
	q := `SELECT id, device_id, temperature, timestamp FROM temperatures`
	args := []any{}
	if deviceID != "" {
		q += ` WHERE device_id = ?`
		args = append(args, deviceID)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)

	rows, err := d.sql.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Reading
	for rows.Next() {
		var r Reading
		var ts string
		if err := rows.Scan(&r.ID, &r.DeviceID, &r.Temperature, &ts); err != nil {
			return nil, err
		}
		r.Timestamp, _ = time.Parse(time.RFC3339Nano, ts)
		out = append(out, r)
	}
	return out, rows.Err()
}
