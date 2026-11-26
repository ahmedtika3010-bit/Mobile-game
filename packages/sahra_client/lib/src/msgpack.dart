/// Small MessagePack codec covering what the game server sends and receives:
/// nil, bool, int, float, str, bin, array, map. No extension types.
library;

import 'dart:convert';
import 'dart:typed_data';

class MsgPackReader {
  MsgPackReader(this._b, [this._o = 0]) : _d = ByteData.sublistView(_b);
  final Uint8List _b;
  final ByteData _d;
  int _o;

  bool get hasMore => _o < _b.length;

  dynamic read() {
    final t = _b[_o++];
    if (t <= 0x7f) return t;
    if (t >= 0xe0) return t - 0x100;
    if (t >= 0xa0 && t <= 0xbf) return _str(t & 0x1f);
    if (t >= 0x90 && t <= 0x9f) return _arr(t & 0x0f);
    if (t >= 0x80 && t <= 0x8f) return _map(t & 0x0f);
    switch (t) {
      case 0xc0:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xc4:
        return _bin(_u8());
      case 0xc5:
        return _bin(_u16());
      case 0xc6:
        return _bin(_u32());
      case 0xca:
        final v = _d.getFloat32(_o);
        _o += 4;
        return v;
      case 0xcb:
        final v = _d.getFloat64(_o);
        _o += 8;
        return v;
      case 0xcc:
        return _u8();
      case 0xcd:
        return _u16();
      case 0xce:
        return _u32();
      case 0xcf:
        // 64-bit reads via two 32-bit halves so this also works when compiled to JavaScript.
        final hi = _d.getUint32(_o), lo = _d.getUint32(_o + 4);
        _o += 8;
        return hi * 4294967296 + lo;
      case 0xd0:
        final v = _d.getInt8(_o);
        _o += 1;
        return v;
      case 0xd1:
        final v = _d.getInt16(_o);
        _o += 2;
        return v;
      case 0xd2:
        final v = _d.getInt32(_o);
        _o += 4;
        return v;
      case 0xd3:
        final hi = _d.getInt32(_o), lo = _d.getUint32(_o + 4);
        _o += 8;
        return hi * 4294967296 + lo;
      case 0xd9:
        return _str(_u8());
      case 0xda:
        return _str(_u16());
      case 0xdb:
        return _str(_u32());
      case 0xdc:
        return _arr(_u16());
      case 0xdd:
        return _arr(_u32());
      case 0xde:
        return _map(_u16());
      case 0xdf:
        return _map(_u32());
    }
    throw FormatException('unsupported msgpack type 0x${t.toRadixString(16)}');
  }

  int _u8() => _b[_o++];
  int _u16() {
    final v = _d.getUint16(_o);
    _o += 2;
    return v;
  }

  int _u32() {
    final v = _d.getUint32(_o);
    _o += 4;
    return v;
  }

  String _str(int n) {
    final s = utf8.decode(_b.sublist(_o, _o + n));
    _o += n;
    return s;
  }

  Uint8List _bin(int n) {
    final v = Uint8List.fromList(_b.sublist(_o, _o + n));
    _o += n;
    return v;
  }

  List<dynamic> _arr(int n) => List.generate(n, (_) => read());
  Map<String, dynamic> _map(int n) {
    final m = <String, dynamic>{};
    for (var i = 0; i < n; i++) {
      m['${read()}'] = read();
    }
    return m;
  }
}

class MsgPackWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void writeByte(int b) => _out.addByte(b);

  void write(Object? v) {
    if (v == null) {
      _out.addByte(0xc0);
    } else if (v is bool) {
      _out.addByte(v ? 0xc3 : 0xc2);
    } else if (v is int) {
      _int(v);
    } else if (v is double) {
      final d = ByteData(9)
        ..setUint8(0, 0xcb)
        ..setFloat64(1, v);
      _out.add(d.buffer.asUint8List());
    } else if (v is String) {
      final bytes = utf8.encode(v);
      final n = bytes.length;
      if (n < 32) {
        _out.addByte(0xa0 | n);
      } else if (n < 0x100) {
        _out.add([0xd9, n]);
      } else if (n < 0x10000) {
        _out.add([0xda, n >> 8, n & 0xff]);
      } else {
        _out.add([0xdb, ..._be32(n)]);
      }
      _out.add(bytes);
    } else if (v is List) {
      final n = v.length;
      if (n < 16) {
        _out.addByte(0x90 | n);
      } else if (n < 0x10000) {
        _out.add([0xdc, n >> 8, n & 0xff]);
      } else {
        _out.add([0xdd, ..._be32(n)]);
      }
      for (final e in v) {
        write(e);
      }
    } else if (v is Map) {
      final n = v.length;
      if (n < 16) {
        _out.addByte(0x80 | n);
      } else if (n < 0x10000) {
        _out.add([0xde, n >> 8, n & 0xff]);
      } else {
        _out.add([0xdf, ..._be32(n)]);
      }
      v.forEach((k, e) {
        write('$k');
        write(e);
      });
    } else {
      throw ArgumentError('cannot encode ${v.runtimeType}');
    }
  }

  void _int(int v) {
    if (v >= 0 && v <= 0x7f) {
      _out.addByte(v);
    } else if (v < 0 && v >= -32) {
      _out.addByte(0x100 + v);
    } else if (v >= 0 && v <= 0xffffffff) {
      final d = ByteData(5)
        ..setUint8(0, 0xce)
        ..setUint32(1, v);
      _out.add(d.buffer.asUint8List());
    } else if (v < 0 && v >= -0x80000000) {
      final d = ByteData(5)
        ..setUint8(0, 0xd2)
        ..setInt32(1, v);
      _out.add(d.buffer.asUint8List());
    } else {
      // Beyond 32 bits (e.g. millisecond timestamps): float64 is exact up to 2^53
      // and needs no 64-bit integer support (not available when compiled to JavaScript).
      final d = ByteData(9)
        ..setUint8(0, 0xcb)
        ..setFloat64(1, v.toDouble());
      _out.add(d.buffer.asUint8List());
    }
  }

  List<int> _be32(int n) =>
      [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];

  Uint8List takeBytes() => _out.takeBytes();
}
