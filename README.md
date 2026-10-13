# Uptrack Mobile

Uptrack Mobile is the Flutter app for monitoring services and responding to incidents on iOS and Android; see the [mobile app plan](../uptrack-spec/docs/mobile/mobile-app-plan.md).

The [Ink mobile contract](../uptrack-spec/docs/mobile/design-system.md), [component inventory](../uptrack-spec/docs/mobile/design-components.md) and [validation ledger](../uptrack-spec/docs/mobile/design-validation.md) describe the shared web/mobile identity and separate implementation from native acceptance.

## Shared tokens

From this directory, generate or verify Flutter, Android widget and iOS widget colors using the canonical web JSON:

```sh
dart run tool/generate_tokens.dart
dart run tool/generate_tokens.dart --check
```

An isolated mobile checkout uses the explicitly exported snapshot:

```sh
dart run tool/generate_tokens.dart --check --source design/shared.tokens.json
```

When shared colors change, update `uptrack-web/design/tokens.json`, copy it to `design/shared.tokens.json`, regenerate, and check both sources. CI uses the snapshot explicitly; local generation does not silently fall back when the canonical source is missing. Missing/invalid roles and missing/stale outputs fail. Generated files must not be edited or formatted independently. Web outputs remain owned by the web build.

## Offline component gallery

```sh
flutter run -t lib/design/gallery/main.dart
```

This separate developer entrypoint uses production components, supports light/dark and 200% text, and needs no account or backend. It is separate from the Android tester demo and is not a production route.

```sh
flutter analyze
flutter test
```

Native debug/simulator compilation and automated renderings do not establish physical-device, TalkBack/VoiceOver, widget extension, or store acceptance.
