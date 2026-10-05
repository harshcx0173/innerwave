import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/social/listening_room_sheet.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 8, 30); // 02:00 PM IST

  test('shows relative minutes for messages under one hour', () {
    expect(formatRoomTime(DateTime.utc(2026, 10, 5, 8, 5).toIso8601String(), now: now), '25m');
  });

  test('shows an IST clock for older messages from today', () {
    expect(formatRoomTime(DateTime.utc(2026, 10, 5, 6, 15).toIso8601String(), now: now), '11:45 AM');
  });

  test('shows Yesterday with an IST 12-hour clock', () {
    expect(formatRoomTime(DateTime.utc(2026, 10, 4, 12, 15).toIso8601String(), now: now), 'Yesterday 5:45 PM');
  });

  test('shows DD/MM/YYYY and IST time for older messages', () {
    expect(formatRoomTime(DateTime.utc(2026, 10, 2, 20, 30).toIso8601String(), now: now), '03/10/2026 2:00 AM');
  });
}
