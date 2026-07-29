#!/usr/bin/env bash
#
# Run the platform-independent logic checks.
#
# The markdown parser, the SVG path parser and the duration formatting do not
# touch UIKit, so they compile and run against the macOS SDK — no Xcode, no
# simulator. That makes them the fast check to run on every change; the rest of
# the app needs a real iOS build.
#
# Usage: ./scripts/run-logic-tests.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O \
  "$ROOT/Tests/LogicTests/main.swift" \
  "$ROOT/OffiCraft/Markdown/MarkdownParser.swift" \
  "$ROOT/OffiCraft/Design/SVGPath.swift" \
  "$ROOT/OffiCraft/Design/Formatters.swift" \
  "$ROOT/OffiCraft/Models/UsageWindow.swift" \
  "$ROOT/OffiCraft/Models/StudioSettings.swift" \
  "$ROOT/OffiCraft/Models/ReplyCardTone.swift" \
  "$ROOT/OffiCraft/Models/HandledReplyCardsPolicy.swift" \
  "$ROOT/OffiCraft/Features/Office/RosterUnread.swift" \
  "$ROOT/OffiCraft/Features/Asks/AskOptionLayout.swift" \
  "$ROOT/OffiCraft/Features/Office/ChatLane.swift" \
  "$ROOT/OffiCraft/Features/Office/ChatMessageClamp.swift" \
  -o "$OUT/logic-tests"

"$OUT/logic-tests"
