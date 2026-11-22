import 'package:cupertino_ui/cupertino_ui.dart';

import 'bear_avatar.dart';
import 'record_image.dart';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'app_appearance.dart';
import 'tuantuan.dart';

abstract final class Palette {
  static const paper = Color(0xFFF6F3EA);
  static const ink = Color(0xFF161C18);
  static const forest = Color(0xFF173E2E);
  static const stamp = Color(0xFFFF4A1A);
  static const sun = Color(0xFFFFB81C);
  static const muted = Color(0xFF5A665E);
}

ThemeData buildTheme(
  Brightness brightness, {
  AppAppearance appearance = AppAppearance.classic,
}) {
  if (appearance == AppAppearance.tuantuan) return _tuanTuanTheme(brightness);
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: Palette.forest,
    brightness: brightness,
    primary: dark ? const Color(0xFF7ED3A6) : Palette.forest,
    surface: dark ? const Color(0xFF212722) : Colors.white,
    onSurface: dark ? const Color(0xFFF2EFE6) : Palette.ink,
    secondary: dark ? const Color(0xFFFF6B3D) : const Color(0xFFB33112),
  );
  return ThemeData(
    extensions: const [AppearanceTheme(AppAppearance.classic)],
    colorScheme: colors,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? const Color(0xFF171B18) : Palette.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF171B18) : Palette.paper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      ),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 17, height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5),
      bodySmall: TextStyle(fontSize: 13, height: 1.45),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: .6),
    ),
  );
}

ThemeData _tuanTuanTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF65BB3C),
    primary: dark ? const Color(0xFF9CE575) : const Color(0xFF477A2B),
    onPrimary: dark ? const Color(0xFF17340D) : Colors.white,
    primaryContainer: dark ? const Color(0xFF2D4025) : const Color(0xFFEFF8DF),
    onPrimaryContainer: dark
        ? const Color(0xFFDEF3CC)
        : const Color(0xFF315523),
    secondary: dark ? const Color(0xFFFFC776) : const Color(0xFF8A4D0A),
    secondaryContainer: dark
        ? const Color(0xFF49341D)
        : const Color(0xFFFFF2D9),
    onSecondaryContainer: dark
        ? const Color(0xFFFFE7C5)
        : const Color(0xFF78420A),
    surface: dark ? const Color(0xFF242B22) : Colors.white,
    onSurface: dark ? const Color(0xFFF2F5EC) : const Color(0xFF3E443B),
    onSurfaceVariant: dark ? const Color(0xFFBEC9B7) : const Color(0xFF626B5B),
    outline: dark ? const Color(0xFF8E9B85) : const Color(0xFF7A8771),
    outlineVariant: dark ? const Color(0xFF46513F) : const Color(0xFFDCE5D4),
  );
  final base = buildTheme(brightness);
  final background = dark ? const Color(0xFF191F18) : const Color(0xFFFFFEFB);
  return base.copyWith(
    extensions: const [AppearanceTheme(AppAppearance.tuantuan)],
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: colors.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: colors.onSurface,
      ),
    ),
    textTheme: base.textTheme
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
        .copyWith(
          headlineLarge: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: colors.onSurface,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: colors.onSurface,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: colors.onSurface,
          ),
          bodySmall: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: colors.onSurfaceVariant,
          ),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark
            ? const Color(0xFF9CE575)
            : const Color(0xFF65BB3C),
        foregroundColor: const Color(0xFF1F3F13),
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 2,
        shadowColor: const Color(0xFF499027),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.outline, width: 2),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.outline, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant),
  );
}

class Paper extends StatelessWidget {
  const Paper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(isTuanTuan(context) ? 24 : 20),
      side: isTuanTuan(context)
          ? BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            )
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class CategoryMark extends StatelessWidget {
  const CategoryMark(this.category, {super.key, this.size = 46});
  final String category;
  final double size;
  static String label(String c) => switch (c) {
    'study' => '学习',
    'exercise' => '运动',
    'food' => '饮食',
    'sleep' => '作息',
    'water' => '饮水',
    'mindfulness' => '冥想',
    'custom' => '自定义',
    _ => 'ALL',
  };
  static IconData icon(String c) => switch (c) {
    'study' => CupertinoIcons.book,
    'exercise' => Icons.directions_run_rounded,
    'food' => Icons.restaurant_outlined,
    'sleep' => CupertinoIcons.moon,
    'water' => CupertinoIcons.drop,
    'mindfulness' => CupertinoIcons.leaf_arrow_circlepath,
    'custom' => CupertinoIcons.star,
    _ => CupertinoIcons.square_grid_2x2,
  };
  static Color color(String c) => switch (c) {
    'exercise' => const Color(0xFFBA391A),
    'food' => const Color(0xFF775600),
    'custom' => const Color(0xFF5A665E),
    _ => Palette.forest,
  };
  @override
  Widget build(BuildContext context) => Semantics(
    label: label(category),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isTuanTuan(context)
            ? Theme.of(context).colorScheme.primaryContainer
            : category == 'food'
            ? Palette.sun.withValues(alpha: .28)
            : color(category).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon(category),
        size: size * .5,
        color: isTuanTuan(context)
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFADCEBA)
            : color(category),
      ),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(
    this.name, {
    super.key,
    this.url,
    this.userId,
    this.size = 44,
  });
  final String name;
  final String? url, userId;
  final double size;
  @override
  Widget build(BuildContext context) {
    final preset = url?.startsWith('preset:bear-') == true
        ? int.tryParse(url!.split('-').last)
        : null;
    if (url == null || url!.isEmpty || url!.startsWith('preset:')) {
      return Semantics(
        label: '$name 的小熊头像',
        child: BearAvatar(
          index: preset == null ? bearIndex(userId ?? name) : preset - 1,
          size: size,
        ),
      );
    }
    return ClipOval(
      child: RecordImage(url!, width: size, height: size, variant: 'original'),
    );
  }
}

class StampLabel extends StatelessWidget {
  const StampLabel({super.key, this.text = '已盖章', this.compact = false});
  final String text;
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary,
          width: 1.5,
        ),
        color: isTuanTuan(context)
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        borderRadius: BorderRadius.circular(isTuanTuan(context) ? 14 : 7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 12 : 15,
        ),
      ),
    ),
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: onRefresh == null
            ? list
            : RefreshIndicator(
                onRefresh: () async {
                  try {
                    await onRefresh!();
                  } catch (error) {
                    if (context.mounted) feedback(context, error.toString());
                  }
                },
                child: list,
              ),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;
  @override
  Widget build(BuildContext context) {
    final routes = ['/today', '/team', '/reports', '/plans'];
    final labels = ['今日', '小队', '周报', '计划'];
    final icons = [
      CupertinoIcons.sun_max,
      CupertinoIcons.person_2,
      CupertinoIcons.chart_bar,
      CupertinoIcons.square_list,
    ];
    final index = routes.indexWhere((r) => location.startsWith(r)).clamp(0, 3);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/checkin'),
        tooltip: '拍照打卡',
        backgroundColor: isTuanTuan(context)
            ? Theme.of(context).colorScheme.primaryContainer
            : Palette.forest,
        foregroundColor: isTuanTuan(context)
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Colors.white,
        shape: isTuanTuan(context)
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: const Icon(CupertinoIcons.camera),
      ),
      floatingActionButtonLocation: ios
          ? FloatingActionButtonLocation.centerDocked
          : FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: ios
          ? CupertinoTabBar(
              currentIndex: index,
              onTap: (i) => context.go(routes[i]),
              activeColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              items: List.generate(
                4,
                (i) => BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(
                      right: i == 1 ? 22 : 0,
                      left: i == 2 ? 22 : 0,
                    ),
                    child: Icon(icons[i]),
                  ),
                  label: labels[i],
                ),
              ),
            )
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(routes[i]),
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
              ),
            ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String description, {
  String accept = '确认',
}) async =>
    await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accept),
          ),
        ],
      ),
    ) ??
    false;

void feedback(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
