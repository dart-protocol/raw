// Copyright 2019 dart-raw authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:raw/raw.dart' show DebugHexEncoder;

import 'raw_writer.dart';

class RawReader {
  /// Tells whether typed data returning methods ([readByteData], [readUint8List]) are
  /// allowed to return views of the input.
  final bool isViewAllowed;

  final ByteData _byteData;

  /// Current index in the buffer.
  int index;

  RawReader.withByteData(
    this._byteData, {
    this.index = 0,
    this.isViewAllowed = true,
  });

  factory RawReader.withBytes(List<int> bytes, {bool isViewAllowed = false}) {
    if (bytes is Uint8List) {
      return RawReader.withByteData(
        ByteData.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
        isViewAllowed: isViewAllowed,
      );
    }

    // Allocate ByteData and copy bytes into it
    final byteData = ByteData(bytes.length);
    final writer = RawWriter.withByteData(byteData, isExpanding: false);
    writer.writeBytes(bytes);
    return RawReader.withByteData(
      byteData,
      isViewAllowed: isViewAllowed,
    );
  }

  /// Deprecated. Use [availableLength].
  @deprecated
  int get availableLengthInBytes => _byteData.lengthInBytes - index;

  /// Returns the number of unread bytes.
  int get availableLength => _byteData.lengthInBytes - index;

  /// Returns a view ([ByteData]) at the buffer.
  ByteData get bufferAsByteData => _byteData;

  /// Returns a view ([Uint8List]) at the buffer.
  Uint8List get bufferAsUint8List {
    final byteData = this._byteData;
    return Uint8List.view(
        byteData.buffer, byteData.offsetInBytes, byteData.lengthInBytes);
  }

  /// Returns the number of bytes before the next zero byte.
  ///
  /// If `maxLength` is null and zero is not found, the method throws
  /// [RawReaderException].
  /// If `maxLength` is non-null and zero is not found within the first
  /// `maxLength` bytes, the method returns `maxLength`.
  int lengthUntilZero({int? maxLength}) {
    final byteData = this._byteData;
    final start = this.index;
    int end;
    if (maxLength == null) {
      end = _byteData.lengthInBytes;
    } else {
      end = start + maxLength;
    }
    for (var i = start; i < end; i++) {
      if (byteData.getUint8(i) == 0) {
        return i - start;
      }
    }
    if (maxLength != null) {
      return maxLength;
    }
    throw _newEofException(start, "sequence of bytes terminated by zero");
  }

  /// Previews a 16-bit unsigned integer without advancing in the byte list.
  int previewUint16(int index, [Endian endian = Endian.big]) {
    return _byteData.getUint16(this.index + index, endian);
  }

  /// Previews a 32-bit unsigned integer without advancing in the byte list.
  int previewUint32(int index, [Endian endian = Endian.big]) {
    return _byteData.getUint32(this.index + index, endian);
  }

  /// Previews a byte without advancing in the byte list.
  int previewUint8(int index) {
    return _byteData.getUint8(this.index + index);
  }

  /// Returns a copy of the next `length` bytes.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  ByteData readByteData(int length) {
    final byteData = this._byteData;
    final result = ByteData(length);
    var i = 0;

    // If 128 or more bytes, we read in 4-byte chunks.
    // This should be faster.
    //
    // This constant is just a guess of a good minimum.
    if (length >> 7 != 0) {
      final optimizedDestination = Uint32List.view(
          result.buffer, result.offsetInBytes, result.lengthInBytes);
      while (i + 3 < length) {
        // Copy in 4-byte chunks.
        // We must use host endian during reading.
        optimizedDestination[i] = byteData.getUint32(index + i, Endian.host);
        i += 4;
      }
    }
    for (; i < result.lengthInBytes; i++) {
      result.setUint8(i, byteData.getUint8(index + i));
    }
    this.index = index + length;
    return result;
  }

  /// Returns a view at the next `length` bytes. If views are disallowed
  /// ([isCopyOnRead] is true), the method returns a copy of the bytes.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  ByteData readByteDataViewOrCopy(int? length) {
    if (length == null) {
      length = availableLength;
    } else if (length > _byteData.lengthInBytes - index) {
      throw ArgumentError.value(length, "length");
    }
    if (isViewAllowed) {
      return _readByteDataView(length);
    }
    return readByteData(length);
  }

  /// Reads a 64-bit signed integer as _Int64_ (from _'package:fixnum'_).
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 8.
  Int64 readFixInt64([Endian endian = Endian.big]) {
    final bytes = readUint8List(8);
    if (endian == Endian.little) {
      return Int64.fromBytes(bytes);
    } else {
      return Int64.fromBytesBigEndian(bytes);
    }
  }

  /// Reads a 32-bit floating-point value.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 4.
  double readFloat32([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 4;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "float32");
    }
    final value = byteData.getFloat32(index, endian);
    this.index = newIndex;
    return value;
  }

  /// Reads a 64-bit floating-point value.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 8.
  double readFloat64([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 8;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "float64");
    }
    final value = _byteData.getFloat64(index, endian);
    this.index = index + 8;
    return value;
  }

  /// Reads a 32-bit signed integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 2.
  int readInt16([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 2;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "int16");
    }
    final value = _byteData.getInt16(index, endian);
    this.index = index + 2;
    return value;
  }

  /// Reads a 32-bit signed integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 4.
  int readInt32([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 4;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "int32");
    }
    final value = _byteData.getInt32(index, endian);
    this.index = index + 4;
    return value;
  }

  /// Reads an 8-bit signed integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 1.
  int readInt8() {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 1;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "int8");
    }
    final value = _byteData.getInt8(index);
    this.index = index + 1;
    return value;
  }

  /// Returns a new RawReader that has a view at a span of this RawReader.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  RawReader readRawReader(int length) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + length;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "$length bytes");
    }
    final result = RawReader.withByteData(
      ByteData.view(
        byteData.buffer,
        byteData.offsetInBytes + index,
        length,
      ),
    );
    this.index = index + length;
    return result;
  }

  /// Reads a 16-bit unsigned integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 2.
  int readUint16([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 2;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "uint16");
    }
    final value = _byteData.getUint16(index, endian);
    this.index = index + 2;
    return value;
  }

  /// Reads a 32-bit unsigned integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 4.
  int readUint32([Endian endian = Endian.big]) {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 4;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "uint32");
    }
    final value = _byteData.getUint32(index, endian);
    this.index = index + 4;
    return value;
  }

  /// Reads an 8-bit unsigned integer.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by 1.
  int readUint8() {
    final byteData = this._byteData;
    final index = this.index;
    final newIndex = index + 1;
    if (newIndex > byteData.lengthInBytes) {
      throw _newEofException(index, "uint8");
    }
    final value = _byteData.getUint8(index);
    this.index = index + 1;
    return value;
  }

  /// Returns a copy of the next `length` bytes.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  Uint8List readUint8List(int? length) {
    if (length == null) {
      length = availableLength;
    } else if (length > _byteData.lengthInBytes - index) {
      throw ArgumentError.value(length, "length");
    }
    final result = Uint8List(length);
    var i = 0;

    // If 128 or more bytes, we read in 4-byte chunks.
    // This should be faster.
    //
    // This constant is just a guess of a good minimum.
    if (length >> 7 != 0) {
      final optimizedDestination = Uint32List.view(
        result.buffer,
        result.offsetInBytes,
        result.lengthInBytes,
      );
      while (i + 3 < length) {
        // Copy in 4-byte chunks.
        // We must use host endian during reading.
        optimizedDestination[i] = _byteData.getUint32(index + i, Endian.host);
        i += 4;
      }
    }
    for (var i = 0; i < result.length; i++) {
      result[i] = _byteData.getUint8(index + i);
    }
    this.index = index + length;
    return result;
  }

  /// Returns a view at the next `length` bytes. If views are disallowed
  /// ([isCopyOnRead] is true), returns a copy of the bytes.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  Uint8List readUint8ListViewOrCopy(int? length) {
    if (length == null) {
      length = availableLength;
    } else if (length > _byteData.lengthInBytes - index) {
      throw ArgumentError.value(length, "length");
    }
    if (isViewAllowed) {
      return _readUint8ListView(length);
    }
    return readUint8List(length);
  }

  /// Reads an UTF-8 string.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  String readUtf8(int length) {
    final bytes = _readUint8ListView(length);
    return utf8.decode(bytes);
  }

  /// Reads an UTF-8 string delimited by a zero byte ("C string").
  ///
  /// The delimiter will be excluded from the returned string.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by length of the bytes,
  /// including the delimiter.
  String readUtf8NullEnding() {
    var length = lengthUntilZero();
    final result = readUtf8(length);
    readUint8();
    return result;
  }

  /// Reads an ASCII/UTF-8 string.
  /// Validates that every byte is less than 0x80 (takes only a single byte in
  /// UTF-8).
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by `length`.
  String readUtf8Simple(int length) {
    final bytes = _readUint8ListView(length);
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] >= 128) {
        throw _newException(
          "Expected UTF-8 with single-byte runes, found a rune that's not single-byte",
          index: index - length + i,
        );
      }
    }
    return String.fromCharCodes(bytes);
  }

  /// Reads an ASCII/UTF-8 string delimited by a zero byte ("C string").
  /// Validates that every byte is less than 0x80 (takes only a single byte in
  /// UTF-8).
  ///
  /// The delimiter will be excluded from the returned string.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by length of the bytes,
  /// including the delimiter.
  String readUtf8SimpleNullEnding() {
    var length = lengthUntilZero();
    final result = readUtf8Simple(length);
    readUint8();
    return result;
  }

  /// Reads a variable-length signed integer.
  ///
  /// For an explanation of the encoding, see [Protocol Buffers documentation](https://developers.google.com/protocol-buffers/docs/encoding).
  ///
  /// Examples:
  ///   * 0x00 --> 0
  ///   * 0x01 --> -1
  ///   * 0x02 --> 1
  ///   * 0x03 --> -2
  ///   * 0x04 --> 2
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by length of the bytes.
  int readVarInt() {
    final value = readVarUint();
    if (value % 2 == 0) {
      return value ~/ 2;
    }
    return (value ~/ -2) - 1;
  }

  /// Reads a variable-length unsigned integer.
  ///
  /// For an explanation of the encoding, see [Protocol Buffers documentation](https://developers.google.com/protocol-buffers/docs/encoding).
  ///
  /// Examples:
  ///   * 0x00 --> 0
  ///   * 0x01 --> 1
  ///   * 0x83, 0x02 --> (2 << 7) + 3 = 259
  ///   * 0x80, 0x80, 0x04 --> (4 << 14) + (0 << 7) + 0 = 2 << 14 = 65536
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by length of the bytes.
  int readVarUint() {
    final byteData = this._byteData;
    final start = this.index;
    var index = start;
    var result = 0;
    for (var i = 0; i < 64; i += 7) {
      if (index >= byteData.lengthInBytes) {
        throw _newEofException(index, "VarUint");
      }
      final byte = byteData.getUint8(index);
      index++;
      result |= (0x7F & byte) << i;
      if (0x80 & byte == 0) {
        break;
      }
    }
    this.index = index;
    return result;
  }

  /// Reads N bytes and validates that every byte is zero.
  ///
  /// If reading fails, the method throws [RawReaderException].
  /// If reading succeeds, the method increments [index] by length of the bytes.
  void readZeroes(int length) {
    final start = this.index;
    for (; length > 0; length--) {
      final value = readUint8();
      if (value != 0) {
        throw _newException(
            "expected $length zero bytes found a non-zero byte after ${this.index - 1 - start} bytes",
            index: start);
      }
    }
  }

  /// Returns an error that describes unexpected EOF.
  RawReaderException _newEofException(int index, String type) {
    return _newException(
      "Expected $type at $index, encountered EOF after ${_byteData.lengthInBytes - index} bytes.",
    );
  }

  RawReaderException _newException(String message, {int? index}) {
    index ??= this.index;
    var snippetStart = index - 16;
    if (snippetStart < 0) {
      snippetStart = 0;
    }
    var snippetEnd = index + 16;
    if (snippetEnd > _byteData.lengthInBytes) {
      snippetEnd = _byteData.lengthInBytes;
    }
    final byteData = this._byteData;
    final snippet = Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes + snippetStart,
      snippetEnd - snippetStart,
    );
    return RawReaderException(
      message,
      index: index,
      snippet: snippet,
      snippetIndex: index - snippetStart,
    );
  }

  ByteData _readByteDataView(int length) {
    final byteData = this._byteData;
    final index = this.index;
    final result = ByteData.view(
      byteData.buffer,
      byteData.offsetInBytes + index,
      length,
    );
    this.index = index + length;
    return result;
  }

  Uint8List _readUint8ListView(int length) {
    final byteData = this._byteData;
    final index = this.index;
    final result = Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes + index,
      length,
    );
    this.index = index + length;
    return result;
  }
}

/// Thrown by [RawReader].
class RawReaderException implements Exception {
  final String message;
  final int index;
  final Uint8List snippet;
  final int snippetIndex;

  RawReaderException(
    this.message, {
    required this.index,
    required this.snippet,
    required this.snippetIndex,
  });

  @override
  String toString() {
    final snippet = const DebugHexEncoder().convert(this.snippet);
    return "Error at ${index}: $message\nBytes ${index}..${index + snippetIndex}..${index + snippet.length}: $snippet";
  }
}
