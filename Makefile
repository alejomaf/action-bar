APP_NAME := ActionBar

.PHONY: build run test app install

build:
	swift build

run:
	swift run $(APP_NAME)

test:
	swift test

app:
	./scripts/build-app.sh

install:
	./scripts/install-local.sh
