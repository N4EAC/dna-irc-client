#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/module-cache
sed '/^class CRTView/,$d' Sources/DNA/main.swift > .build/IRCChecks.swift
cat Tests/irc-checks.swift >> .build/IRCChecks.swift
swiftc -module-cache-path .build/module-cache .build/IRCChecks.swift -o .build/irc-checks
.build/irc-checks

sed '/^let app = NSApplication.shared/,$d' Sources/DNA/main.swift > .build/MenuChecks.swift
cat Tests/menu-checks.swift >> .build/MenuChecks.swift
swiftc -module-cache-path .build/module-cache .build/MenuChecks.swift -o .build/menu-checks
.build/menu-checks
