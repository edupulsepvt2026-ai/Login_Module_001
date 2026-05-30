// Package tomlloader reads and parses all TOML configuration files
// from the toml/ directory and exposes typed config structs.
package tomlloader

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// AppConfig holds top-level application settings.
type AppConfig struct {
	App    AppSection    `toml:"app"`
	Server ServerSection `toml:"server"`
	Log    LogSection    `toml:"log"`
}

type AppSection struct {
	Name    string `toml:"name"`
	Version string `toml:"version"`
	Env     string `toml:"env"`
}

type ServerSection struct {
	Host string     `toml:"host"`
	Port int        `toml:"port"`
	TLS  TLSSection `toml:"tls"`
}

type TLSSection struct {
	Enabled  bool   `toml:"enabled"`
	CertFile string `toml:"cert_file"`
	KeyFile  string `toml:"key_file"`
}

type LogSection struct {
	File  string `toml:"file"`
	Level string `toml:"level"`
}

// DBConfig holds MSSQL connection settings.
type DBConfig struct {
	Database DBSection `toml:"database"`
}

type DBSection struct {
	Server          string `toml:"server"`
	Port            int    `toml:"port"`
	Name            string `toml:"name"`
	User            string `toml:"user"`
	Password        string `toml:"password"`
	Timeout         int    `toml:"timeout"`
	Encrypt         bool   `toml:"encrypt"`
	MaxOpenConns    int    `toml:"max_open_conns"`
	MaxIdleConns    int    `toml:"max_idle_conns"`
	MaxLifetimeMins int    `toml:"max_lifetime_mins"`
	MaxIdleTimeMins int    `toml:"max_idle_time_mins"`
}

// RouteEntry represents a single route declaration.
type RouteEntry struct {
	Path    string `toml:"path"`
	Method  string `toml:"method"`
	Handler string `toml:"handler"`
}

// RoutesConfig holds all route declarations.
type RoutesConfig struct {
	Routes []RouteEntry `toml:"routes"`
}

// Config aggregates all parsed configurations.
type Config struct {
	App    AppConfig
	DB     DBConfig
	Routes RoutesConfig
}

// Load reads all TOML files from the given directory and returns a Config.
func Load(dir string) (*Config, error) {
	cfg := &Config{}

	if err := loadFile(filepath.Join(dir, "app.toml"), &cfg.App); err != nil {
		return nil, fmt.Errorf("app.toml: %w", err)
	}
	if err := loadFile(filepath.Join(dir, "database.toml"), &cfg.DB); err != nil {
		return nil, fmt.Errorf("database.toml: %w", err)
	}
	if err := loadFile(filepath.Join(dir, "routes.toml"), &cfg.Routes); err != nil {
		return nil, fmt.Errorf("routes.toml: %w", err)
	}

	return cfg, nil
}

func loadFile(path string, v any) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	if _, err := toml.NewDecoder(f).Decode(v); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}
