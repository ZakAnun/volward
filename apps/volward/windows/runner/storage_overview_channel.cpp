#include "storage_overview_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <windows.h>

#include <cstdint>
#include <cwchar>
#include <limits>
#include <memory>
#include <set>
#include <string>
#include <variant>
#include <vector>

#include "utils.h"

namespace {

using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;

std::vector<std::wstring> FixedDrives() {
  const DWORD required_length = GetLogicalDriveStringsW(0, nullptr);
  if (required_length == 0) {
    return {};
  }

  std::vector<wchar_t> buffer(required_length + 1, L'\0');
  const DWORD copied_length =
      GetLogicalDriveStringsW(required_length, buffer.data());
  if (copied_length == 0 || copied_length >= required_length) {
    return {};
  }

  std::vector<std::wstring> drives;
  for (const wchar_t* current = buffer.data(); *current != L'\0';
       current += std::wcslen(current) + 1) {
    if (GetDriveTypeW(current) == DRIVE_FIXED) {
      drives.emplace_back(current);
    }
  }
  return drives;
}

std::string DriveId(const std::wstring& root) {
  if (root.size() < 2 || root[1] != L':') {
    return {};
  }
  wchar_t id[] = {root[0], L':', L'\0'};
  if (id[0] >= L'a' && id[0] <= L'z') {
    id[0] = static_cast<wchar_t>(id[0] - L'a' + L'A');
  }
  return Utf8FromUtf16(id);
}

std::string DriveIdFromUtf8Path(const std::string& path) {
  if (path.size() < 2 || path[1] != ':') {
    return {};
  }
  unsigned char drive_letter = static_cast<unsigned char>(path[0]);
  if (drive_letter >= 'a' && drive_letter <= 'z') {
    drive_letter = static_cast<unsigned char>(drive_letter - 'a' + 'A');
  }
  if (drive_letter < 'A' || drive_letter > 'Z') {
    return {};
  }
  return std::string(1, static_cast<char>(drive_letter)) + ":";
}

std::string VolumeName(const std::wstring& root, const std::string& fallback) {
  wchar_t label[MAX_PATH] = {};
  if (GetVolumeInformationW(root.c_str(), label, MAX_PATH, nullptr, nullptr,
                            nullptr, nullptr, 0) &&
      label[0] != L'\0') {
    const std::string name = Utf8FromUtf16(label);
    if (!name.empty()) {
      return name;
    }
  }
  return fallback;
}

struct RequestedDriveSelection {
  bool has_selected_path = false;
  std::string drive_id;
};

RequestedDriveSelection RequestedDrive(const EncodableValue* arguments) {
  if (arguments == nullptr) {
    return {};
  }
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return {};
  }
  const auto found = map->find(EncodableValue("selectedPath"));
  if (found == map->end()) {
    return {};
  }
  const auto* path = std::get_if<std::string>(&found->second);
  if (path == nullptr || path->empty()) {
    return {};
  }

  RequestedDriveSelection selection;
  selection.has_selected_path = true;
  selection.drive_id = DriveIdFromUtf8Path(*path);
  return selection;
}

bool LoadCapacity(const std::wstring& root, int64_t* total_bytes,
                  int64_t* available_bytes) {
  ULARGE_INTEGER available = {};
  ULARGE_INTEGER total = {};
  if (!GetDiskFreeSpaceExW(root.c_str(), &available, &total, nullptr) ||
      total.QuadPart == 0 || available.QuadPart > total.QuadPart ||
      total.QuadPart >
          static_cast<ULONGLONG>(std::numeric_limits<int64_t>::max())) {
    return false;
  }

  *total_bytes = static_cast<int64_t>(total.QuadPart);
  *available_bytes = static_cast<int64_t>(available.QuadPart);
  return true;
}

std::wstring KnownFolderPath(REFKNOWNFOLDERID folder_id) {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(folder_id, 0, nullptr, &path)) ||
      path == nullptr || path[0] == L'\0') {
    if (path != nullptr) {
      CoTaskMemFree(path);
    }
    return {};
  }
  std::wstring result(path);
  CoTaskMemFree(path);
  while (result.size() > 3 &&
         (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

bool IsReadableDirectory(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    return false;
  }

  std::wstring query = path;
  if (!query.empty() && query.back() != L'\\' && query.back() != L'/') {
    query.push_back(L'\\');
  }
  query.push_back(L'*');
  WIN32_FIND_DATAW data = {};
  const HANDLE handle = FindFirstFileW(query.c_str(), &data);
  if (handle == INVALID_HANDLE_VALUE) {
    return false;
  }
  FindClose(handle);
  return true;
}

std::string FolderDisplayName(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  const wchar_t* name =
      separator == std::wstring::npos ? path.c_str() : path.c_str() + separator + 1;
  if (name[0] == L'\0') {
    return {};
  }
  return Utf8FromUtf16(name);
}

EncodableMap MakeLocation(const char* id, const char* kind,
                          const std::wstring& path,
                          const std::string& volume_id) {
  const std::string utf8_path = Utf8FromUtf16(path.c_str());
  std::string name = FolderDisplayName(path);
  if (name.empty()) {
    name = utf8_path;
  }
  return EncodableMap{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("name"), EncodableValue(name)},
      {EncodableValue("path"), EncodableValue(utf8_path)},
      {EncodableValue("kind"), EncodableValue(kind)},
      {EncodableValue("volumeId"), EncodableValue(volume_id)},
  };
}

}  // namespace

std::unique_ptr<StorageOverviewChannel> RegisterStorageOverviewChannel(
    flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<StorageOverviewChannel>(
      engine->messenger(), "com.volward/storage_overview",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "loadOverview") {
          result->NotImplemented();
          return;
        }

        flutter::EncodableList volumes;
        flutter::EncodableList locations;
        const RequestedDriveSelection requested =
            RequestedDrive(call.arguments());
        std::string selected_volume_id;
        std::set<std::string> volume_ids;

        for (const std::wstring& api_root : FixedDrives()) {
          const std::string id = DriveId(api_root);
          if (id.empty()) {
            continue;
          }

          int64_t total_bytes = 0;
          int64_t available_bytes = 0;
          if (!LoadCapacity(api_root, &total_bytes, &available_bytes)) {
            continue;
          }

          const std::string root_path = id + "\\";
          const std::string name = VolumeName(api_root, root_path);
          if ((!requested.has_selected_path && selected_volume_id.empty()) ||
              (!requested.drive_id.empty() && id == requested.drive_id)) {
            selected_volume_id = id;
          }
          volume_ids.insert(id);
          volumes.emplace_back(EncodableMap{
              {EncodableValue("id"), EncodableValue(id)},
              {EncodableValue("name"), EncodableValue(name)},
              {EncodableValue("rootPath"), EncodableValue(root_path)},
              {EncodableValue("totalBytes"), EncodableValue(total_bytes)},
              {EncodableValue("availableBytes"),
               EncodableValue(available_bytes)},
          });
        }

        const struct {
          const char* id;
          const char* kind;
          const KNOWNFOLDERID* folder_id;
        } folder_candidates[] = {
            {"home", "home", &FOLDERID_Profile},
            {"desktop", "desktop", &FOLDERID_Desktop},
            {"downloads", "downloads", &FOLDERID_Downloads},
            {"documents", "documents", &FOLDERID_Documents},
        };
        for (const auto& candidate : folder_candidates) {
          const std::wstring path = KnownFolderPath(*candidate.folder_id);
          if (path.empty() || !IsReadableDirectory(path)) {
            continue;
          }
          const std::string utf8_path = Utf8FromUtf16(path.c_str());
          const std::string volume_id = DriveIdFromUtf8Path(utf8_path);
          if (utf8_path.empty() || volume_id.empty() ||
              volume_ids.find(volume_id) == volume_ids.end()) {
            continue;
          }
          locations.emplace_back(
              MakeLocation(candidate.id, candidate.kind, path, volume_id));
        }

        if (volumes.empty()) {
          result->Error("capacity_unavailable",
                        "No accessible fixed drives available");
          return;
        }

        EncodableMap response{
            {EncodableValue("volumes"), EncodableValue(volumes)},
            {EncodableValue("locations"), EncodableValue(locations)},
        };
        if (!selected_volume_id.empty()) {
          response.emplace(EncodableValue("selectedVolumeId"),
                           EncodableValue(selected_volume_id));
        }
        result->Success(EncodableValue(response));
      });
  return channel;
}
