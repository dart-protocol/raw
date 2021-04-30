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

import 'package:fixnum/fixnum.dart';
import 'package:raw/raw.dart';
import 'package:raw/test_helpers.dart';
import 'package:test/test.dart';

void main() {
  group("RawWriter:", () {
    test("toUint8List()", () {
      final writer = RawWriter(capacity: 5);
      writer.writeUint8(1);
      writer.writeUint8(2);
      expect(writer.toUint8List(), orderedEquals([1, 2]));
    });

    test("toUint8List(allowView: true", () {
      final writer = RawWriter(capacity: 5);
      writer.writeUint8(1);
      writer.writeUint8(2);
      expect(writer.toUint8List(copy: false), orderedEquals([1, 2]));
    });

    test("toByteData()", () {
      final writer = RawWriter(capacity: 5);
      writer.writeUint8(1);
      writer.writeUint8(2);
      final byteData = writer.toByteData();
      final uint8List = Uint8List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      expect(uint8List, orderedEquals([1, 2]));
    });

    test("toByteData(copy: false)", () {
      final writer = RawWriter(capacity: 5);
      writer.writeUint8(1);
      writer.writeUint8(2);
      final byteData = writer.toByteData(copy: false);
      final uint8List = Uint8List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      expect(uint8List, orderedEquals([1, 2]));
    });

    group("ensureAvailableBytes", () {
      test("when auto-expanding", () {
        final writer = RawWriter(capacity: 2, isExpanding: true);
        writer.writeUint32(0);
      });

      test("when not auto-expanding", () {
        final writer = RawWriter(capacity: 2, isExpanding: false);
        expect(
          () => writer.writeUint32(0),
          throwsA(const TypeMatcher<RawWriterException>()),
        );
      });
    });

    group("numbers", () {
      late RawWriter writer;
      late num written;
      late List<int> expected;
      late int expectedIndex;
      void littleEndian(int length) {
        final expectedCopy = List<int>.from(expected);
        final firstIndex = writer.length;
        final lastIndex = writer.length + length - 1;
        for (var i = 0; i < length; i++) {
          expected[firstIndex + i] = expectedCopy[lastIndex - i];
        }
      }

      group("writeUint8", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 1 + 2);
          writer.length = 2;
          written = 1;
          expected = [0, 0, 1];
          expectedIndex = 3;
        });

        test("simple call", () {
          writer.writeUint8(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 0);
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 0);
          writer.writeUint8(0x01);
          expect(writer.toUint8List(), byteListEquals(const <int>[1]));
        });
      });

      group("writeUint16", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 2 + 2);
          writer.length = 2;
          written = 0x0102;
          expected = [0, 0, 1, 2];
          expectedIndex = 4;
        });

        test("simple call", () {
          writer.writeUint16(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeUint16(written as int, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(2);
          writer.writeUint16(written as int, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 1);
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 1);
          writer.writeUint16(0x0102);
          expect(writer.toUint8List(), byteListEquals(const <int>[1, 2]));
        });
      });

      group("writeUint32", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 4 + 2);
          writer.length = 2;
          written = 0x01020304;
          expected = [0, 0, 1, 2, 3, 4];
          expectedIndex = 6;
        });

        test("simple call", () {
          writer.writeUint32(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeUint32(written as int, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(4);
          writer.writeUint32(written as int, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 3);
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 3);
          writer.writeUint32(0x01020304);
          expect(writer.toUint8List(), byteListEquals(const <int>[1, 2, 3, 4]));
        });
      });

      group("writeInt8", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 1 + 2);
          writer.length = 2;
          written = -2;
          expected = [0, 0, 0xFE];
          expectedIndex = 3;
        });

        test("simple call", () {
          writer.writeInt8(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 2);
          writer.length = 2;
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 2);
          writer.writeInt8(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
        });
      });

      group("writeInt16", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 2 + 2);
          writer.length = 2;
          written = -2;
          expected = [0, 0, 0xFF, 0xFE];
          expectedIndex = 4;
        });

        test("simple call", () {
          writer.writeInt16(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeInt16(written as int, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(2);
          writer.writeInt16(written as int, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 2 + 1);
          writer.length = 2;
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 2 + 1);
          writer.writeInt16(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
        });
      });

      group("writeInt32", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 4 + 2);
          writer.length = 2;
          written = -2;
          expected = [0, 0, 0xFF, 0xFF, 0xFF, 0xFE];
          expectedIndex = 6;
        });

        test("simple call", () {
          writer.writeInt32(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeInt32(written as int, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(4);
          writer.writeInt32(written as int, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 2 + 3);
          writer.length = 2;
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 2 + 3);
          writer.writeInt32(written as int);
          expect(writer.toUint8List(), byteListEquals(expected));
        });
      });
      group("writeFloat32", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 4 + 2);
          writer.length = 2;
          written = 3.14;
          expected = [0, 0, 0x40, 0x48, 0xf5, 0xc3];
          expectedIndex = 6;
        });

        test("simple call", () {
          writer.writeFloat32(written as double);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeFloat32(written as double, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(4);
          writer.writeFloat32(written as double, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 2 + 3);
          writer.length = 2;
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 2 + 3);
          writer.writeFloat32(written as double);
          expect(writer.toUint8List(), byteListEquals(expected));
        });
      });

      group("writeFloat64", () {
        setUp(() {
          writer = RawWriter(capacity: 2 + 8 + 2);
          writer.length = 2;
          written = 3.14;
          expected = [0, 0, 0x40, 0x09, 0x1e, 0xb8, 0x51, 0xeb, 0x85, 0x1f];
          expectedIndex = 10;
        });

        test("simple call", () {
          writer.writeFloat64(written as double);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("big-endian", () {
          writer.writeFloat64(written as double, Endian.big);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("little-endian", () {
          littleEndian(8);
          writer.writeFloat64(written as double, Endian.little);
          expect(writer.toUint8List(), byteListEquals(expected));
          expect(writer.length, expectedIndex);
        });

        test("expands when needed", () {
          writer = RawWriter(capacity: 2 + 7);
          writer.length = 2;
          expect(writer.toUint8List(copy: false).buffer.lengthInBytes, 2 + 7);
          writer.writeFloat64(written as double);
          expect(writer.toUint8List(), byteListEquals(expected));
        });
      });
    });

    group("writeFixInt64:", () {
      test("simple call", () {
        final value = Int64.fromBytes([1, 2, 3, 4, 5, 6, 7, 8]);
        final expected = [0, 1, 2, 3, 4, 5, 6, 7, 8];
        final expectedIndex = 9;

        final writer = RawWriter(capacity: 8);
        writer.length = 1;
        writer.writeFixInt64(value);
        expect(writer.toUint8List(), byteListEquals(expected));
        expect(writer.length, expectedIndex);
      });

      test("big-endian", () {
        final value = Int64.fromBytes([1, 2, 3, 4, 5, 6, 7, 8]);
        final expected = [0, 1, 2, 3, 4, 5, 6, 7, 8];
        final expectedIndex = 9;

        final writer = RawWriter(capacity: 8);
        writer.length = 1;
        writer.writeFixInt64(value, Endian.big);
        expect(writer.toUint8List(), byteListEquals(expected));
        expect(writer.length, expectedIndex);
      });

      test("little-endian", () {
        final value = Int64.fromBytes([1, 2, 3, 4, 5, 6, 7, 8]);
        final expected = [0, 8, 7, 6, 5, 4, 3, 2, 1];
        final expectedIndex = 9;

        final writer = RawWriter(capacity: 8);
        writer.length = 1;
        writer.writeFixInt64(value, Endian.little);
        expect(writer.toUint8List(), byteListEquals(expected));
        expect(writer.length, expectedIndex);
      });
    });

    test("writeVarUint", () {
      final expected = [0, 0x80, 0x01, 0x81, 0x01];
      final writer = RawWriter(capacity: 1);
      writer.writeVarUint(0);
      writer.writeVarUint(128);
      writer.writeVarUint(129);
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    test("writeVarInt", () {
      final expected = [0, 1, 2, 3, 4];
      final writer = RawWriter(capacity: 1);
      writer.writeVarInt(0);
      writer.writeVarInt(-1);
      writer.writeVarInt(1);
      writer.writeVarInt(-2);
      writer.writeVarInt(2);
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    group("writeBytes", () {
      test("writeBytes(value)", () {
        final input = const <int>[1, 2, 3, 4, 5];
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeBytes(input);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 1, 2, 3, 4, 5],
          ),
        );
      });

      test("writeBytes(value, index)", () {
        final input = const <int>[1, 2, 3, 4, 5];
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeBytes(input, 3);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 4, 5],
          ),
        );
      });

      test("writeBytes(value, index, length)", () {
        final input = const <int>[1, 2, 3, 4, 5];
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeBytes(input, 3, 1);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 4],
          ),
        );
      });

      test("writeBytes(long_uint8_list)", () {
        // Create a long input list
        final input = Uint8List(100000);
        for (var i = 0; i < input.length; i++) {
          input[i] = (i + 1) % 256;
        }

        // Write
        final writer = RawWriter(capacity: 2);
        writer.writeUint8(99);
        writer.writeBytes(input);

        // Test output
        final output = writer.toUint8List();
        expect(output.sublist(0, 4), byteListEquals([99, 1, 2, 3]));
        for (var i = 1; i < output.length; i++) {
          expect(output[i], i % 256);
        }
      });
    });

    group("writeByteData", () {
      test("writeByteData(value)", () {
        final input = ByteData(5);
        input.setUint8(0, 1);
        input.setUint8(1, 2);
        input.setUint8(2, 3);
        input.setUint8(3, 4);
        input.setUint8(4, 5);
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeByteData(input);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 1, 2, 3, 4, 5],
          ),
        );
      });

      test("writeByteData(value, index)", () {
        final input = ByteData(5);
        input.setUint8(0, 1);
        input.setUint8(1, 2);
        input.setUint8(2, 3);
        input.setUint8(3, 4);
        input.setUint8(4, 5);
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeByteData(input, 3);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 4, 5],
          ),
        );
      });

      test("writeByteData(value, index, length)", () {
        final input = ByteData(5);
        input.setUint8(0, 1);
        input.setUint8(1, 2);
        input.setUint8(2, 3);
        input.setUint8(3, 4);
        input.setUint8(4, 5);
        final writer = RawWriter(capacity: 2);
        writer.length = 2;
        writer.writeByteData(input, 3, 1);
        expect(
          writer.toUint8List(),
          byteListEquals(
            const [0, 0, 4],
          ),
        );
      });

      test("writeByteData(long_byte_data)", () {
        // Create a long input list
        final input = ByteData(100000);
        for (var i = 0; i < input.lengthInBytes; i++) {
          input.setUint8(i, (i + 1) % 256);
        }

        // Write
        final writer = RawWriter(capacity: 2);
        writer.writeUint8(99);
        writer.writeByteData(input);

        // Test output
        final output = writer.toUint8List();
        expect(output.sublist(0, 4), byteListEquals([99, 1, 2, 3]));
        for (var i = 1; i < output.length; i++) {
          expect(output[i], i % 256);
        }
      });
    });

    test("writeUtf8", () {
      final expected = [0x61, 0x62, 0x63, 0xf0, 0x9f, 0x99, 0x8f];

      final writer = RawWriter(capacity: 1);
      writer.writeUtf8("abc");
      writer.writeUtf8("🙏");
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    test("writeUtf8NullEnding", () {
      final expected = [0x61, 0x62, 0x63, 0, 0xf0, 0x9f, 0x99, 0x8f, 0];

      final writer = RawWriter(capacity: 1);
      writer.writeUtf8NullEnding("abc");
      writer.writeUtf8NullEnding("🙏");
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    test("writeUtf8Simple", () {
      final expected = [0x61, 0x62, 0x63];

      final writer = RawWriter(capacity: 1);
      writer.writeUtf8("abc");
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    test("writeUtf8SimpleNullEnding", () {
      final expected = [0x61, 0x62, 0x63, 0];

      final writer = RawWriter(capacity: 1);
      writer.writeUtf8NullEnding("abc");
      expect(writer.toUint8List(), byteListEquals(expected));
    });

    test("writeZeroes", () {
      const length = 1023;
      final writer = RawWriter(capacity: 1);
      for (var i = 0; i < length; i++) {
        writer.writeUint8(1);
      }
      writer.length = 1;
      writer.writeZeroes(length - 1);
      final output = writer.toUint8List();
      expect(output[0], 1);
      expect(output.length, length);
      expect(output.skip(1).every((v) => v == 0), isTrue);
    });
  });
}
