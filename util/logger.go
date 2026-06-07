// Package util provides shared helpers: logging, error formatting, and
// other small utilities used across all layers of the application.
package util

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Logger wraps the standard library logger with file + console output.
type Logger struct {
	*log.Logger
	file *os.File
}

// NewLogger opens (or creates) a log file and returns a Logger that
// writes to both the file and stdout simultaneously. Each run gets its own
// uniquely named log file so the current run does not overwrite prior logs.
func NewLogger(logFilePath string) (*Logger, error) {
	if logFilePath == "" {
		logFilePath = "logs/app.log"
	}

	if err := os.MkdirAll(filepath.Dir(logFilePath), 0o755); err != nil {
		return nil, fmt.Errorf("create log dir: %w", err)
	}

	base := filepath.Base(logFilePath)
	ext := filepath.Ext(base)
	name := strings.TrimSuffix(base, ext)
	uniqueName := fmt.Sprintf("%s-%s-%d%s",
		name,
		time.Now().Format("20060102_150405"),
		os.Getpid(),
		ext,
	)
	uniquePath := filepath.Join(filepath.Dir(logFilePath), uniqueName)

	f, err := os.OpenFile(uniquePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open log file: %w", err)
	}

	multi := io.MultiWriter(os.Stdout, f)
	l := log.New(multi, "", 0)

	return &Logger{Logger: l, file: f}, nil
}

// NewNamedLogger creates a logger that writes to <logName>.txt in the current directory.
func NewNamedLogger(logName string) (*Logger, error) {
	logFile := logName + ".txt"
	return NewLogger(logFile)
}

// Close flushes and closes the underlying log file.
func (l *Logger) Close() error {
	if l.file != nil {
		return l.file.Close()
	}
	return nil
}

// Info logs an informational message with timestamp.
func (l *Logger) Info(format string, args ...any) {
	l.Printf("[INFO]  %s %s", timestamp(), fmt.Sprintf(format, args...))
}

// Warn logs a warning message.
func (l *Logger) Warn(format string, args ...any) {
	l.Printf("[WARN]  %s %s", timestamp(), fmt.Sprintf(format, args...))
}

// Error logs an error message.
func (l *Logger) Error(format string, args ...any) {
	l.Printf("[ERROR] %s %s", timestamp(), fmt.Sprintf(format, args...))
}

// Fatal logs and then calls os.Exit(1).
func (l *Logger) Fatal(format string, args ...any) {
	l.Printf("[FATAL] %s %s", timestamp(), fmt.Sprintf(format, args...))
	os.Exit(1)
}

func timestamp() string {
	return time.Now().Format("2006-01-02 15:04:05")
}

// Must panics if err is non-nil. Use only during initialisation.
func Must(err error, msg string) {
	if err != nil {
		panic(fmt.Sprintf("%s: %v", msg, err))
	}
}

const PathParamsKey = "pathParams"

func PathParam(r *http.Request, key string) string {
	if params, ok := r.Context().Value(PathParamsKey).(map[string]string); ok {
		return params[key]
	}
	return ""
}
