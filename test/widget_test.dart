import 'project_fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/main.dart';

void main() {
  testWidgets('starts with the offline import workflow', (tester) async {
    await tester.pumpWidget(LocalCutApp(projects: MemoryProjects()));
    expect(find.text('Import video from Files'), findsOneWidget);
    expect(find.text('Less cleanup.\nMore creating.'), findsOneWidget);
  });
}
