import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/storage_overview_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('used bytes are total minus available and remain bounded', () {
    const normal = StorageVolumeInfo(
      id: '/',
      name: 'Disk',
      rootPath: '/',
      totalBytes: 100,
      availableBytes: 35,
      freshness: StorageDataFreshness.live,
    );
    const invalidAvailable = StorageVolumeInfo(
      id: '/bad',
      name: 'Bad',
      rootPath: '/bad',
      totalBytes: 100,
      availableBytes: 140,
      freshness: StorageDataFreshness.live,
    );

    expect(normal.usedBytes, 65);
    expect(normal.usedFraction, 0.65);
    expect(invalidAvailable.usedBytes, 0);
    expect(invalidAvailable.usedFraction, 0);
  });

  test('payload parser drops malformed volumes and orphan locations', () {
    final data = StorageOverviewData.fromChannel(<String, Object?>{
      'selectedVolumeId': 'C:',
      'volumes': <Object?>[
        <String, Object?>{
          'id': 'C:',
          'name': 'Windows',
          'rootPath': r'C:\',
          'totalBytes': 1000,
          'availableBytes': 250,
        },
        <String, Object?>{'id': '', 'rootPath': ''},
      ],
      'locations': <Object?>[
        <String, Object?>{
          'id': 'drive-C',
          'name': 'Windows',
          'path': r'C:\',
          'kind': 'volume',
          'volumeId': 'C:',
        },
        <String, Object?>{
          'id': 'orphan',
          'name': 'Missing',
          'path': r'Z:\',
          'kind': 'volume',
          'volumeId': 'Z:',
        },
      ],
    });

    expect(data.volumes, hasLength(1));
    expect(data.locations.map((item) => item.id), ['drive-C']);
    expect(data.selectedVolume?.id, 'C:');
  });

  test('payload parser keeps Windows volumes independent of user folders', () {
    final data = StorageOverviewData.fromChannel(<String, Object?>{
      'selectedVolumeId': 'C:',
      'volumes': <Object?>[
        <String, Object?>{
          'id': 'C:',
          'name': 'Windows',
          'rootPath': r'C:\',
          'totalBytes': 1000,
          'availableBytes': 250,
        },
        <String, Object?>{
          'id': 'D:',
          'name': 'Data',
          'rootPath': r'D:\',
          'totalBytes': 2000,
          'availableBytes': 750,
        },
      ],
      'locations': <Object?>[
        <String, Object?>{
          'id': 'home',
          'name': 'me',
          'path': r'C:\Users\me',
          'kind': 'home',
          'volumeId': 'C:',
        },
        <String, Object?>{
          'id': 'downloads',
          'name': 'Downloads',
          'path': r'C:\Users\me\Downloads',
          'kind': 'downloads',
          'volumeId': 'C:',
        },
        <String, Object?>{
          'id': 'desktop',
          'name': 'Desktop',
          'path': r'C:\Users\me\Desktop',
          'kind': 'desktop',
          'volumeId': 'C:',
        },
        <String, Object?>{
          'id': 'documents',
          'name': 'Documents',
          'path': r'C:\Users\me\Documents',
          'kind': 'documents',
          'volumeId': 'C:',
        },
      ],
    });

    expect(data.selectedVolume?.id, 'C:');
    expect(data.volumes.map((item) => item.id), ['C:', 'D:']);
    expect(data.locations.map((item) => item.id), [
      'home',
      'downloads',
      'desktop',
      'documents',
    ]);
    expect(data.locations.map((item) => item.kind), [
      StorageLocationKind.home,
      StorageLocationKind.downloads,
      StorageLocationKind.desktop,
      StorageLocationKind.documents,
    ]);
    expect(data.locations.map((item) => item.volumeId), [
      'C:',
      'C:',
      'C:',
      'C:',
    ]);
  });

  test('payload parser selects a requested Windows drive', () {
    final data = StorageOverviewData.fromChannel(<String, Object?>{
      'selectedVolumeId': 'D:',
      'volumes': <Object?>[
        <String, Object?>{
          'id': 'C:',
          'name': 'Windows',
          'rootPath': r'C:\',
          'totalBytes': 1000,
          'availableBytes': 250,
        },
        <String, Object?>{
          'id': 'D:',
          'name': 'Data',
          'rootPath': r'D:\',
          'totalBytes': 2000,
          'availableBytes': 750,
        },
      ],
      'locations': <Object?>[
        <String, Object?>{
          'id': 'home',
          'name': 'me',
          'path': r'C:\Users\me',
          'kind': 'home',
          'volumeId': 'C:',
        },
      ],
    });

    expect(data.selectedVolume?.id, 'D:');
    expect(data.volumes.map((item) => item.id), ['C:', 'D:']);
    expect(data.locations.map((item) => item.id), ['home']);
  });

  test('payload parser preserves omitted Windows selection provenance', () {
    final data = StorageOverviewData.fromChannel(<String, Object?>{
      'volumes': <Object?>[
        <String, Object?>{
          'id': 'C:',
          'name': 'Windows',
          'rootPath': r'C:\',
          'totalBytes': 1000,
          'availableBytes': 250,
        },
      ],
      'locations': <Object?>[],
    });

    expect(data.selectedVolumeId, isNull);
  });

  test(
    'payload parser requires nonblank strings and preserves valid paths',
    () {
      final data = StorageOverviewData.fromChannel(<String, Object?>{
        'selectedVolumeId': 'valid',
        'volumes': <Object?>[
          <String, Object?>{
            'id': 'valid',
            'rootPath': '/valid ',
            'totalBytes': 100,
            'availableBytes': 50,
          },
          <String, Object?>{'id': 7, 'rootPath': '/numeric-id'},
          <String, Object?>{'id': 'numeric-path', 'rootPath': 9},
          <String, Object?>{'id': '   ', 'rootPath': '/blank-id'},
          <String, Object?>{'id': 'blank-path', 'rootPath': '   '},
        ],
        'locations': <Object?>[
          <String, Object?>{
            'id': 'valid-location',
            'path': ' relative/home ',
            'kind': 'home',
            'volumeId': 'valid',
          },
          <String, Object?>{
            'id': 1,
            'path': '/numeric-id',
            'volumeId': 'valid',
          },
          <String, Object?>{
            'id': 'numeric-path',
            'path': 2,
            'volumeId': 'valid',
          },
          <String, Object?>{
            'id': 'numeric-volume',
            'path': '/numeric-volume',
            'volumeId': 3,
          },
          <String, Object?>{
            'id': 'blank-path',
            'path': '   ',
            'volumeId': 'valid',
          },
          <String, Object?>{
            'id': 'blank-volume',
            'path': '/blank-volume',
            'volumeId': '   ',
          },
        ],
      });

      expect(data.volumes.map((volume) => volume.id), ['valid']);
      expect(data.volumes.single.rootPath, '/valid ');
      expect(data.locations.map((location) => location.id), ['valid-location']);
      expect(data.locations.single.path, ' relative/home ');
      expect(data.locations.single.volumeId, 'valid');
    },
  );

  test('non-finite capacities are isolated from valid volumes', () {
    final data = StorageOverviewData.fromChannel(<String, Object?>{
      'volumes': <Object?>[
        <String, Object?>{
          'id': 'malformed',
          'name': 'Malformed',
          'rootPath': '/malformed',
          'totalBytes': double.nan,
          'availableBytes': double.infinity,
        },
        <String, Object?>{
          'id': 'valid',
          'name': 'Valid',
          'rootPath': '/valid',
          'totalBytes': 100,
          'availableBytes': 25,
        },
      ],
      'locations': <Object?>[],
    });

    expect(data.volumes.map((volume) => volume.id), ['malformed', 'valid']);
    expect(data.volumes.first.totalBytes, isNull);
    expect(data.volumes.first.availableBytes, isNull);
    expect(data.volumes.last.usedBytes, 75);
  });

  test('overview snapshots defensively copy immutable lists', () {
    final volumes = <StorageVolumeInfo>[
      const StorageVolumeInfo(
        id: '/',
        name: 'System',
        rootPath: '/',
        totalBytes: 100,
        availableBytes: 50,
        freshness: StorageDataFreshness.live,
      ),
    ];
    final locations = <StorageLocationInfo>[
      const StorageLocationInfo(
        id: 'home',
        name: 'Home',
        path: '/Users/me',
        kind: StorageLocationKind.home,
        volumeId: '/',
      ),
    ];
    final data = StorageOverviewData(volumes: volumes, locations: locations);
    const loading = StorageOverviewData.loading();
    const unavailable = StorageOverviewData.unavailable('unavailable');

    volumes.clear();
    locations.clear();

    expect(data.volumes, hasLength(1));
    expect(data.locations, hasLength(1));
    expect(() => data.volumes.clear(), throwsUnsupportedError);
    expect(() => data.locations.clear(), throwsUnsupportedError);
    expect(loading.loading, isTrue);
    expect(unavailable.errorCode, 'unavailable');
  });

  test('volume paths use the deepest matching POSIX root', () {
    final data = StorageOverviewData(
      volumes: <StorageVolumeInfo>[
        const StorageVolumeInfo(
          id: '/',
          name: 'System',
          rootPath: '/',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
        const StorageVolumeInfo(
          id: '/Volumes/Data',
          name: 'Data',
          rootPath: '/Volumes/Data',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: <StorageLocationInfo>[],
      selectedVolumeId: '/',
    );

    expect(data.volumeForPath('/Volumes/Data/projects')?.id, '/Volumes/Data');
    expect(data.volumeForPath('/Volumes/Database')?.id, '/');
  });

  test('POSIX volume paths remain case-sensitive', () {
    final data = StorageOverviewData(
      volumes: <StorageVolumeInfo>[
        const StorageVolumeInfo(
          id: '/',
          name: 'System',
          rootPath: '/',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
        const StorageVolumeInfo(
          id: '/Volumes/Data',
          name: 'Data',
          rootPath: '/Volumes/Data',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: const <StorageLocationInfo>[],
      selectedVolumeId: '/Volumes/Data',
    );

    expect(data.volumeForPath('/volumes/data/projects')?.id, '/');
  });

  test('volume paths normalize Windows separators and casing', () {
    final data = StorageOverviewData(
      volumes: <StorageVolumeInfo>[
        const StorageVolumeInfo(
          id: 'C:',
          name: 'Windows',
          rootPath: r'C:\',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
        const StorageVolumeInfo(
          id: 'users',
          name: 'Users',
          rootPath: r'C:\Users',
          totalBytes: 100,
          availableBytes: 50,
          freshness: StorageDataFreshness.live,
        ),
      ],
      locations: <StorageLocationInfo>[],
      selectedVolumeId: 'C:',
    );

    expect(data.volumeForPath(r'c:\users\me')?.id, 'users');
    expect(data.volumeForPath(r'C:\UserSettings')?.id, 'C:');
  });

  const channel = MethodChannel('com.volward/storage_overview');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('method channel provider maps a successful payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'loadOverview');
      expect(call.arguments, {'selectedPath': '/Users/me'});
      return <String, Object?>{
        'selectedVolumeId': '/',
        'volumes': <Object?>[
          <String, Object?>{
            'id': '/',
            'name': 'Macintosh HD',
            'rootPath': '/',
            'totalBytes': 100,
            'availableBytes': 40,
          },
        ],
        'locations': <Object?>[],
      };
    });

    final result = await const MethodChannelStorageOverviewProvider().load(
      selectedPath: '/Users/me',
    );

    expect(result.selectedVolume?.name, 'Macintosh HD');
    expect(result.selectedVolume?.usedBytes, 60);
  });

  test(
    'method channel provider converts platform errors to unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'capacity_unavailable');
      });

      final result = await const MethodChannelStorageOverviewProvider().load();

      expect(result.volumes, isEmpty);
      expect(result.errorCode, 'capacity_unavailable');
      expect(result.loading, isFalse);
    },
  );

  test(
    'method channel provider converts null responses to empty response',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final result = await const MethodChannelStorageOverviewProvider().load();

      expect(result.volumes, isEmpty);
      expect(result.errorCode, 'empty_response');
      expect(result.loading, isFalse);
    },
  );

  test(
    'method channel provider converts missing plugins to unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw MissingPluginException();
      });

      final result = await const MethodChannelStorageOverviewProvider().load();

      expect(result.volumes, isEmpty);
      expect(result.errorCode, 'missing_plugin');
      expect(result.loading, isFalse);
    },
  );

  test(
    'method channel provider converts unexpected errors to invalid payload',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'not-a-map');

      final result = await const MethodChannelStorageOverviewProvider().load();

      expect(result.volumes, isEmpty);
      expect(result.errorCode, 'invalid_payload');
      expect(result.loading, isFalse);
    },
  );

  test('macOS bridge resolves capacity paths without rewriting locations', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(source, contains('.resolvingSymlinksInPath()'));
    expect(source, contains('"path": url.path'));
  });
}
