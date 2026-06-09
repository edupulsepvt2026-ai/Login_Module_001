package main

import (
	"crypto/tls"
	"fmt"
	"loginmodule_99/apigateway"
	"loginmodule_99/db"
	"loginmodule_99/router"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"
	"os"

	"github.com/joho/godotenv"
)

func main() {
	// ── 0. Load local env files (local dev). In production set env vars directly.
	_ = godotenv.Load(".env")
	_ = godotenv.Load("env")

	// ── 1. Load configuration from toml/ directory ────────────────────────
	cfg, err := tomlloader.Load("toml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	// ── 2. Initialise logger (writes to logs/app.log + stdout) ───────────
	log, err := util.NewLogger(cfg.App.Log.File)
	if err != nil {
		fmt.Fprintf(os.Stderr, "logger init error: %v\n", err)
		os.Exit(1)
	}
	defer log.Close()

	log.Info("=== %s v%s starting (env=%s) ===",
		cfg.App.App.Name, cfg.App.App.Version, cfg.App.App.Env)

	// ── 3. Connect to MSSQL ───────────────────────────────────────────────
	if err := db.Init(cfg.DB.Database, log); err != nil {
		log.Warn("MSSQL unavailable, continuing without DB: %v", err)
	} else {
		defer db.Close()
		log.Info("MSSQL database ready")
	}

	// ── 3a. Connect to master PostgreSQL (pgxpool) ────────────────────────
	if err := db.InitMaster(cfg.Postgres.MasterDB, log); err != nil {
		log.Fatal("master postgres unavailable: %v", err)
	}
	defer db.CloseMaster()

	// ── 3b. Init tenant pool manager ──────────────────────────────────────
	db.InitTenantManager(db.GetMaster(), log)
	defer db.Manager.CloseAll()

	// ── 4. Build TLS Configuration ────────────────────────────────────────
	var tlsConfig *tls.Config
	if cfg.App.Server.TLS.Enabled {
		log.Info("TLS is enabled. Checking certificate files...")
		certFile := cfg.App.Server.TLS.CertFile
		keyFile := cfg.App.Server.TLS.KeyFile

		// Auto-generate self-signed cert if files don't exist
		_, certErr := os.Stat(certFile)
		_, keyErr := os.Stat(keyFile)
		if os.IsNotExist(certErr) || os.IsNotExist(keyErr) {
			log.Info("Certificate or key files not found. Auto-generating self-signed certificate...")
			if err := util.GenerateSelfSignedCert(certFile, keyFile); err != nil {
				log.Fatal("failed to generate self-signed cert: %v", err)
			}
			log.Info("Self-signed certificate generated at %s and %s", certFile, keyFile)
		}

		// Load certificates
		cert, err := tls.LoadX509KeyPair(certFile, keyFile)
		if err != nil {
			log.Fatal("failed to load TLS key pair: %v", err)
		}

		tlsConfig = &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS12,
		}
		log.Info("TLS configuration preloaded successfully")
	}

	// ── 5. Build router from routes.toml ──────────────────────────────────
	mux := router.New(cfg.Routes.Routes, log, db.Get(), db.GetMaster())

	// ── 6. Assemble and start API gateway ─────────────────────────────────
	addr := fmt.Sprintf("%s:%d", cfg.App.Server.Host, cfg.App.Server.Port)
	gw := apigateway.New(addr, mux, tlsConfig, log)

	if err := gw.Start(); err != nil {
		log.Fatal("gateway error: %v", err)
	}
}
