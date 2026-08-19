#include "storage_overview_channel.h"

#include <dirent.h>
#include <errno.h>
#include <gio/gio.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr long kNfsMagic = 0x6969;
constexpr long kCifsMagic = 0xFF534D42;
constexpr long kSmb2Magic = 0xFE534D42;
constexpr long kProcMagic = 0x9FA0;
constexpr long kSysfsMagic = 0x62656572;
constexpr long kTmpfsAndDevtmpfsMagic = 0x01021994;
constexpr long kDevptsMagic = 0x1CD1;
constexpr long kCgroupMagic = 0x27E0EB;
constexpr long kCgroup2Magic = 0x63677270;
constexpr long kDebugfsMagic = 0x64626720;
constexpr long kSecurityfsMagic = 0x73636673;
constexpr long kTracefsMagic = 0x74726163;
constexpr long kPstoreMagic = 0x6165676C;
constexpr long kMqueueMagic = 0x19800202;
constexpr long kHugetlbfsMagic = 0x958458F6;
constexpr long kConfigfsMagic = 0x62656570;
constexpr long kFusectlMagic = 0x65735543;
constexpr long kRamfsMagic = 0x858458F6;
constexpr long kBinfmtfsMagic = 0x42494E4D;
constexpr long kNsfsMagic = 0x6E736673;
constexpr long kBpfMagic = 0xCAFE4A11;
constexpr long kEfivarfsMagic = 0xDE5E81E4;

struct VolumeInfo {
  std::string id;
  std::string name;
  std::string root_path;
  int64_t total_bytes;
  int64_t available_bytes;
};

struct LocationCandidate {
  std::string id;
  std::string kind;
  std::string path;
};

struct LocationInfo {
  LocationCandidate candidate;
  std::string volume_id;
};

using VolumeMap = std::map<std::string, VolumeInfo>;

FlValue* string_value(const std::string& value) {
  return fl_value_new_string(value.c_str());
}

void map_set(FlValue* map, const gchar* key, FlValue* value) {
  fl_value_set_string_take(map, key, value);
}

std::string user_directory_or_fallback(GUserDirectory directory,
                                       const gchar* fallback_name) {
  const gchar* configured = g_get_user_special_dir(directory);
  if (configured != nullptr && configured[0] != '\0') {
    return configured;
  }
  const gchar* home = g_get_home_dir();
  if (home == nullptr || home[0] == '\0') {
    return {};
  }
  g_autofree gchar* fallback = g_build_filename(home, fallback_name, nullptr);
  return fallback == nullptr ? std::string() : fallback;
}

std::string normalize_path(const gchar* path) {
  if (path == nullptr || path[0] == '\0') {
    return {};
  }
  g_autofree gchar* resolved = realpath(path, nullptr);
  g_autofree gchar* canonical =
      resolved == nullptr ? g_canonicalize_filename(path, nullptr) : nullptr;
  const gchar* normalized_path = resolved == nullptr ? canonical : resolved;
  std::string normalized = normalized_path == nullptr ? path : normalized_path;
  while (normalized.size() > 1 && normalized.back() == '/') {
    normalized.pop_back();
  }
  return normalized;
}

bool directory_contents_are_readable(const gchar* path) {
  DIR* directory = opendir(path);
  if (directory == nullptr) {
    return false;
  }

  const int descriptor = dirfd(directory);
  struct stat status = {};
  bool readable = descriptor >= 0 && fstat(descriptor, &status) == 0 &&
                  S_ISDIR(status.st_mode) &&
                  faccessat(descriptor, ".", R_OK | X_OK, 0) == 0;
  if (readable) {
    errno = 0;
    readdir(directory);
    readable = errno == 0;
  }
  closedir(directory);
  return readable;
}

bool path_is_under_root(const std::string& path, const std::string& root) {
  if (root == "/") {
    return !path.empty() && path.front() == '/';
  }
  if (path == root) {
    return true;
  }
  return path.size() > root.size() && path.compare(0, root.size(), root) == 0 &&
         path[root.size()] == '/';
}

bool is_remote_filesystem(GFile* root) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GFileInfo) info = g_file_query_filesystem_info(
      root, G_FILE_ATTRIBUTE_FILESYSTEM_REMOTE, nullptr, &error);
  return info == nullptr || g_file_info_get_attribute_boolean(
                                info, G_FILE_ATTRIBUTE_FILESYSTEM_REMOTE);
}

bool is_unsupported_filesystem(const gchar* path) {
  struct statfs filesystem = {};
  if (statfs(path, &filesystem) != 0) {
    return true;
  }
  switch (filesystem.f_type) {
    case kNfsMagic:
    case kCifsMagic:
    case kSmb2Magic:
    case kProcMagic:
    case kSysfsMagic:
    case kTmpfsAndDevtmpfsMagic:
    case kDevptsMagic:
    case kCgroupMagic:
    case kCgroup2Magic:
    case kDebugfsMagic:
    case kSecurityfsMagic:
    case kTracefsMagic:
    case kPstoreMagic:
    case kMqueueMagic:
    case kHugetlbfsMagic:
    case kConfigfsMagic:
    case kFusectlMagic:
    case kRamfsMagic:
    case kBinfmtfsMagic:
    case kNsfsMagic:
    case kBpfMagic:
    case kEfivarfsMagic:
      return true;
    default:
      return false;
  }
}

bool checked_capacity(const gchar* path, int64_t* total_bytes,
                      int64_t* available_bytes) {
  struct statvfs stats = {};
  if (statvfs(path, &stats) != 0 || stats.f_frsize == 0 ||
      stats.f_blocks == 0) {
    return false;
  }

  const uint64_t block_size = static_cast<uint64_t>(stats.f_frsize);
  const uint64_t blocks = static_cast<uint64_t>(stats.f_blocks);
  const uint64_t available_blocks = static_cast<uint64_t>(stats.f_bavail);
  const uint64_t max_int64 =
      static_cast<uint64_t>(std::numeric_limits<int64_t>::max());
  if (blocks > max_int64 / block_size ||
      available_blocks > max_int64 / block_size) {
    return false;
  }

  const uint64_t total = blocks * block_size;
  const uint64_t available = std::min(total, available_blocks * block_size);
  *total_bytes = static_cast<int64_t>(total);
  *available_bytes = static_cast<int64_t>(available);
  return true;
}

bool add_mount(GMount* mount, VolumeMap* volumes,
               std::string* added_volume_id = nullptr) {
  g_autoptr(GFile) root = g_mount_get_root(mount);
  if (root == nullptr) {
    return false;
  }
  g_autofree gchar* raw_root_path = g_file_get_path(root);
  if (raw_root_path == nullptr || is_remote_filesystem(root) ||
      is_unsupported_filesystem(raw_root_path)) {
    return false;
  }

  const std::string root_path = normalize_path(raw_root_path);
  if (root_path.empty()) {
    return false;
  }
  int64_t total_bytes = 0;
  int64_t available_bytes = 0;
  if (!checked_capacity(raw_root_path, &total_bytes, &available_bytes)) {
    return false;
  }

  g_autofree gchar* raw_name = g_mount_get_name(mount);
  std::string name = raw_name == nullptr ? "" : raw_name;
  if (name.empty()) {
    g_autofree gchar* basename = g_path_get_basename(root_path.c_str());
    name = basename == nullptr ? root_path : basename;
  }

  VolumeInfo volume = {root_path, name, root_path, total_bytes,
                       available_bytes};
  const auto existing = volumes->find(root_path);
  if (existing == volumes->end()) {
    volumes->emplace(root_path, std::move(volume));
  } else if (name < existing->second.name) {
    existing->second.name = name;
  }
  if (added_volume_id != nullptr) {
    *added_volume_id = root_path;
  }
  return true;
}

std::string parent_path(const std::string& path) {
  if (path.empty() || path == "/") {
    return {};
  }
  g_autofree gchar* parent = g_path_get_dirname(path.c_str());
  if (parent == nullptr || parent[0] == '\0') {
    return {};
  }
  std::string result = parent;
  while (result.size() > 1 && result.back() == '/') {
    result.pop_back();
  }
  return result == path ? std::string() : result;
}

std::string mount_root_for_path(const std::string& path) {
  struct stat current_stat = {};
  if (stat(path.c_str(), &current_stat) != 0) {
    return {};
  }
  const dev_t device = current_stat.st_dev;
  std::string current = path;
  while (current != "/") {
    const std::string parent = parent_path(current);
    if (parent.empty()) {
      break;
    }
    struct stat parent_stat = {};
    if (stat(parent.c_str(), &parent_stat) != 0 ||
        parent_stat.st_dev != device) {
      break;
    }
    current = parent;
  }
  return current;
}

bool add_statvfs_volume(const gchar* path, VolumeMap* volumes,
                        std::string* added_volume_id = nullptr) {
  const std::string normalized_path = normalize_path(path);
  if (normalized_path.empty() ||
      is_unsupported_filesystem(normalized_path.c_str())) {
    return false;
  }
  const std::string root_path = mount_root_for_path(normalized_path);
  if (root_path.empty() || is_unsupported_filesystem(root_path.c_str())) {
    return false;
  }

  int64_t total_bytes = 0;
  int64_t available_bytes = 0;
  if (!checked_capacity(root_path.c_str(), &total_bytes, &available_bytes)) {
    return false;
  }

  g_autofree gchar* basename = g_path_get_basename(root_path.c_str());
  std::string name = basename == nullptr ? root_path : basename;
  if (name.empty() || name == "/") {
    name = "Disk";
  }

  VolumeInfo volume = {root_path, name, root_path, total_bytes,
                       available_bytes};
  const auto existing = volumes->find(root_path);
  if (existing == volumes->end()) {
    volumes->emplace(root_path, std::move(volume));
  } else if (name < existing->second.name) {
    existing->second.name = name;
  }
  if (added_volume_id != nullptr) {
    *added_volume_id = root_path;
  }
  return true;
}

bool add_enclosing_mount(const gchar* path, VolumeMap* volumes,
                         std::string* added_volume_id = nullptr) {
  const std::string normalized_path = normalize_path(path);
  if (normalized_path.empty()) {
    return false;
  }
  g_autoptr(GFile) file = g_file_new_for_path(normalized_path.c_str());
  g_autoptr(GError) error = nullptr;
  g_autoptr(GMount) mount = g_file_find_enclosing_mount(file, nullptr, &error);
  if (mount != nullptr && add_mount(mount, volumes, added_volume_id)) {
    return true;
  }
  return add_statvfs_volume(normalized_path.c_str(), volumes, added_volume_id);
}

void add_discovered_mounts(VolumeMap* volumes) {
  g_autoptr(GVolumeMonitor) monitor = g_volume_monitor_get();
  if (monitor == nullptr) {
    return;
  }
  GList* mounts = g_volume_monitor_get_mounts(monitor);
  for (GList* entry = mounts; entry != nullptr; entry = entry->next) {
    add_mount(G_MOUNT(entry->data), volumes);
  }
  g_list_free_full(mounts, g_object_unref);
}

const VolumeInfo* deepest_volume_for_path(const VolumeMap& volumes,
                                          const gchar* raw_path) {
  const std::string path = normalize_path(raw_path);
  const VolumeInfo* selected = nullptr;
  for (const auto& entry : volumes) {
    const VolumeInfo& volume = entry.second;
    if (path_is_under_root(path, volume.root_path) &&
        (selected == nullptr ||
         volume.root_path.size() > selected->root_path.size())) {
      selected = &volume;
    }
  }
  return selected;
}

FlValue* make_volume(const VolumeInfo& volume) {
  FlValue* value = fl_value_new_map();
  map_set(value, "id", string_value(volume.id));
  map_set(value, "name", string_value(volume.name));
  map_set(value, "rootPath", string_value(volume.root_path));
  map_set(value, "totalBytes", fl_value_new_int(volume.total_bytes));
  map_set(value, "availableBytes", fl_value_new_int(volume.available_bytes));
  return value;
}

FlValue* make_location(const LocationCandidate& candidate,
                       const VolumeInfo& volume) {
  g_autofree gchar* raw_name = g_path_get_basename(candidate.path.c_str());
  const std::string name = raw_name == nullptr ? candidate.path : raw_name;
  FlValue* value = fl_value_new_map();
  map_set(value, "id", string_value(candidate.id));
  map_set(value, "name", string_value(name));
  map_set(value, "path", string_value(candidate.path));
  map_set(value, "kind", string_value(candidate.kind));
  map_set(value, "volumeId", string_value(volume.id));
  return value;
}

FlMethodResponse* capacity_error(const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new("capacity_unavailable", message, nullptr));
}

FlMethodResponse* load_overview(FlMethodCall* call) {
  const gchar* selected_path = g_get_home_dir();
  FlValue* args = fl_method_call_get_args(call);
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* raw = fl_value_lookup_string(args, "selectedPath");
    if (raw != nullptr && fl_value_get_type(raw) == FL_VALUE_TYPE_STRING &&
        fl_value_get_string(raw)[0] != '\0') {
      selected_path = fl_value_get_string(raw);
    }
  }

  if (selected_path == nullptr || selected_path[0] == '\0' ||
      !g_file_test(selected_path, G_FILE_TEST_IS_DIR) ||
      is_unsupported_filesystem(selected_path)) {
    return capacity_error("selected filesystem is unavailable");
  }

  const gchar* raw_home = g_get_home_dir();
  const std::string home = raw_home == nullptr ? "" : raw_home;
  const std::vector<LocationCandidate> candidates = {
      {"home", "home", home},
      {"desktop", "desktop",
       user_directory_or_fallback(G_USER_DIRECTORY_DESKTOP, "Desktop")},
      {"downloads", "downloads",
       user_directory_or_fallback(G_USER_DIRECTORY_DOWNLOAD, "Downloads")},
      {"documents", "documents",
       user_directory_or_fallback(G_USER_DIRECTORY_DOCUMENTS, "Documents")},
  };

  VolumeMap volumes;
  add_discovered_mounts(&volumes);
  std::string selected_mount_id;
  if (!add_enclosing_mount(selected_path, &volumes, &selected_mount_id)) {
    return capacity_error("selected filesystem capacity is unavailable");
  }
  std::vector<LocationInfo> locations;
  for (const LocationCandidate& candidate : candidates) {
    if (!candidate.path.empty() &&
        directory_contents_are_readable(candidate.path.c_str())) {
      std::string volume_id;
      if (add_enclosing_mount(candidate.path.c_str(), &volumes, &volume_id)) {
        locations.push_back({candidate, volume_id});
      }
    }
  }

  const VolumeInfo* selected = deepest_volume_for_path(volumes, selected_path);
  if (selected == nullptr || selected->id != selected_mount_id) {
    return capacity_error("selected filesystem mount was not found");
  }
  const std::string selected_volume_id = selected->id;

  g_autoptr(FlValue) result = fl_value_new_map();
  map_set(result, "selectedVolumeId", string_value(selected_volume_id));

  FlValue* volume_values = fl_value_new_list();
  fl_value_append_take(volume_values, make_volume(*selected));
  for (const auto& entry : volumes) {
    if (entry.first != selected_volume_id) {
      fl_value_append_take(volume_values, make_volume(entry.second));
    }
  }
  map_set(result, "volumes", volume_values);

  FlValue* location_values = fl_value_new_list();
  for (const LocationInfo& location : locations) {
    const auto volume = volumes.find(location.volume_id);
    if (volume != volumes.end()) {
      fl_value_append_take(location_values,
                           make_location(location.candidate, volume->second));
    }
  }
  map_set(result, "locations", location_values);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

void method_call_cb(FlMethodChannel*, FlMethodCall* call, gpointer) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (std::strcmp(fl_method_call_get_name(call), "loadOverview") == 0) {
    response = load_overview(call);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}
}  // namespace

void register_storage_overview_channel(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.volward/storage_overview",
      FL_METHOD_CODEC(fl_standard_method_codec_get_instance()));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), "volward-storage-overview-channel",
                         g_steal_pointer(&channel), g_object_unref);
}
