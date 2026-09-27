import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/widgets/live_activity.dart';

void main() {
  group('LiveActivityEvent', () {
    test('round-trips the server aps.event names', () {
      expect(LiveActivityEvent.fromName('start'), LiveActivityEvent.start);
      expect(LiveActivityEvent.fromName('update'), LiveActivityEvent.update);
      expect(LiveActivityEvent.fromName('end'), LiveActivityEvent.end);
      expect(LiveActivityEvent.fromName('bogus'), isNull);
      expect(LiveActivityEvent.start.name, 'start');
    });

    test('cadence guard allows lifecycle events only', () {
      for (final String event in <String>[
        'open',
        'start',
        'update',
        'resolve',
        'end',
      ]) {
        expect(allowsLiveActivityPush(event), isTrue, reason: event);
      }
      for (final String event in <String>['check.ok', 'reminder', 'ack']) {
        expect(allowsLiveActivityPush(event), isFalse, reason: event);
      }
    });
  });

  group('buildLiveActivityPayload', () {
    test('start carries attributes-type + attributes + content-state', () {
      final Map<String, Object?> payload = buildLiveActivityPayload(
        event: LiveActivityEvent.start,
        incidentId: 'inc-1',
        monitorName: 'DB primary',
        title: 'DB primary is DOWN',
        body: 'Ongoing since 10:00',
        status: 'ongoing',
        nowSecs: 1700000000,
      );
      final Map<String, Object?> aps = (payload['aps']! as Map)
          .cast<String, Object?>();
      expect(aps['event'], 'start');
      expect(aps['timestamp'], 1700000000);
      expect(aps['attributes-type'], 'UptrackIncident');
      expect(kLiveActivityAttributesType, 'UptrackIncident');
      final Map<String, Object?> attributes = (aps['attributes']! as Map)
          .cast<String, Object?>();
      expect(attributes['incidentId'], 'inc-1');
      expect(attributes['monitorName'], 'DB primary');
      final Map<String, Object?> state = (aps['content-state']! as Map)
          .cast<String, Object?>();
      expect(state['title'], 'DB primary is DOWN');
      expect(state['status'], 'ongoing');
      expect(payload['incident_id'], 'inc-1');
      expect(payload['monitor_name'], 'DB primary');
    });

    test('update and end carry no attributes', () {
      for (final LiveActivityEvent event in <LiveActivityEvent>[
        LiveActivityEvent.update,
        LiveActivityEvent.end,
      ]) {
        final Map<String, Object?> payload = buildLiveActivityPayload(
          event: event,
          incidentId: 'inc-1',
          monitorName: 'DB primary',
          title: 't',
          body: 'b',
          status: event == LiveActivityEvent.end ? 'resolved' : 'ongoing',
          nowSecs: 1700000000,
        );
        final Map<String, Object?> aps = (payload['aps']! as Map)
            .cast<String, Object?>();
        expect(aps.containsKey('attributes'), isFalse, reason: event.name);
        expect(aps.containsKey('attributes-type'), isFalse, reason: event.name);
        expect(
          (aps['content-state']! as Map).cast<String, Object?>()['status'],
          event == LiveActivityEvent.end ? 'resolved' : 'ongoing',
        );
      }
    });

    test('parse round-trips the built payload', () {
      final Map<String, Object?> payload = buildLiveActivityPayload(
        event: LiveActivityEvent.start,
        incidentId: 'inc-1',
        monitorName: 'DB primary',
        title: 'DB primary is DOWN',
        body: 'Ongoing',
        status: 'ongoing',
        nowSecs: 1700000000,
      );
      final LiveActivityPush push = LiveActivityPush.fromJson(payload);
      expect(push.event, LiveActivityEvent.start);
      expect(push.incidentId, 'inc-1');
      expect(push.monitorName, 'DB primary');
      expect(push.state.title, 'DB primary is DOWN');
      expect(push.state.isResolved, isFalse);
      expect(push.attributes, isNotNull);
      expect(push.timestamp, 1700000000);
    });

    test('parse rejects payloads without event or content-state', () {
      expect(
        () => LiveActivityPush.fromJson(<String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => LiveActivityPush.fromJson(<String, Object?>{
          'aps': <String, Object?>{'event': 'nope'},
          'incident_id': 'i',
          'monitor_name': 'm',
        }),
        throwsFormatException,
      );
    });
  });

  group('LiveActivityRegisterRequest', () {
    test('validates kind, token presence, and TTL bounds', () {
      const LiveActivityRegisterRequest ok = LiveActivityRegisterRequest(
        incidentId: 'inc-1',
        token: 'device-push-token',
        kind: 'push_to_start',
        expiresInSeconds: 3600,
      );
      expect(ok.validate(), isEmpty);
      expect(ok.toJson()['incident_id'], 'inc-1');
      expect(ok.toJson()['kind'], 'push_to_start');
      expect(ok.toJson()['expires_in_seconds'], 3600);

      expect(
        const LiveActivityRegisterRequest(
          incidentId: 'inc-1',
          token: '  ',
          kind: 'push_to_start',
        ).validate(),
        isNotEmpty,
      );
      expect(
        const LiveActivityRegisterRequest(
          incidentId: 'inc-1',
          token: 't',
          kind: 'bogus',
        ).validate(),
        isNotEmpty,
      );
      expect(
        const LiveActivityRegisterRequest(
          incidentId: 'inc-1',
          token: 't',
          kind: 'update',
          expiresInSeconds: 30,
        ).validate(),
        isNotEmpty,
      );
      expect(
        const LiveActivityRegisterRequest(
          incidentId: 'inc-1',
          token: 't',
          kind: 'update',
          expiresInSeconds: 9999999,
        ).validate(),
        isNotEmpty,
      );
      // TTL is optional.
      expect(
        const LiveActivityRegisterRequest(
          incidentId: 'inc-1',
          token: 't',
          kind: 'update',
        ).validate(),
        isEmpty,
      );
    });
  });

  group('LiveActivityRemoveRequest', () {
    test('requires a token and encodes it', () {
      expect(const LiveActivityRemoveRequest(token: 'abc').validate(), isEmpty);
      expect(
        const LiveActivityRemoveRequest(token: 'abc').toJson(),
        <String, Object?>{'token': 'abc'},
      );
      expect(const LiveActivityRemoveRequest(token: '').validate(), isNotEmpty);
    });
  });
}
