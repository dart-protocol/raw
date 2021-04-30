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

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:raw/raw.dart';

void main() {
  const minLength = 128;

  // writeUtf8(...)
  WriteUtf8Benchmark().report();

  // writeUint8List(...): Aligned copy, uint8 chunks
  WriteUint8ListBenchmark(0, 0, minLength - 1).report();
  // writeUint8List(...): Aligned copy, uint32 chunks + uint8 chunks
  WriteUint8ListBenchmark(0, 0, minLength + 1).report();

  // writeUint8List(...): Non-aligned copy, uint8 chunks
  WriteUint8ListBenchmark(63, 63, minLength - 1).report();
  // writeUint8List(...): Non-aligned copy, uint32 chunks + uint8 chunks
  WriteUint8ListBenchmark(63, 63, minLength + 1).report();
}

class WriteUtf8Benchmark extends BenchmarkBase {
  static const times = 100;
  static const value =
      "013456789013456789013456789013456789013456789013456789013456789013456789013456789013456789";
  late RawWriter _destination;

  WriteUtf8Benchmark()
      : super(
          "writeUtf8(...): $times times",
        );

  @override
  void setup() {
    _destination = RawWriter(capacity: times * value.length);
    super.setup();
  }

  @override
  void run() {
    // Set initial index
    _destination.length = 0;

    for (var i = 0; i < times; i++) {
      // Copy from source to destination
      _destination.writeUtf8(value);
    }
  }
}

class WriteUint8ListBenchmark extends BenchmarkBase {
  static const times = 100;
  final int destinationIndex;
  final int sourceIndex;
  final int length;
  late Uint8List _source;
  late RawWriter _destination;

  WriteUint8ListBenchmark(this.destinationIndex, this.sourceIndex, this.length)
      : super(
          "writeUint8List(...): $times times: destinationIndex=$destinationIndex sourceIndex=$sourceIndex length=$length",
        );

  @override
  void setup() {
    _source = Uint8List(sourceIndex + length);
    for (var i = 0; i < _source.length; i++) {
      _source[i] = i % 256;
    }
    _destination = RawWriter(capacity: destinationIndex + times * length);
    super.setup();
  }

  @override
  void run() {
    // Set initial index
    _destination.length = destinationIndex;

    for (var i = 0; i < times; i++) {
      // Copy from source to destination
      _destination.writeBytes(_source, sourceIndex, length);
    }
  }
}
