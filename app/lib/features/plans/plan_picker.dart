import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_controller.dart';
import '../../domain/models.dart';

Future<Plan?> choosePlan(BuildContext context) => showModalBottomSheet<Plan>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _PlanPicker(),
);

class _PlanPicker extends ConsumerStatefulWidget {
  const _PlanPicker();
  @override
  ConsumerState<_PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends ConsumerState<_PlanPicker> {
  final query = TextEditingController();
  List<Plan> plans = [];
  bool busy = false;
  String? next, error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final current = ++generation;
    setState(() => busy = true);
    try {
      final data = jsonObject(
        await ref
            .read(repositoryProvider)
            .action(
              'read_page',
              args: {
                'collection': 'plans',
                'status': 'active',
                'query': query.text.trim(),
                if (more) 'cursor': next,
              },
            ),
      );
      if (!mounted || current != generation) return;
      final rows = jsonList(data['items'])
          .map((v) => Plan.fromJson(jsonObject(v)))
          .toList();
      setState(() {
        plans = more ? [...plans, ...rows] : rows;
        next = nullableString(data['next_cursor']);
        error = null;
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            TextField(
              controller: query,
              decoration: InputDecoration(
                labelText: '搜索计划名称',
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: load,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => load(),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: load, child: Text('$error，点击重试')),
            Expanded(
              child: ListView(
                children: [
                  ...plans.map(
                    (p) => ListTile(
                      title: Text(p.title),
                      subtitle: Text(p.scheduleLabel),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  ),
                  if (!busy && error == null && plans.isEmpty)
                    const ListTile(title: Text('没有找到计划')),
                  if (next != null)
                    TextButton(
                      onPressed: busy ? null : () => load(more: true),
                      child: const Text('加载更多'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlanDetailLoader extends ConsumerStatefulWidget {
  const PlanDetailLoader({super.key, required this.id, required this.builder});
  final String id;
  final Widget Function(Plan) builder;
  @override
  ConsumerState<PlanDetailLoader> createState() => _PlanDetailLoaderState();
}

class _PlanDetailLoaderState extends ConsumerState<PlanDetailLoader> {
  late Future<Object?> data = ref
      .read(repositoryProvider)
      .action('get_plan', args: {'id': widget.id});
  @override
  Widget build(BuildContext context) => FutureBuilder<Object?>(
    future: data,
    builder: (context, s) {
      if (s.hasData) return widget.builder(Plan.fromJson(jsonObject(s.data)));
      return Scaffold(
        appBar: AppBar(title: const Text('计划')),
        body: Center(
          child: s.hasError
              ? TextButton(
                  onPressed: () => setState(
                    () => data = ref
                        .read(repositoryProvider)
                        .action('get_plan', args: {'id': widget.id}),
                  ),
                  child: Text('${s.error}，点击重试'),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
