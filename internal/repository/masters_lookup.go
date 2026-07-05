package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// existsByID checks whether a single row with the given id exists in table.
// table must be a trusted, hardcoded identifier — never user input.
func existsByID(ctx context.Context, pool *pgxpool.Pool, table, id string) (bool, error) {
	var ok bool
	err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT EXISTS(SELECT 1 FROM %s WHERE id = $1::uuid)`, table), id).Scan(&ok)
	if err != nil {
		return false, fmt.Errorf("failed to validate %s: %w", table, err)
	}
	return ok, nil
}

// countByIDs returns how many of the given ids actually exist in table.
// table must be a trusted, hardcoded identifier — never user input.
func countByIDs(ctx context.Context, pool *pgxpool.Pool, table string, ids []string) (int, error) {
	var count int
	err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM %s WHERE id = ANY($1::uuid[])`, table), ids).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("failed to validate %s: %w", table, err)
	}
	return count, nil
}

// getIDByName resolves a single row's id by case-insensitive exact name match.
// Used to resolve human-readable bulk-upload columns (e.g. "Class 6") to ids.
func getIDByName(ctx context.Context, pool *pgxpool.Pool, table, name string) (string, bool, error) {
	var id string
	err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT id::text FROM %s WHERE LOWER(name) = LOWER($1)`, table), name).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("failed to look up %s by name: %w", table, err)
	}
	return id, true, nil
}
