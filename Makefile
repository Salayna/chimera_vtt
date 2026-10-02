# Supabase config for the app, relative to app/. Override for a hosted
# project: make web CONFIG=config/prod.json
CONFIG ?= config/local.json
DEFINES = --dart-define-from-file=$(CONFIG)
# 8080 is taken locally.
PORT ?= 8765

.PHONY: up down macos web web-prod serve bench loopback test test-live analyze

up:                       ## start the local Supabase stack
	supabase start

down:
	supabase stop

macos:                    ## GM on desktop
	cd app && flutter run -d macos $(DEFINES)

web:                      ## build the web app, with DOM semantics for automation
	cd app && flutter build web $(DEFINES) --dart-define=SEMANTICS=true

web-prod:                 ## release web build against config/prod.json, for hosting
	cd app && flutter build web --release --dart-define-from-file=config/prod.json

serve: web                ## GM at localhost:$(PORT), player at 127.0.0.1:$(PORT)
	cd app/build/web && python3 -m http.server $(PORT)

bench:                    ## render benchmark, offline
	cd app && flutter run --profile -d macos --dart-define=BENCH=true

loopback:                 ## GM and player side by side, offline
	cd app && flutter run -d macos --dart-define=LOOPBACK=true

test:
	cd packages/chimera_core && dart test
	cd packages/tactical_engine && dart test
	cd packages/chimera_sync && dart test
	cd app && flutter test

test-live:                ## H2: SupabaseTransport against the stack in CONFIG
	cd packages/chimera_sync && \
	  eval $$(python3 -c 'import json;c=json.load(open("../../app/$(CONFIG)"));print(" ".join(f"export {k}={v}" for k,v in c.items()))') && \
	  dart test test/supabase_test.dart

analyze:
	flutter analyze
