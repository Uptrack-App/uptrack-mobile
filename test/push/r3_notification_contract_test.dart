import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';

/// R3 early slice: the shared Dart ↔ Kotlin notification contract.
///
/// A Dart foreground re-display that lands on a different channel (or a
/// different action identity) than the Kotlin background render would give the
/// user two channels and two different payloads for one alert. Nothing in the
/// type system can catch that across a language boundary, so this test parses
/// the Kotlin sources and compares them against the Dart constants.
void main() {
  final String receiver = _read('UptrackDataMessageReceiver.kt');
  final String channels = _read('UptrackNotificationChannels.kt');
  final String intents = _read('UptrackNotificationIntents.kt');

  group('severity → channel mapping is identical in Dart and Kotlin', () {
    test('every channel id is byte-for-byte identical', () {
      expect(_const(channels, 'P1'), PushChannelIds.p1);
      expect(_const(channels, 'P2'), PushChannelIds.p2);
      expect(_const(channels, 'P3'), PushChannelIds.p3);
      expect(_const(channels, 'FALLBACK'), PushChannelIds.fallback);
    });

    test('p1 high / p2 default / p3 low / unknown fallback', () {
      // The table the brief pins — deterministic, including the odd inputs.
      expect(PushSeverityChannels.idFor('p1'), PushChannelIds.p1);
      expect(PushSeverityChannels.idFor('p2'), PushChannelIds.p2);
      expect(PushSeverityChannels.idFor('p3'), PushChannelIds.p3);
      expect(PushSeverityChannels.idFor('info'), PushChannelIds.fallback);
      expect(PushSeverityChannels.idFor('p4'), PushChannelIds.fallback);
      expect(PushSeverityChannels.idFor(''), PushChannelIds.fallback);
      expect(PushSeverityChannels.idFor(null), PushChannelIds.fallback);
      expect(PushSeverityChannels.idFor(' SEV-1 '), PushChannelIds.fallback);
      // The same input is the same channel every time.
      expect(
        PushSeverityChannels.idFor('p1'),
        PushSeverityChannels.idFor('p1'),
      );

      // Same table, asserted against the Dart channel declarations.
      expect(
        PushSeverityChannels.specFor('p1').importance,
        PushChannelImportance.high,
      );
      expect(
        PushSeverityChannels.specFor('p2').importance,
        PushChannelImportance.standard,
      );
      expect(
        PushSeverityChannels.specFor('p3').importance,
        PushChannelImportance.low,
      );
      expect(
        PushSeverityChannels.specFor('info').importance,
        PushSeverityChannels.specFor('nonsense').importance,
        reason: 'unknown severity must be indistinguishable from info',
      );
      expect(PushSeverityChannels.isMapped('p3'), isTrue);
      expect(PushSeverityChannels.isMapped('info'), isFalse);
      expect(PushSeverityChannels.isMapped(null), isFalse);

      // …and the same table asserted against the Kotlin source text, resolved
      // through each branch's `const val` so this compares the channel id
      // Android sees, not a Kotlin identifier.
      expect(_armMap(_whenArms(channels, 'channelIdFor')), <String, String>{
        'p1': PushChannelIds.p1,
        'p2': PushChannelIds.p2,
        'p3': PushChannelIds.p3,
        'else': PushChannelIds.fallback,
      });
      expect(
        _normaliser(channels),
        'severity?.trim()?.lowercase()',
        reason: 'normalisation must be identical so the tables cannot diverge',
      );
      expect(PushSeverityChannels.normalize(' P1 '), 'p1');
    });

    test(
      'channel importances match the Kotlin NotificationManager constants',
      () {
        // `const val P1_IMPORTANCE = NotificationManager.IMPORTANCE_HIGH`
        expect(
          _const(channels, 'P1_IMPORTANCE'),
          'NotificationManager.IMPORTANCE_HIGH',
        );
        expect(
          _const(channels, 'P2_IMPORTANCE'),
          'NotificationManager.IMPORTANCE_DEFAULT',
        );
        expect(
          _const(channels, 'P3_IMPORTANCE'),
          'NotificationManager.IMPORTANCE_LOW',
        );
        expect(
          _const(channels, 'FALLBACK_IMPORTANCE'),
          'NotificationManager.IMPORTANCE_DEFAULT',
        );

        // The renderer must request the plugin enums with the same numeric
        // values as those constants, or Android downgrades the notification:
        // NotificationManager IMPORTANCE_HIGH/DEFAULT/LOW = 4/3/2.
        expect(
          FlutterLocalNotificationsNotifier.importanceFor(
            PushChannelImportance.high,
          ).value,
          4,
        );
        expect(
          FlutterLocalNotificationsNotifier.importanceFor(
            PushChannelImportance.standard,
          ).value,
          3,
        );
        expect(
          FlutterLocalNotificationsNotifier.importanceFor(
            PushChannelImportance.low,
          ).value,
          2,
        );
        // Notification priority agrees with the channel importance
        // (PRIORITY_HIGH/DEFAULT/LOW = 1/0/-1).
        expect(
          FlutterLocalNotificationsNotifier.priorityFor(
            PushChannelImportance.high,
          ).value,
          1,
        );
        expect(
          FlutterLocalNotificationsNotifier.priorityFor(
            PushChannelImportance.standard,
          ).value,
          0,
        );
        expect(
          FlutterLocalNotificationsNotifier.priorityFor(
            PushChannelImportance.low,
          ).value,
          -1,
        );
        // The Kotlin side must resolve the same table in `importanceForId` …
        expect(
          _armMap(_whenArms(channels, 'importanceForId')),
          <String, String>{
            PushChannelIds.p1: 'NotificationManager.IMPORTANCE_HIGH',
            PushChannelIds.p2: 'NotificationManager.IMPORTANCE_DEFAULT',
            PushChannelIds.p3: 'NotificationManager.IMPORTANCE_LOW',
            'else': 'NotificationManager.IMPORTANCE_DEFAULT',
          },
        );
        // … and must agree on the notification priority, too, or Android
        // silently downgrades the notification.
        expect(_armMap(_whenArms(channels, 'priorityFor')), <String, String>{
          PushChannelIds.p1: 'NotificationCompat.PRIORITY_HIGH',
          PushChannelIds.p3: 'NotificationCompat.PRIORITY_LOW',
          'else': 'NotificationCompat.PRIORITY_DEFAULT',
        }, reason: 'p2 and every unknown severity share the default priority');
      },
    );

    test('names and descriptions match so Settings reads the same on both', () {
      for (final MapEntry<String, PushChannelSpec> entry
          in PushSeverityChannels.specs.entries) {
        final String dartKey = _dartKeyForId(entry.key);
        expect(_const(channels, '${dartKey}_NAME'), entry.value.name);
        expect(
          _const(channels, '${dartKey}_DESCRIPTION'),
          entry.value.description,
        );
      }
      expect(
        PushSeverityChannels.specs[PushChannelIds.fallback]!.name,
        'Incident alerts',
      );
      expect(
        PushSeverityChannels.specs[PushChannelIds.fallback]!.description,
        'Incident and monitor alerts from Uptrack.',
      );
    });

    test('all published ids are declared in the same order on both sides', () {
      expect(PushChannelIds.all, <String>[
        'uptrack_p1',
        'uptrack_p2',
        'uptrack_p3',
        'incidents',
      ]);
      final RegExpMatch? match = RegExp(
        r'val ALL_IDS = listOf\(([^)]*)\)',
        dotAll: true,
      ).firstMatch(channels);
      expect(match, isNotNull, reason: 'ALL_IDS must stay parseable');
      final List<String> kotlinOrder = RegExp(r'([A-Z0-9_]+)')
          .allMatches(match!.group(1)!)
          .map((RegExpMatch m) => _const(channels, m.group(1)!))
          .toList();
      expect(kotlinOrder, PushChannelIds.all);
    });

    test('the fallback is the channel the backend still advertises', () {
      // `INCIDENTS_CHANNEL_ID` in crates/api/src/push_fcm.rs is "incidents";
      // the receiver's pre-R3 CHANNEL_ID must keep naming that same channel so
      // an unknown severity still finds a channel this app publishes.
      expect(
        RegExp(r'const val CHANNEL_ID = UptrackNotificationChannels\.FALLBACK')
            .hasMatch(receiver),
        isTrue,
      );
      expect(PushChannelIds.fallback, 'incidents');
    });
  });

  group('intent identity is identical in Dart and Kotlin', () {
    test('per-action intent actions and payload ids match', () {
      expect(
        _const(intents, 'ACK_ACTION'),
        PushIntentIdentity.acknowledgeAction,
      );
      expect(
        _const(intents, 'ESCALATE_ACTION'),
        PushIntentIdentity.escalateAction,
      );
      expect(_const(intents, 'SNOOZE_ACTION'), PushIntentIdentity.snoozeAction);
      expect(_const(intents, 'ACK'), PushIntentIdentity.acknowledge);
      expect(_const(intents, 'ESCALATE'), PushIntentIdentity.escalate);
      expect(_const(intents, 'SNOOZE'), PushIntentIdentity.snooze);
      expect(_const(intents, 'DATA_SCHEME'), PushIntentIdentity.dataScheme);
      expect(_const(intents, 'EXTRA_ACTION'), PushIntentIdentity.extraAction);
      expect(
        _const(intents, 'EXTRA_TARGET_KIND'),
        PushIntentIdentity.extraTargetKind,
      );
      expect(
        _const(intents, 'EXTRA_TARGET_ID'),
        PushIntentIdentity.extraTargetId,
      );
      expect(
        _const(intents, 'MAX_ID_LENGTH'),
        '${PushIntentIdentity.maxIdLength}',
      );
      expect(_const(intents, 'KIND_INCIDENT'), PushTargetKind.incident.wire);
      expect(_const(intents, 'KIND_MONITOR'), PushTargetKind.monitor.wire);
    });

    test('the body tap keeps ACTION_MAIN on both sides', () {
      // `Intent.ACTION_MAIN` *is* "android.intent.action.MAIN".
      expect(
        _const(intents, 'TAP_ACTION'),
        anyOf('Intent.ACTION_MAIN', 'android.intent.action.MAIN'),
      );
      expect(PushIntentIdentity.tapAction, 'android.intent.action.MAIN');
    });

    test('action button labels match the Dart renderer', () {
      expect(
        FlutterLocalNotificationsNotifier.androidActionsFor(
          const PushMessage(incidentId: 'inc-1'),
        ).map((dynamic action) => (action as dynamic).title).toList(),
        <String>[
          _const(intents, 'ACK_TITLE'),
          _const(intents, 'ESCALATE_TITLE'),
          _const(intents, 'SNOOZE_TITLE'),
        ],
      );
    });

    test('every PendingIntent is immutable', () {
      expect(
        RegExp(r'FLAG_UPDATE_CURRENT or PendingIntent\.FLAG_IMMUTABLE')
            .hasMatch(intents),
        isTrue,
      );
      expect(
        RegExp(r'PendingIntent\.getActivity\(').allMatches(intents).length,
        2,
        reason: 'one body-tap factory and one action factory, both immutable',
      );
      expect(
        RegExp(r'private const val FLAGS =').hasMatch(intents),
        isTrue,
        reason: 'the flag pair must be shared, not retyped per call',
      );
    });

    test('an action intent cannot be read as a body tap by MainActivity', () {
      // MainActivity reads exactly these two extras to build a tap payload.
      final String body = _functionBody(intents, 'actionIntent');
      expect(body, contains('putExtra(EXTRA_ACTION'));
      expect(body, contains('putExtra(EXTRA_TARGET_KIND'));
      expect(body, contains('putExtra(EXTRA_TARGET_ID'));
      expect(
        body,
        isNot(contains('EXTRA_INCIDENT_ID')),
        reason: 'an action intent must never carry a tap extra',
      );
      expect(
        body,
        isNot(contains('EXTRA_MONITOR_ID')),
        reason: 'an action intent must never carry a tap extra',
      );
      expect(
        body,
        isNot(contains('CATEGORY_LAUNCHER')),
        reason: 'only a body tap is a launcher launch',
      );
      expect(body, contains('data = Uri.parse(data)'));

      // …while the body tap still carries exactly those two extras.
      final String tapBody = _functionBody(intents, 'tapIntent');
      expect(
        tapBody,
        contains('putExtra(UptrackDataMessageReceiver.EXTRA_INCIDENT_ID'),
      );
      expect(
        tapBody,
        contains('putExtra(UptrackDataMessageReceiver.EXTRA_MONITOR_ID'),
      );
      expect(tapBody, contains('addCategory(Intent.CATEGORY_LAUNCHER)'));
      expect(tapBody, isNot(contains('putExtra(EXTRA_ACTION')));
    });

    test('identity is action + data, not extras and not the hash alone', () {
      final String ack1 = PushIntentIdentity.identity(
        PushIntentIdentity.acknowledgeAction,
        PushIntentIdentity.actionData(
          PushIntentIdentity.acknowledge,
          PushTargetKind.incident,
          'inc-1',
        ),
      );
      final String ack2 = PushIntentIdentity.identity(
        PushIntentIdentity.acknowledgeAction,
        PushIntentIdentity.actionData(
          PushIntentIdentity.acknowledge,
          PushTargetKind.incident,
          'inc-2',
        ),
      );
      final String tap1 = PushIntentIdentity.identity(
        PushIntentIdentity.tapAction,
        PushIntentIdentity.tapData('inc-1', null),
      );
      expect(
        ack1,
        'app.uptrack.mobile.UPTRACK_ACK|uptrack://push/action/incident/UPTRACK_ACK/inc-1',
      );
      expect(
        tap1,
        'android.intent.action.MAIN|uptrack://push/tap/incident/inc-1',
      );
      // Same action, different incident → different identity and request code.
      expect(ack1, isNot(ack2));
      // Same incident, tap vs action → still different identity.
      expect(ack1, isNot(tap1));
      expect(
        PushIntentIdentity.requestCode(ack1),
        isNot(PushIntentIdentity.requestCode(ack2)),
      );
      expect(
        PushIntentIdentity.requestCode(ack1),
        PushIntentIdentity.requestCode(ack1),
        reason: 'a repeat alert for one incident must reuse its intent',
      );
      // Every action has its own intent action, so no two can collide.
      // `intentActionForAction` is total-but-nullable, so the set is nullable.
      final Set<String?> actions = PushIntentIdentity.actionIds
          .map((String id) => PushIntentIdentity.intentActionForAction(id))
          .toSet();
      expect(actions, hasLength(3));
      expect(actions, isNot(contains(PushIntentIdentity.tapAction)));

      // The Kotlin side builds the same URIs and the same request code.
      expect(
        RegExp(
          r'fun actionData\(action: String, kind: String, targetId: String\?\)',
        ).hasMatch(intents),
        isTrue,
      );
      expect(
        RegExp(r'"\$DATA_SCHEME://push/action/\$kind/\$action/\$safeTarget"')
            .hasMatch(intents),
        isTrue,
      );
      expect(
        RegExp(r'"\$DATA_SCHEME://push/tap/\$KIND_INCIDENT/\$incident"')
            .hasMatch(intents),
        isTrue,
      );
      expect(
        _functionBody(intents, 'requestCode'),
        'identity.hashCode() and 0x7fffffff',
        reason: 'same formula on both sides',
      );
      expect(
        _functionBody(intents, 'identity'),
        contains('"\$intentAction|\$data"'),
      );
    });

    test('ids are sanitized identically and rejected, never rewritten', () {
      expect(PushIntentIdentity.sanitizeId('inc-1'), 'inc-1');
      expect(PushIntentIdentity.sanitizeId('  inc.1_b  '), 'inc.1_b');
      expect(PushIntentIdentity.sanitizeId('inc 1'), isNull);
      expect(PushIntentIdentity.sanitizeId('inc/1'), isNull);
      expect(PushIntentIdentity.sanitizeId('inc\n1'), isNull);
      expect(PushIntentIdentity.sanitizeId('inc?x=1'), isNull);
      expect(PushIntentIdentity.sanitizeId('inc#1'), isNull);
      expect(PushIntentIdentity.sanitizeId(''), isNull);
      expect(PushIntentIdentity.sanitizeId('   '), isNull);
      expect(PushIntentIdentity.sanitizeId(null), isNull);
      expect(
        PushIntentIdentity.sanitizeId(
          'x' * (PushIntentIdentity.maxIdLength + 1),
        ),
        isNull,
      );
      expect(
        PushIntentIdentity.sanitizeId('x' * PushIntentIdentity.maxIdLength),
        hasLength(PushIntentIdentity.maxIdLength),
      );
      // No id → no URI at all (never a URI with an empty segment).
      expect(PushIntentIdentity.tapData(null, null), isNull);
      expect(PushIntentIdentity.tapData('bad id', 'also bad'), isNull);
      expect(
        PushIntentIdentity.actionData(
          PushIntentIdentity.acknowledge,
          PushTargetKind.incident,
          null,
        ),
        isNull,
      );

      // Same rules in Kotlin.
      final String body = _functionBody(intents, 'sanitizeId');
      expect(body, contains("char == '-' || char == '_' || char == '.'"));
      expect(body, contains('trimmed.length > MAX_ID_LENGTH'));
      expect(body, contains('if (!ok) return null'));
    });

    test('action targets are the same three-or-one set on both sides', () {
      expect(
        FlutterLocalNotificationsNotifier.androidActionsFor(
          const PushMessage(incidentId: 'inc-1', monitorId: 'mon-1'),
        ).map((dynamic action) => (action as dynamic).id).toList(),
        PushIntentIdentity.actionIds,
        reason: 'an incident target offers all three, in the shared order',
      );
      expect(
        FlutterLocalNotificationsNotifier.androidActionsFor(
          const PushMessage(monitorId: 'mon-1'),
        ).map((dynamic action) => (action as dynamic).id).toList(),
        <String>[PushIntentIdentity.snooze],
        reason: 'monitor-only alerts offer only the monitor-scoped action',
      );
      expect(
        FlutterLocalNotificationsNotifier.androidActionsFor(
          const PushMessage(title: 'no target'),
        ),
        isEmpty,
      );
      expect(
        FlutterLocalNotificationsNotifier.androidActionsFor(
          const PushMessage(incidentId: 'inc 1'),
        ),
        isEmpty,
        reason: 'an unsanitizable id is not an action target',
      );
      final String body = _functionBody(intents, 'actionTargets');
      expect(body, contains('ActionTarget(ACK, KIND_INCIDENT, incident)'));
      expect(body, contains('ActionTarget(ESCALATE, KIND_INCIDENT, incident)'));
      expect(body, contains('ActionTarget(SNOOZE, KIND_INCIDENT, incident)'));
      expect(body, contains('ActionTarget(SNOOZE, KIND_MONITOR, monitor)'));
    });
  });

  group('no DND claim, no premature execution, no token', () {
    test('neither side asks to bypass Do Not Disturb', () {
      for (final String source in <String>[channels, intents, receiver]) {
        // Scanned with comments removed: all three sources *document* that they
        // never call `setBypassDnd`, and that prose must not read as a call.
        final String code = _code(source);
        expect(
          RegExp('setBypassDnd', caseSensitive: false).hasMatch(code),
          isFalse,
        );
        expect(
          RegExp(
            r'channelBypassDnd\s*[=:]\s*true',
            caseSensitive: false,
          ).hasMatch(code),
          isFalse,
        );
        expect(
          RegExp('setFullScreenIntent', caseSensitive: false).hasMatch(code),
          isFalse,
        );
        expect(
          RegExp('IMPORTANCE_NONE', caseSensitive: false).hasMatch(code),
          isFalse,
        );
      }
    });

    test(
      'channel creation never deletes, recreates, or silences a channel',
      () {
        final String body = _functionBody(channels, 'ensure');
        expect(
          body,
          contains('getNotificationChannel(id) != null) return'),
          reason: 'an existing (user-owned) channel must be left alone',
        );
        // Name/description/importance are only ever read from the spec table —
        // importance is the NotificationChannel constructor argument, and is
        // never assigned afterwards (which Android would ignore anyway).
        expect(
          RegExp(
            r'NotificationChannel\(spec\.id, spec\.name, spec\.importance\)',
          ).hasMatch(body),
          isTrue,
        );
        expect(body, contains('description = spec.description'));
        expect(_code(channels), isNot(contains('deleteNotificationChannel')));
      },
    );

    test('the receiver fires no request and has no API surface', () {
      final String code = _code(receiver);
      for (final String forbidden in <String>[
        'HttpURLConnection',
        'okhttp',
        'OkHttpClient',
        'java.net.URL',
        'UptrackApi',
        'goAsync',
        'registerDevice',
      ]) {
        expect(
          code,
          isNot(contains(forbidden)),
          reason:
              'a lock-screen tap must not reach the network from the receiver',
        );
      }
      // Every action goes through the immutable, identity-carrying factory —
      // there is no second way to build an action intent here.
      expect(receiver, contains('UptrackNotificationIntents.actionIntent('));
      expect(receiver, contains('UptrackNotificationIntents.tapIntent('));
      expect(
        RegExp(r'PendingIntent\.').hasMatch(code),
        isFalse,
        reason: 'the receiver must not build intents itself',
      );
    });

    test('no token or alert text reaches an intent', () {
      expect(_code(intents), isNot(contains('EXTRA_TOKEN')));
      expect(_code(receiver), isNot(contains('EXTRA_TOKEN')));
      final String tapBody = _functionBody(intents, 'tapIntent');
      final String actionBody = _functionBody(intents, 'actionIntent');
      for (final String body in <String>[tapBody, actionBody]) {
        expect(body, isNot(contains('EXTRA_TITLE')));
        expect(body, isNot(contains('EXTRA_BODY')));
      }
      expect(
        PushIntentIdentity.actionExtras(
          action: PushIntentIdentity.acknowledge,
          kind: PushTargetKind.incident,
          targetId: 'inc-1',
        ).keys.toSet(),
        <String>{
          PushIntentIdentity.extraAction,
          PushIntentIdentity.extraTargetKind,
          PushIntentIdentity.extraTargetId,
        },
      );
      // An unusable target drops the id rather than sending an empty one.
      expect(
        PushIntentIdentity.actionExtras(
          action: PushIntentIdentity.snooze,
          kind: PushTargetKind.monitor,
          targetId: 'bad id',
        ).keys,
        <String>{
          PushIntentIdentity.extraAction,
          PushIntentIdentity.extraTargetKind,
        },
      );
    });
  });
}

/// `const val NAME = "literal"` (or `= NotificationManager.CONST`) in Kotlin.
String _const(String source, String name) {
  final RegExpMatch? match = RegExp('const val $name = ([^\\n]+)')
      .firstMatch(source);
  if (match == null) {
    throw StateError('no `const val $name` in the Kotlin source');
  }
  final String raw = match.group(1)!.trim();
  if (raw.startsWith('"') && raw.endsWith('"')) {
    return raw.substring(1, raw.length - 1);
  }
  return raw;
}

/// The `X_NAME` / `X_DESCRIPTION` prefix Kotlin uses for a channel id.
String _dartKeyForId(String id) {
  return switch (id) {
    PushChannelIds.p1 => 'P1',
    PushChannelIds.p2 => 'P2',
    PushChannelIds.p3 => 'P3',
    _ => 'FALLBACK',
  };
}

/// One arm of a Kotlin `when`: a `key -> value` pair, both sides resolved.
typedef _Arm = ({String key, String value});

/// Every arm of the `when` inside `fun <function>(…)`, in source order.
///
/// A constant identifier on either side (`P1`, `FALLBACK_IMPORTANCE`) is
/// resolved to its `const val`, so the assertions below compare the channel id
/// and importance **value** Android actually sees rather than a Kotlin name: a
/// renamed constant still matches, a changed value does not. A quoted literal
/// (`"p1"`, `else`) and an external reference
/// (`NotificationCompat.PRIORITY_HIGH`) are kept verbatim.
List<_Arm> _whenArms(String source, String function) {
  final RegExp pattern = RegExp(
    r'((?:"[^"]*")|(?:else)|(?:\b[A-Z][A-Z0-9_]*))\s*->\s*'
    r'((?:[A-Za-z][A-Za-z0-9_]*\.[A-Za-z][A-Za-z0-9_]*)|(?:\b[A-Z][A-Z0-9_]*))',
  );
  return <_Arm>[
    for (final RegExpMatch arm in pattern.allMatches(
      _functionBody(source, function),
    ))
      (
        key: _armToken(source, arm.group(1)!),
        value: _armToken(source, arm.group(2)!),
      ),
  ];
}

/// [arms] as a map, refusing a duplicate key — a duplicated arm is itself drift.
Map<String, String> _armMap(List<_Arm> arms) {
  final Map<String, String> map = <String, String>{};
  for (final _Arm arm in arms) {
    if (map.containsKey(arm.key)) {
      throw StateError('duplicate `when` arm for "${arm.key}"');
    }
    map[arm.key] = arm.value;
  }
  return map;
}

/// One side of a `when` arm: a quoted literal verbatim, a `const val` resolved
/// to its value, anything else (an external constant reference) verbatim.
String _armToken(String source, String token) {
  if (token.startsWith('"') && token.endsWith('"')) {
    return token.substring(1, token.length - 1);
  }
  if (token.contains('.')) {
    return token;
  }
  final RegExpMatch? declared = RegExp('const val $token = ([^\\n]+)')
      .firstMatch(source);
  if (declared == null) {
    return token;
  }
  return declared.group(1)!.trim().replaceAll('"', '');
}

/// The normaliser expression inside Kotlin's [channelIdFor].
String _normaliser(String source) {
  final RegExpMatch? match = RegExp(
    r'fun channelIdFor\(severity: String\?\): String = when \((.+?)\) \{',
  ).firstMatch(source);
  return match?.group(1)?.trim() ?? '';
}

/// Body of one Kotlin function, for structural checks.
///
/// Handles both shapes used in this slice: a braced block body and an
/// expression body (`= expr`, and `= when (...) { … }`). Naive brace balancing
/// silently returns the *next* function's body for a braceless expression body,
/// which would make an assertion about `requestCode` actually assert something
/// about `actionTargets` — so the parameter list is skipped first and the body
/// is classified from what follows it.
String _functionBody(String source, String function) {
  final RegExpMatch? header = RegExp('fun $function\\(').firstMatch(source);
  if (header == null) {
    throw StateError('no `fun $function` in the Kotlin source');
  }
  // Skip the parameter list, which may span several lines.
  int depth = 0;
  int i = header.end - 1; // the '('
  for (; i < source.length; i++) {
    if (source[i] == '(') {
      depth++;
    } else if (source[i] == ')' && --depth == 0) {
      break;
    }
  }
  // Then walk to the first `=` (expression body) or `{` (block body).
  int j = i + 1;
  while (j < source.length && source[j] != '=' && source[j] != '{') {
    j++;
  }
  if (j >= source.length) {
    throw StateError('no body in `fun $function`');
  }
  if (source[j] == '{') {
    return _braced(source, j);
  }
  final int lineEnd = source.indexOf('\n', j);
  final int end = lineEnd == -1 ? source.length : lineEnd;
  final int brace = source.substring(j, end).indexOf('{');
  // `= when (...) { … }` is still a braced block.
  if (brace != -1) {
    return _braced(source, j + brace);
  }
  return source.substring(j + 1, end).trim();
}

/// Balanced `{ … }` starting at the brace at [start], excluding both braces.
String _braced(String source, int start) {
  int depth = 0;
  for (int i = start; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(start + 1, i);
      }
    }
  }
  throw StateError('unbalanced braces at offset $start');
}

/// [source] with `//` and `/* … */` comments removed, so an "is this absent?"
/// assertion is decided by code and not by prose in a KDoc — these sources
/// document what they deliberately do *not* do, which would otherwise read as a
/// violation of its own doc.
String _code(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _read(String name) =>
    File('android/app/src/main/kotlin/app/uptrack/uptrack_mobile/$name')
        .readAsStringSync();
