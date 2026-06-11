package db

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5/pgxpool"
)

func ConnectMaster(dsn string) *pgxpool.Pool {
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatalf("unable to connect to master DB: %v", err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		log.Fatalf("master DB ping failed: %v", err)
	}

	log.Println("connected to master DB")
	return pool
}

func BuildDSN(host, port, user, password, dbname string) string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=disable",
		user, password, host, port, dbname,
	)
}
