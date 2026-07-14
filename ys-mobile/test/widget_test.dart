import 'package:flutter_test/flutter_test.dart';
import 'package:ys_mobile/src/models/models.dart';

void main() {
  test('parses a completed call record', () {
    final log = ChatCallLog.tryParse(
      '{"kind":"audio","status":"completed","duration":75}',
    );

    expect(log, isNotNull);
    expect(log!.status, 'completed');
    expect(log.duration, 75);
    expect(log.isMissed, isFalse);
  });

  test('parses a missed call and rejects transient call statuses', () {
    final missed = ChatCallLog.tryParse(
      '{"kind":"audio","status":"missed","duration":0}',
    );

    expect(missed?.isMissed, isTrue);
    expect(ChatCallLog.tryParse('Cuộc gọi bị từ chối'), isNull);
    expect(ChatCallLog.tryParse('Người kia đang bận'), isNull);
    expect(ChatCallLog.tryParse('Cuộc gọi đã hủy'), isNull);
  });
  test('parses scoped chat search results', () {
    final results = ChatSearchResults.fromJson({
      'contacts': [
        {'userid': 'NV001', 'fullname': 'Lan', 'nickname': 'Chi Lan'},
      ],
      'messages': [
        {
          'id': 11,
          'conversationId': 7,
          'senderUserid': 'NV001',
          'senderName': 'Lan',
          'type': 'text',
          'content': 'bao cao',
        },
      ],
      'files': [
        {
          'id': 12,
          'conversationId': 7,
          'senderUserid': 'NV001',
          'senderName': 'Lan',
          'type': 'file',
          'attachments': [
            {'id': 1, 'fileName': 'bao-cao.pdf'},
          ],
        },
      ],
    });

    expect(results.contacts.single.displayName, 'Chi Lan');
    expect(results.messages.single.content, 'bao cao');
    expect(results.files.single.attachments.single.fileName, 'bao-cao.pdf');
  });
}
