package repository

import (
	"context"
	"fmt"

	"auth-service/db"

	"github.com/jackc/pgx/v5/pgxpool"
)

// CoreSettingRepository handles tenant database credential lookup from master infrastructure table.
type CoreSettingRepository struct {
	masterDB *pgxpool.Pool
}

// NewCoreSettingRepository creates a new repository for tenant connection metadata.
func NewCoreSettingRepository(masterDB *pgxpool.Pool) *CoreSettingRepository {
	return &CoreSettingRepository{
		masterDB: masterDB,
	}
}

// GetTenantCredentials fetches tenant DB credentials from infrastructure.chain_database by chain_id.
func (r *CoreSettingRepository) GetTenantCredentials(ctx context.Context, mid string) (db.TenantDBCredentials, error) {
	query := `
		SELECT db_host, db_port, db_name, db_user,
		       db_password_encrypted, ssl_mode,
		       max_conns, min_conns, connect_timeout_secs
		FROM infrastructure.chain_database
		WHERE chain_id = $1 AND is_active = true
		LIMIT 1
	`

	var creds db.TenantDBCredentials
	var dbPort int32
	var maxConns int32
	var minConns int32
	var connectTimeoutSecs int32
	var encryptedPassword string

	row := r.masterDB.QueryRow(ctx, query, mid)
	if err := row.Scan(
		&creds.Host,
		&dbPort,
		&creds.DBName,
		&creds.User,
		&encryptedPassword,
		&creds.SSLMode,
		&maxConns,
		&minConns,
		&connectTimeoutSecs,
	); err != nil {
		return db.TenantDBCredentials{}, fmt.Errorf("failed to fetch tenant credentials for chain_id %q: %w", mid, err)
	}

	creds.Port = fmt.Sprintf("%d", dbPort)
	creds.MaxConns = maxConns
	creds.MinConns = minConns
	creds.ConnectTimeoutSecs = connectTimeoutSecs

	password, err := decryptPassword(encryptedPassword)
	if err != nil {
		return db.TenantDBCredentials{}, fmt.Errorf("failed to decrypt tenant password for chain_id %q: %w", mid, err)
	}
	creds.Password = password

	if creds.Host == "" || creds.User == "" || creds.Password == "" || creds.DBName == "" {
		return db.TenantDBCredentials{}, fmt.Errorf("incomplete tenant credentials for chain_id %q", mid)
	}

	if creds.SSLMode == "" {
		creds.SSLMode = "require"
	}

	return creds, nil
}

func decryptPassword(encrypted string) (string, error) {
	if encrypted == "" {
		return "", fmt.Errorf("tenant password value is empty")
	}
	// TODO: implement KMS decryption for db_password_encrypted.
	// For now, assume master DB stores the password in plaintext or already decrypted.
	return encrypted, nil
}

// GetAllTenantMids retrieves all active chain IDs from infrastructure.chain_database.
func (r *CoreSettingRepository) GetAllTenantMids(ctx context.Context) ([]string, error) {
	query := `
		SELECT chain_id::text FROM infrastructure.chain_database
		WHERE is_active = true
		ORDER BY chain_id
	`

	rows, err := r.masterDB.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch tenant chain ids: %w", err)
	}
	defer rows.Close()

	var mids []string
	for rows.Next() {
		var mid string
		if err := rows.Scan(&mid); err != nil {
			return nil, fmt.Errorf("failed to scan chain_id: %w", err)
		}
		mids = append(mids, mid)
	}

	return mids, rows.Err()
}
