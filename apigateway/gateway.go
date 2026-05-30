// Package apigateway assembles the HTTP server: it chains middleware,
// attaches the router, and manages graceful shutdown on OS signals.
package apigateway

import (
	"context"
	"crypto/tls"
	"fmt"
	"loginmodule_99/middleware"
	"loginmodule_99/util"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Gateway holds the configured HTTP server.
type Gateway struct {
	server *http.Server
	log    *util.Logger
}

// New wraps handler with the standard middleware chain and returns a Gateway.
func New(addr string, handler http.Handler, tlsConfig *tls.Config, log *util.Logger) *Gateway {
	// Build middleware chain: RequestID → Logger → Recovery → handler
	chain := middleware.RequestID(
		middleware.Logger(log)(
			middleware.Recovery(log)(handler),
		),
	)

	return &Gateway{
		server: &http.Server{
			Addr:         addr,
			Handler:      chain,
			TLSConfig:    tlsConfig,
			ReadTimeout:  15 * time.Second,
			WriteTimeout: 15 * time.Second,
			IdleTimeout:  60 * time.Second,
		},
		log: log,
	}
}

// Start listens on the configured address and blocks until an OS signal
// (SIGINT / SIGTERM) triggers a graceful 10-second shutdown window.
func (g *Gateway) Start() error {
	errCh := make(chan error, 1)

	go func() {
		if g.server.TLSConfig != nil {
			g.log.Info("API gateway listening securely (HTTPS) on https://%s", g.server.Addr)
			if err := g.server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
				errCh <- fmt.Errorf("ListenAndServeTLS: %w", err)
			}
		} else {
			g.log.Info("API gateway listening on http://%s", g.server.Addr)
			if err := g.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				errCh <- fmt.Errorf("ListenAndServe: %w", err)
			}
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-errCh:
		return err
	case sig := <-quit:
		g.log.Info("received signal %s, shutting down…", sig)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := g.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}

	g.log.Info("server stopped cleanly")
	return nil
}
