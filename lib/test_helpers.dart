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

library raw_test;

import 'package:matcher/matcher.dart';

import 'raw.dart';

/// Returns a matcher that matches integers with the bytes.
/// Uses [DebugHexEncoder] for describing problems.
Matcher byteListEquals(Iterable<int> expected, {DebugHexEncoder? format}) {
  return _ByteListEquals(expected.toList(), format: format);
}

/// Returns a matcher that matches [RawEncodable] with another .
/// Uses [DebugHexEncoder] for describing problems.
Matcher selfEncoderEquals(RawEncodable expected, {DebugHexEncoder? format}) {
  return _SelfEncoderEquals(expected, format: format);
}

/// Returns a matcher that matches [RawEncodable] with the bytes.
/// Uses [DebugHexEncoder] for describing problems.
Matcher selfEncoderEqualsBytes(Iterable<int> expected,
    {DebugHexEncoder? format}) {
  return _SelfEncoderEquals(RawData(expected.toList()), format: format);
}

class _ByteListEquals extends Matcher {
  final List<int> _expected;
  final DebugHexEncoder format;

  _ByteListEquals(this._expected, {DebugHexEncoder? format})
      : this.format = format ?? const DebugHexEncoder();

  @override
  Description describe(Description description) {
    description = description.add('equals hex:').add(format.convert(_expected));
    return description;
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is List) {
      return mismatchDescription
          .replace("Actually hex:")
          .add(format.convert(item, expected: _expected));
    } else {
      return orderedEquals(_expected)
          .describeMismatch(item, mismatchDescription, matchState, verbose);
    }
  }

  @override
  bool matches(item, Map matchState) {
    if (item is List) {
      if (_expected.length != item.length) {
        return false;
      }
      for (var i = 0; i < item.length; i++) {
        if (_expected[i] != item[i]) {
          return false;
        }
      }
      return true;
    }
    return orderedEquals(_expected).matches(item, matchState);
  }
}

class _SelfEncoderEquals extends Matcher {
  final _ByteListEquals _equals;
  final Matcher _fallbackEquals;

  _SelfEncoderEquals(RawEncodable expected, {DebugHexEncoder? format})
      : this._equals =
            _ByteListEquals(expected.toUint8ListViewOrCopy(), format: format),
        this._fallbackEquals = equals(expected);

  @override
  Description describe(Description description) {
    return _equals.describe(description);
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is RawEncodable) {
      return _equals.describeMismatch(
        item.toUint8ListViewOrCopy(),
        mismatchDescription,
        matchState,
        verbose,
      );
    } else {
      return _fallbackEquals.describeMismatch(
        item,
        mismatchDescription,
        matchState,
        verbose,
      );
    }
  }

  @override
  bool matches(item, Map matchState) {
    if (item is RawEncodable) {
      return _equals.matches(item.toUint8ListViewOrCopy(), matchState);
    } else {
      return _fallbackEquals.matches(item, matchState);
    }
  }
}
