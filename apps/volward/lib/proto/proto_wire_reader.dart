import 'dart:convert';
import 'dart:typed_data';

/// Shared proto3 binary reader for hand-written decoders.
class ProtoWireReader {
  ProtoWireReader(this._data, this._pos, this._end);

  final Uint8List _data;
  int _pos;
  final int _end;

  bool get isDone => _pos >= _end;

  int readVarint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      final b = _data[_pos++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
    return result;
  }

  String readString() {
    final len = readVarint();
    final view = Uint8List.view(_data.buffer, _data.offsetInBytes + _pos, len);
    _pos += len;
    return utf8.decode(view);
  }

  ProtoWireReader readLenSlice() {
    final len = readVarint();
    final start = _pos;
    _pos += len;
    return ProtoWireReader(_data, start, start + len);
  }

  int readFixed64() {
    final data = ByteData.sublistView(_data, _pos, _pos + 8);
    _pos += 8;
    return data.getUint64(0, Endian.little);
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        while (_data[_pos++] & 0x80 != 0) {}
      case 1:
        _pos += 8;
      case 2:
        _pos += readVarint();
      case 5:
        _pos += 4;
      default:
        throw StateError('proto_wire_reader: unknown wire type $wireType');
    }
  }
}

double fixed64ToDouble(int bits) {
  final data = ByteData(8);
  data.setUint64(0, bits, Endian.little);
  return data.getFloat64(0, Endian.little);
}
