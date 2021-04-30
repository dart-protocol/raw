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

import 'package:fixnum/fixnum.dart' show Int64;

import 'raw_value.dart';

/// Writes values into a buffer.
///
/// If `isExpanding` is true, buffer is automatically is expanded.
class RawWriter implements Sink<List<int>> {
  static const int _defaultInitialCapacity = 64;

  /// Minimum length for copying bytes in uin32 chunks.
  /// See 'test/benchmark.dart'.
  static const int _minLengthForUin32CopyMethod = 128;

  ByteData _byteData;

  int _length = 0;

  bool _isViewed = false;

  /// Determines whether buffer is expanded automatically.
  final bool isExpanding;

  /// Constructor that uses the [ByteData] as buffer.
  ///
  /// If `isExpanding` is true, buffer is expanded automatically.
  RawWriter.withByteData(this._byteData, {this.isExpanding = true});

  /// Constructor that allocates a new buffer with the capacity.
  ///
  /// If `isExpanding` is true, buffer is automatically is expanded.
  factory RawWriter({
    int capacity = _defaultInitialCapacity,
    bool isExpanding = true,
  }) {
    return RawWriter.withByteData(
      ByteData(capacity),
      isExpanding: isExpanding,
    );
  }

  /// Constructor that uses the [Uint8List] as buffer.
  ///
  /// If `isExpanding` is true, buffer is expanded automatically.
  RawWriter.withUint8List(Uint8List list, {bool isExpanding = true})
      : this.withByteData(
          ByteData.view(
            list.buffer,
            list.offsetInBytes,
            list.lengthInBytes,
          ),
          isExpanding: isExpanding,
        );

  /// Returns the buffer.
  ByteData get bufferAsByteData => _byteData;

  /// Current written length.
  ///
  /// It's acceptable to mutate the length temporarily to write into a specific
  /// region of the buffer.
  ///
  /// Decreasing length does not affect the underlying buffer at all.
  ///
  /// Increasing length does not guarantee that the added bytes are zero.
  /// For increasing length with zero bytes, use [writeZeroes].
  int get length => _length;

  set length(int value) {
    final oldValue = this._length;
    if (value > oldValue) {
      ensureAvailableLength(value - oldValue);
    }
    this._length = value;
  }

  /// Resets the buffer
  void reset({int capacity = _defaultInitialCapacity}) {
    if (_isViewed) {
      _byteData = ByteData(capacity);
      _isViewed = false;
    }
    _length = 0;
  }

  /// Ensures that the buffer has space for N more bytes.
  ///
  /// If buffer does not have enough space and [isExpanding] is false, will
  /// throw [RawWriterException].
  void ensureAvailableLength(int length) {
    // See whether old buffer has enough capacity.
    final oldByteData = this._byteData;
    final minCapacity = this._length + length;
    if (oldByteData.lengthInBytes >= minCapacity) {
      return;
    }

    if (!isExpanding) {
      throw RawWriterException(
          "ensureAvailaleLength($length) was called, but only ${oldByteData.lengthInBytes - this._length} bytes is available");
    }

    // Choose a new capacity that's a power of 2.
    var newCapacity = 64;
    while (newCapacity < minCapacity) {
      newCapacity *= 2;
    }

    // Switch to the new buffer.
    _byteData = ByteData(newCapacity);
    final oldIndex = this._length;
    this._length = 0;

    // Write contents of the old buffer.
    //
    // We write the whole buffer so we eliminate complex bugs when index is
    // non-monotonic or data is written directly.
    writeByteData(oldByteData);

    this._length = oldIndex;
  }

  /// Returns a view at the written bytes. The length will be equal to [length].
  ///
  /// By default, the result is always a view.
  /// If `copy` is true, the result is a copy of the bytes.
  ByteData toByteData({bool copy = false}) {
    final length = this._length;
    final byteData = this._byteData;
    if (copy) {
      final result = ByteData(length);
      final writer = RawWriter.withByteData(result);
      writer.writeByteData(byteData, 0, length);
      return result;
    }
    this._isViewed = true;
    if (length == byteData.lengthInBytes) {
      return byteData;
    }
    return ByteData.view(
      byteData.buffer,
      byteData.offsetInBytes,
      length,
    );
  }

  /// Returns a view at the written bytes. The length will be equal to [length].
  ///
  /// By default, the result is always a view.
  /// If `copy` is true, the result is a copy of the bytes.
  Uint8List toUint8List({bool copy = false}) {
    if (copy) {
      // Create a copy
      final byteData = toByteData();

      // Return a view at the copy
      return Uint8List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    }
    this._isViewed = true;
    final byteData = this._byteData;
    return Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes,
      this._length,
    );
  }

  /// Writes bytes from [ByteData].
  void writeByteData(ByteData value, [int index = 0, int? writtenLength]) {
    var calculatedWrittenLength = writtenLength ?? value.lengthInBytes - index;
    ensureAvailableLength(calculatedWrittenLength);

    final byteData = this._byteData;
    var bufferLength = this._length;
    if (calculatedWrittenLength >= _minLengthForUin32CopyMethod) {
      final hostEndian = Endian.host;
      while (calculatedWrittenLength >= 4) {
        byteData.setUint32(
          bufferLength,
          value.getUint32(index, hostEndian),
          hostEndian,
        );
        bufferLength += 4;
        index += 4;
        calculatedWrittenLength -= 4;
      }
    }
    while (calculatedWrittenLength > 0) {
      byteData.setUint8(bufferLength, value.getUint8(index));
      bufferLength++;
      index++;
      calculatedWrittenLength--;
    }
    this._length = bufferLength;
  }

  /// Writes bytes from a list.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeBytes(List<int> value, [int index = 0, int? writtenLength]) {
    var calculatedWrittenLength = writtenLength ?? value.length - index;
    if (calculatedWrittenLength >= _minLengthForUin32CopyMethod &&
        value is Uint8List) {
      writeByteData(
        ByteData.view(
          value.buffer,
          value.offsetInBytes + index,
          calculatedWrittenLength,
        ),
      );
      return;
    }
    ensureAvailableLength(calculatedWrittenLength);

    final buffer = this._byteData;
    var bufferIndex = this._length;
    for (final end = index + calculatedWrittenLength; index < end; index++) {
      buffer.setUint8(bufferIndex, value[index]);
      bufferIndex++;
    }
    this._length = bufferIndex;
  }

  /// Writes 64-bit integer (Int64 from _'package:fixnum'_).
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeFixInt64(Int64 value, [Endian endian = Endian.big]) {
    ensureAvailableLength(8);

    final bytes = value.toBytes();
    final length = this._length;
    if (endian == Endian.little) {
      for (var i = 0; i < bytes.length; i++) {
        _byteData.setUint8(length + 7 - i, bytes[i]);
      }
    } else {
      for (var i = 0; i < bytes.length; i++) {
        _byteData.setUint8(length + i, bytes[i]);
      }
    }
    this._length = length + 8;
  }

  /// Writes a 32-bit floating-point value.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeFloat32(double value, [Endian endian = Endian.big]) {
    ensureAvailableLength(4);

    final length = this._length;
    _byteData.setFloat32(length, value, endian);
    this._length = length + 4;
  }

  /// Writes a 64-bit floating-point value.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeFloat64(double value, [Endian endian = Endian.big]) {
    ensureAvailableLength(8);

    final length = this._length;
    _byteData.setFloat64(length, value, endian);
    this._length = length + 8;
  }

  /// Writes an 16-bit signed integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeInt16(int value, [Endian endian = Endian.big]) {
    ensureAvailableLength(2);

    final length = this._length;
    _byteData.setInt16(length, value, endian);
    this._length = length + 2;
  }

  /// Writes a 32-bit signed integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeInt32(int value, [Endian endian = Endian.big]) {
    ensureAvailableLength(4);

    final length = this._length;
    _byteData.setInt32(length, value, endian);
    this._length = length + 4;
  }

  /// Writes an 8-bit signed integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeInt8(int value) {
    ensureAvailableLength(1);

    final length = this._length;
    _byteData.setInt8(length, value);
    this._length = length + 1;
  }

  /// Writes a [RawEncodable].
  void writeSelfEncoder(RawEncodable encoder) {
    encoder.encodeRaw(this);
  }

  /// Writes a 16-bit unsigned integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeUint16(int value, [Endian endian = Endian.big]) {
    ensureAvailableLength(2);

    final length = this._length;
    _byteData.setUint16(length, value, endian);
    this._length = length + 2;
  }

  /// Writes a 32-bit unsigned integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeUint32(int value, [Endian endian = Endian.big]) {
    ensureAvailableLength(4);

    final length = this._length;
    _byteData.setUint32(length, value, endian);
    this._length = length + 4;
  }

  /// Writes an 8-bit unsigned integer.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeUint8(int value) {
    ensureAvailableLength(1);

    final length = this._length;
    _byteData.setUint8(length, value);
    this._length = length + 1;
  }

  /// Writes an UTF-8 string and returns length of the written bytes.
  ///
  /// If a non-null `maxLengthInBytes` is given, the method will thrown
  /// [ArgumentError] if UTF-8 encoding of the string exceeds the limit.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  int writeUtf8(String value, {int? maxLengthInBytes}) {
    // Write until the first multi-byte rune.
    final multiByteRuneIndex = _writeUtf8Simple(value);
    if (multiByteRuneIndex < 0) {
      // All runes were single-byte.
      return value.length;
    }

    // Remove written prefix.
    value = value.substring(multiByteRuneIndex);

    // Write the rest using UTF8-encoder
    final utf8Bytes = utf8.encode(value);
    if (maxLengthInBytes != null && utf8Bytes.length >= maxLengthInBytes) {
      throw ArgumentError.value(
        value,
        "value",
        "string exceeds maximum length ($maxLengthInBytes) when encoded to UTF-8",
      );
    }
    writeBytes(utf8Bytes);
    return utf8Bytes.length;
  }

  /// Writes an UTF-8 string that ends with a zero byte ("C string").
  /// Returns number of written bytes, including the final null-character.
  ///
  /// If a non-null `maxLengthInBytes` is given, the method will thrown
  /// [ArgumentError] if UTF-8 encoding of the string exceeds the limit.
  ///
  /// Throws [ArgumentError] if any rune is 0.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  int writeUtf8NullEnding(String value, {int? maxLengthInBytes}) {
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) == 0) {
        throw ArgumentError.value(value, "value", "contains null byte");
      }
    }
    final n = writeUtf8(value);
    writeUint8(0);
    return n + 1;
  }

  /// Writes an ASCII/UTF-8 string. Throws [ArgumentError] if any rune is
  /// greater than 127 (takes multiple bytes in UTF-8).
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeUtf8Simple(String value) {
    final multiByteRuneIndex = _writeUtf8Simple(value);
    if (multiByteRuneIndex < 0) {
      // All bytes were 0..127
      return;
    }
    throw ArgumentError.value(
        value, "value", "encountered a multi-byte rune at $multiByteRuneIndex");
  }

  /// Writes an ASCII/UTF-8 string that ends with a zero byte ("C string").
  /// Trows [ArgumentError] if any byte is 0 or greater than 127 (takes
  /// multiple bytes in UTF-8).
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeUtf8SimpleNullEnding(String value) {
    ensureAvailableLength(value.length + 1);

    final byteData = this._byteData;
    var length = this._length;
    for (var i = 0; i < value.length; i++) {
      final byte = value.codeUnitAt(i);
      if (byte == 0 || byte > 0x7F) {
        throw ArgumentError.value(value);
      }
      byteData.setUint8(length, byte);
      length++;
    }
    byteData.setUint8(length, 0);
    length++;
    this._length = length;
  }

  /// Writes variable-length signed integer.
  ///
  /// For an explanation of the encoding, see [Protocol Buffers documentation](https://developers.google.com/protocol-buffers/docs/encoding).
  ///
  /// Examples:
  ///   * -2 --> 0x03
  ///   * -1 --> 0x01
  ///   * 0 --> 0x00
  ///   * 1 --> 0x02
  ///   * 2 --> 0x04
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeVarInt(int value) {
    if (value < 0) {
      writeVarUint(-2 * value - 1);
    } else {
      writeVarUint(2 * value);
    }
  }

  /// Writes variable-length unsigned integer.
  ///
  /// For an explanation of the encoding, see [Protocol Buffers documentation](https://developers.google.com/protocol-buffers/docs/encoding).
  ///
  /// Examples:
  ///   * 0 --> 0x00
  ///   * 1 --> 0x01
  ///   * 259 --> 0x83, 0x02
  ///   * 65536 --> 0x80, 0x80, 0x04
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeVarUint(int value) {
    if (value < 0) {
      throw ArgumentError.value(value);
    }
    while (true) {
      final byte = 0x7F & value;
      final nextValue = value >> 7;
      if (nextValue == 0) {
        writeUint8(byte);
        return;
      }
      writeUint8(0x80 | byte);
      value = nextValue;
    }
  }

  /// Writes N zeroes.
  ///
  /// Before writing, the method calls [ensureAvailableLength], which may throw
  /// [RawWriterException].
  void writeZeroes(int writtenLength) {
    ensureAvailableLength(writtenLength);
    final byteData = this._byteData;
    var bufferLength = this._length;
    while (writtenLength >= 4) {
      byteData.setUint32(bufferLength, 0);
      bufferLength += 4;
      writtenLength -= 4;
    }
    while (writtenLength > 0) {
      byteData.setUint8(bufferLength, 0);
      bufferLength++;
      writtenLength--;
    }
    this._length = bufferLength;
  }

  /// Writes UTF-8 runes until a multi-byte rune is encountered.
  ///
  /// Returns index of the first multi-byte rune.
  /// Return value -1 means that all runes were single-byte.
  int _writeUtf8Simple(String value) {
    ensureAvailableLength(value.length);

    final byteData = this._byteData;
    var length = this._length;
    for (var i = 0; i < value.length; i++) {
      final byte = value.codeUnitAt(i);
      if (byte > 0x7F) {
        this._length = length;
        return i;
      }
      byteData.setUint8(length, byte);
      length++;
    }
    this._length = length;
    return -1;
  }

  @override
  void add(List<int> data) {
    writeBytes(data);
  }

  @override
  void close() {}
}

/// Thrown by [RawWriter].
class RawWriterException implements Exception {
  final String message;

  RawWriterException(this.message);

  @override
  String toString() => message;
}
