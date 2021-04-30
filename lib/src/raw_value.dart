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

import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'raw_reader.dart';
import 'raw_writer.dart';

/// Interface for classes that implements both [RawEncodable] and [RawDecodable].
abstract class RawValue extends RawEncodable with RawDecodable {}

/// Interface for classes that can decode themselves using [RawReader].
abstract class RawDecodable {
  /// Decodes from the bytes.
  void decodeRaw(RawReader reader);

  /// Decodes from the argument.
  ///
  /// The default implementation first encodes the argument
  /// (using [RawEncodable.toByteDataViewOrCopy]) and then calls [decodeRaw] of
  /// this object.
  void decodeRawFromValue(RawEncodable value) {
    final byteData = value.toByteDataViewOrCopy();
    final reader = RawReader.withByteData(byteData);
    decodeRaw(reader);
  }
}

/// Interface for classes that can encode themselves using [RawWriter].
abstract class RawEncodable {
  const RawEncodable();

  /// Determines hash by serializing this value.
  @override
  int get hashCode => const RawEquality().hash(this);

  /// Determines equality by serializing both values.
  @override
  bool operator ==(other) {
    return other is RawEncodable && const RawEquality().equals(this, other);
  }

  /// Encodes this object.
  void encodeRaw(RawWriter writer);

  /// Returns an estimate of the maximum number of bytes needed to encode this
  /// value.
  int encodeRawCapacity() => 64;

  /// Returns a copy of the encoded value.
  ByteData toByteData() {
    final capacity = encodeRawCapacity();
    final writer = RawWriter(capacity: capacity);
    encodeRaw(writer);
    return writer.toByteData();
  }

  /// Returns a view or copy of the encoded value.
  ///
  /// The default implementation of this method returns a copy of the bytes
  /// (using [toByteData]), but subclasses may return a view.
  ByteData toByteDataViewOrCopy() => toByteData();

  /// Returns a copy of the encoded value.
  Uint8List toUint8List() {
    final capacity = encodeRawCapacity();
    final writer = RawWriter(capacity: capacity);
    encodeRaw(writer);
    return writer.toUint8List();
  }

  /// Returns a view or copy of the encoded value.
  ///
  /// The default implementation of this method returns a copy of the bytes
  /// (using [toUint8List]), but subclasses may return a view.
  Uint8List toUint8ListViewOrCopy() => toUint8List();
}

/// Equality for [RawEncodable].
///
/// Used by '==' and 'hashCode' in [RawEncodable].
class RawEquality<T extends RawEncodable> implements Equality<T> {
  const RawEquality();

  @override
  bool equals(T e1, T e2) {
    final bytes = e1.toUint8ListViewOrCopy();
    final otherBytes = e2.toUint8ListViewOrCopy();
    if (bytes.length != otherBytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != otherBytes[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int hash(T e) {
    final bytes = e.toByteDataViewOrCopy();
    const mask = 0x7FFFFFFF;

    var h = 0;
    var i = 0;
    while (true) {
      int value = 0;
      if (i + 3 < bytes.lengthInBytes) {
        value = bytes.getUint32(i, Endian.little);
        i += 4;
      } else if (i < bytes.lengthInBytes) {
        value = 0;
        var shift = 0;
        do {
          value |= bytes.getUint8(i) << shift;
          i++;
          shift += 8;
        } while (i < bytes.lengthInBytes);
      } else {
        break;
      }
      final a = 0xFF & (value >> 24);
      final b = 0xFF & (value >> 16);
      final c = 0xFF & (value >> 8);
      final d = 0xFF & value;
      h = mask & (h ^ value);
      h = mask & ((((h * 11 + a) * 13 + b) * 17 + c) * 19 + d);
      h = mask & ((h >> 19) | (h << 13));
      h = mask & (h ^ value);
      h = mask & ((((h * 13 + a) * 17 + b) * 19 + c) * 23 + d);
    }
    h ^= bytes.lengthInBytes;
    return h;
  }

  @override
  bool isValidKey(Object? o) => o is RawEncodable;
}
