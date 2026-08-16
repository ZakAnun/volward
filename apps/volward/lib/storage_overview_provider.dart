import 'package:flutter/services.dart';

import 'storage_overview.dart';

abstract interface class StorageOverviewProvider {
  Future<StorageOverviewData> load({String? selectedPath});
}

class MethodChannelStorageOverviewProvider implements StorageOverviewProvider {
  const MethodChannelStorageOverviewProvider();

  static const channel = MethodChannel('com.volward/storage_overview');

  @override
  Future<StorageOverviewData> load({String? selectedPath}) async {
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'loadOverview',
        <String, Object?>{'selectedPath': selectedPath},
      );
      return result == null
          ? const StorageOverviewData.unavailable('empty_response')
          : StorageOverviewData.fromChannel(result);
    } on PlatformException catch (error) {
      return StorageOverviewData.unavailable(error.code);
    } on MissingPluginException {
      return const StorageOverviewData.unavailable('missing_plugin');
    } on Object {
      return const StorageOverviewData.unavailable('invalid_payload');
    }
  }
}
