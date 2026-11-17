import 'dart:ffi';
import 'dart:io';

abstract interface class NativeLibraryHandle {
  Pointer<T> lookup<T extends NativeFunction>(String symbol);

  Pointer<T>? tryLookup<T extends NativeFunction>(String symbol);
}

class DynamicNativeLibraryHandle implements NativeLibraryHandle {
  DynamicNativeLibraryHandle._(this._library);

  factory DynamicNativeLibraryHandle.openExecutableSibling() {
    return DynamicNativeLibraryHandle._(_openExecutableSibling());
  }

  final DynamicLibrary _library;

  @override
  Pointer<T> lookup<T extends NativeFunction>(String symbol) {
    return _library.lookup<T>(symbol);
  }

  @override
  Pointer<T>? tryLookup<T extends NativeFunction>(String symbol) {
    try {
      return lookup<T>(symbol);
    } on Object {
      return null;
    }
  }

  static DynamicLibrary _openExecutableSibling() {
    if (Platform.isMacOS) {
      final exe = Platform.resolvedExecutable;
      final libPath =
          '${File(exe).parent.path}/../Frameworks/libvolward_facade.dylib';
      return DynamicLibrary.open(libPath);
    }
    if (Platform.isLinux) {
      final exe = Platform.resolvedExecutable;
      final libPath = '${File(exe).parent.path}/lib/libvolward_facade.so';
      return DynamicLibrary.open(libPath);
    }
    if (Platform.isWindows) {
      final exe = Platform.resolvedExecutable;
      final libPath = '${File(exe).parent.path}/volward_facade.dll';
      return DynamicLibrary.open(libPath);
    }
    throw UnsupportedError('Volward native bridge: unsupported platform');
  }
}
