#ifndef RUNNER_STORAGE_OVERVIEW_CHANNEL_H_
#define RUNNER_STORAGE_OVERVIEW_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>

using StorageOverviewChannel = flutter::MethodChannel<flutter::EncodableValue>;

std::unique_ptr<StorageOverviewChannel> RegisterStorageOverviewChannel(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_STORAGE_OVERVIEW_CHANNEL_H_
