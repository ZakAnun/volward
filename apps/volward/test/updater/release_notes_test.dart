import 'package:flutter_test/flutter_test.dart';
import 'package:volward/widgets/update_available_dialog.dart';

void main() {
  group('summarizeReleaseNotes', () {
    test('returns empty for null, empty, or whitespace-only body', () {
      expect(summarizeReleaseNotes(null), '');
      expect(summarizeReleaseNotes(''), '');
      expect(summarizeReleaseNotes('   '), '');
    });

    test('returns full text when within maxChars', () {
      const notes = 'Bug fixes and performance improvements.';
      expect(summarizeReleaseNotes(notes), notes);
      expect(summarizeReleaseNotes(notes, maxChars: 400), notes);
    });

    test('truncates long text with ellipsis', () {
      final long = 'a' * 500;
      final result = summarizeReleaseNotes(long, maxChars: 400);
      expect(result.length, 401);
      expect(result.endsWith('…'), isTrue);
      expect(result.substring(0, 400), 'a' * 400);
    });
  });
}
