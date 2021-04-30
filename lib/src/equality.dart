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

class ByteDataEquality implements Equality<ByteData> {
  const ByteDataEquality();

  @override
  bool equals(ByteData e1, ByteData e2) {
    if (e1.lengthInBytes != e2.lengthInBytes) {
      return false;
    }
    var i = 0;
    for (; i + 3 < e1.lengthInBytes; i += 4) {
      if (e1.getUint32(i) != e2.getUint32(i)) {
        return false;
      }
    }
    for (; i < e1.lengthInBytes; i++) {
      if (e1.getUint8(i) != e2.getUint8(i)) {
        return false;
      }
    }
    return true;
  }

  @override
  int hash(ByteData e) {
    var h = e.lengthInBytes;
    var n = e.lengthInBytes;
    if (n > 256) {
      n = 256;
    }
    var i = 0;
    for (; i + 3 < n; i += 4) {
      h = 0xFFFFFFFF & (h + e.getUint32(i));
    }
    for (; i < n; i++) {
      h = 0xFFFFFFFF & (h + e.getUint8(i));
    }
    return h;
  }

  @override
  bool isValidKey(Object? o) {
    return o is ByteData;
  }
}
