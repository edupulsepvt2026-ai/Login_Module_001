// Package response provides standard JSON response helpers.
package response

import (
	"encoding/json"
	"net/http"
)

type successEnvelope struct {
	Success bool `json:"success"`
	Data    any  `json:"data"`
}

type errorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type errorEnvelope struct {
	Success bool        `json:"success"`
	Error   errorDetail `json:"error"`
}

// OK writes a 200 JSON response: { "success": true, "data": ... }
func OK(w http.ResponseWriter, data any) {
	write(w, http.StatusOK, successEnvelope{Success: true, Data: data})
}

// Created writes a 201 JSON response.
func Created(w http.ResponseWriter, data any) {
	write(w, http.StatusCreated, successEnvelope{Success: true, Data: data})
}

// Err writes an error JSON response with the given HTTP status.
func Err(w http.ResponseWriter, status int, code, message string) {
	write(w, status, errorEnvelope{
		Success: false,
		Error:   errorDetail{Code: code, Message: message},
	})
}

func write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
