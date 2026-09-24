// Tests for the shelf pin config: first-run detection, round trip and
// corrupt-file tolerance.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:materde_shell/shelf/shelf_config.dart';

void main() {
  late Directory tmp;
  late String path;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('materde-shelf-config');
    path = '${tmp.path}/shelf.json';
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('missing file loads as a first run with no pins', () {
    final config = ShelfConfig.load(path: path);
    expect(config.existed, isFalse);
    expect(config.pinned, isEmpty);
    expect(config.path, path);
  });

  test('initial(...).save() round trips through load()', () async {
    await ShelfConfig.initial(<String>['a.desktop', 'b.desktop'], path: path)
        .save();
    expect(File(path).readAsStringSync(), contains('a.desktop'));

    final config = ShelfConfig.load(path: path);
    expect(config.existed, isTrue);
    expect(config.pinned, <String>['a.desktop', 'b.desktop']);
  });

  test('corrupt file loads as existing with no pins', () {
    File(path).writeAsStringSync('{not json');
    final config = ShelfConfig.load(path: path);
    expect(config.existed, isTrue);
    expect(config.pinned, isEmpty);
  });

  test('initial() pins are immutable', () {
    final config = ShelfConfig.initial(<String>['a.desktop'], path: path);
    expect(() => config.pinned.add('b.desktop'), throwsUnsupportedError);
  });
}
