#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP_NAME="ActionBar"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/$APP_NAME.app"

"$ROOT_DIR/scripts/build-app.sh" release

mkdir -p "$DESTINATION_DIR"
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

echo "Installed $DESTINATION_APP"
