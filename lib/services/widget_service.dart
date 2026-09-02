import 'package:home_widget/home_widget.dart';
import '../db/db_helper.dart';

/// Pushes a fresh summary (pending/overdue counts + up to 3 most urgent
/// ideas) to the home screen widget. Everything is saved as a String —
/// deliberately avoiding saveWidgetData<int>, since numeric storage had
/// known bugs in the older home_widget version this project is pinned
/// to (needed for Dart SDK compatibility with this project's Flutter
/// version).
class WidgetService {
  static const providerName = 'MyManagerWidgetProvider';

  static Future<void> update() async {
    try {
      final ideas = await DBHelper.getAllActiveIdeas();
      final active = ideas.where((i) => i.status != 'done').toList();
      final pending = active.length;
      final overdue = active.where((i) => i.isOverdue).length;

      // Overdue first, then soonest deadline, then no-deadline items last.
      active.sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
        if (a.deadline != null && b.deadline != null) {
          return a.deadline!.compareTo(b.deadline!);
        }
        if (a.deadline != null) return -1;
        if (b.deadline != null) return 1;
        return 0;
      });
      final top = active.take(3).toList();

      await HomeWidget.saveWidgetData<String>('pending_count', '$pending');
      await HomeWidget.saveWidgetData<String>('overdue_count', '$overdue');
      await HomeWidget.saveWidgetData<String>(
          'idea_1', top.isNotEmpty ? top[0].title : '');
      await HomeWidget.saveWidgetData<String>(
          'idea_2', top.length > 1 ? top[1].title : '');
      await HomeWidget.saveWidgetData<String>(
          'idea_3', top.length > 2 ? top[2].title : '');

      await HomeWidget.updateWidget(name: providerName);
    } catch (_) {
      // A failed widget refresh should never affect the rest of the app.
    }
  }
}
