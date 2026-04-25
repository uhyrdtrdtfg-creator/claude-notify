.PHONY: build run test fmt lint tidy clean

BIN := bin/claude-notify

build: tidy
	go build -o $(BIN) .

run:
	go run .

test:
	go test -race -count=1 ./...

fmt:
	gofmt -s -w .

lint: fmt
	go vet ./...

tidy:
	go mod tidy

clean:
	rm -rf bin/

install: build
	install -m 0755 $(BIN) /usr/local/bin/claude-notify
