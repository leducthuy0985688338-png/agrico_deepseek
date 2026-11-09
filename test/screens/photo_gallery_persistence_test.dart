import 'dart:async';
import 'package:agrico_deepseek/widgets/photo_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('photo removal waits for persistence and disables duplicate actions', (tester) async {
    final gate = Completer<void>(); var calls = 0; final paths = ['missing-photo.jpg'];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, refresh) => PhotoGallery(
      photoPaths: List.of(paths), onAddPhoto: (_) async {}, onRemovePhoto: (_) async {
        calls++; await gate.future; refresh(() { paths.clear(); });
      },
    )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close)); await tester.pump();
    expect(calls, 1); expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close)); await tester.pump(); expect(calls, 1);
    gate.complete(); await tester.pumpAndSettle();
    expect(paths, isEmpty); expect(find.byIcon(Icons.close), findsNothing);
  });
  testWidgets('photo persistence error retains the list and permits retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PhotoGallery(photoPaths: const ['missing-photo.jpg'],
      onAddPhoto: (_) async {}, onRemovePhoto: (_) async { calls++; throw StateError('disk'); }))));
    await tester.pumpAndSettle(); await tester.tap(find.byIcon(Icons.close)); await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.textContaining('Không thể cập nhật danh sách ảnh'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close)); await tester.pumpAndSettle(); expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
