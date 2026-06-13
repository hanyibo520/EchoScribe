import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/asr/partial_preview.dart';

void main() {
  test('latest partial preview replaces previous recognition hypothesis', () {
    var preview = latestPartialPreviewText('，你多说两。');
    preview = latestPartialPreviewText('你多说两句话。');

    expect(preview, '你多说两句话。');
  });

  test('latest partial preview trims engine output', () {
    expect(latestPartialPreviewText('  你好。 \n'), '你好。');
  });
}
