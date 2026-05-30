APP     := goproject
BIN     := ./bin/$(APP)
TOMLDIR := toml
LOGDIR  := logs

.PHONY: all build run tidy clean

all: build

## Download deps and tidy go.sum
tidy:
	go mod tidy

## Compile the binary into bin/
build: tidy
	@mkdir -p bin $(LOGDIR)
	go build -o $(BIN) ./...
	@echo "✓ built $(BIN)"

## Run directly (no binary)
run:
	@mkdir -p $(LOGDIR)
	go run main.go

## Remove compiled artifacts
clean:
	rm -rf bin $(LOGDIR)
