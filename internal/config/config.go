package config

import (
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port string

	MasterDBHost     string
	MasterDBPort     string
	MasterDBName     string
	MasterDBUser     string
	MasterDBPassword string

	OmnichannelURL string

	RedisAddr     string
	RedisPassword string

	JWTSecret               string
	JWTAccessExpirySeconds  int
	JWTRefreshExpirySeconds int

	// Tenant pool expiry duration in minutes (default 30 min)
	TenantPoolExpiryMinutes int
}

func Load() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file found, reading from environment")
	}

	return &Config{
		Port: getEnv("PORT", "8080"),

		MasterDBHost:     getEnv("MASTER_DB_HOST", "localhost"),
		MasterDBPort:     getEnv("MASTER_DB_PORT", "5432"),
		MasterDBName:     getEnv("MASTER_DB_NAME", ""),
		MasterDBUser:     getEnv("MASTER_DB_USER", "postgres"),
		MasterDBPassword: getEnv("MASTER_DB_PASSWORD", ""),

		OmnichannelURL: getEnv("OMNICHANNEL_URL", "http://localhost:8001"),

		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),

		JWTSecret:               getEnv("JWT_SECRET", ""),
		JWTAccessExpirySeconds:  getEnvInt("JWT_ACCESS_EXPIRY_SECONDS", 900),
		JWTRefreshExpirySeconds: getEnvInt("JWT_REFRESH_EXPIRY_SECONDS", 604800),
		TenantPoolExpiryMinutes: getEnvInt("TENANT_POOL_EXPIRY_MINUTES", 30),
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	n, err := strconv.Atoi(val)
	if err != nil {
		return fallback
	}
	return n
}
