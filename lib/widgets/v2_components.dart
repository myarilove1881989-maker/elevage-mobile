export '../theme/design_system_v2.dart' show V2InputDecoration;
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_system_v2.dart';

/// Visual field spacing shared by existing inputs; their controllers and
/// validators remain the sole source of business values.
class V2Field extends StatelessWidget {
  const V2Field({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey != LogicalKeyboardKey.tab)
          V2DraftScope.maybeOf(context)?.markChanged();
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) => V2DraftScope.maybeOf(context)?.markChanged(),
        child: child,
      ),
    ),
  );
}

abstract interface class V2DraftActions {
  void markChanged();
  void confirmed();
  Future<void> home();
}

class V2DraftScope extends InheritedWidget {
  const V2DraftScope({super.key, required this.state, required super.child});
  final V2DraftActions state;
  static V2DraftActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<V2DraftScope>()?.state ??
      V2ScaffoldState._pages[ModalRoute.of(context)];
  @override
  bool updateShouldNotify(V2DraftScope oldWidget) => oldWidget.state != state;
}

class V2Scaffold extends StatefulWidget {
  const V2Scaffold({
    super.key,
    this.appBar,
    this.body,
    this.drawer,
    this.endDrawer,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.protectDraft = false,
    this.isDashboard = false,
    this.busy = false,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body,
      drawer,
      endDrawer,
      floatingActionButton,
      bottomNavigationBar,
      bottomSheet;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody,
      extendBodyBehindAppBar,
      protectDraft,
      isDashboard,
      busy;
  @override
  State<V2Scaffold> createState() => V2ScaffoldState();
}

class V2ScaffoldState extends State<V2Scaffold> implements V2DraftActions {
  static final _homes = <NavigatorState, Route<dynamic>>{};
  static final _pages = <Route<dynamic>?, V2DraftActions>{};
  Route<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    });
  }

  bool changed = false, leaving = false, asking = false;
  @override
  void markChanged() {
    if (widget.protectDraft && !changed && !leaving)
      setState(() => changed = true);
  }

  @override
  void confirmed() {
    if (mounted) setState(() => changed = false);
  }

  Future<bool> confirmLeave() async {
    if (widget.busy) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Enregistrement en cours…')),
      );
      return false;
    }
    if (!changed || leaving) return true;
    if (asking) return false;
    asking = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Quitter la saisie ?'),
        content: const Text(
          'Les informations non enregistrées seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    asking = false;
    return result == true;
  }

  @override
  Future<void> home() async {
    if (!await confirmLeave() || !mounted) return;
    setState(() => leaving = true);
    final navigator = Navigator.of(context),
        target = _homes[Navigator.of(context)];
    navigator.popUntil((route) => route == target || route.isFirst);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route != null) _pages[_route] = this;
    if (widget.isDashboard) {
      final route = ModalRoute.of(context);
      if (route != null) _homes[Navigator.of(context)] = route;
    }
  }

  @override
  void dispose() {
    if (_pages[_route] == this) _pages.remove(_route);
    _homes.removeWhere((_, route) => route == _route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: V2DraftScope(
      state: this,
      child: PopScope(
        canPop: !widget.busy && (!changed || leaving),
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !await confirmLeave() || !mounted) return;
          setState(() => leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop(result);
          });
        },
        child: Scaffold(
          appBar:
              widget.appBar ??
              (Navigator.of(context).canPop()
                  ? const V2AppBar(title: Text('Élev’Age'))
                  : null),
          body: widget.body,
          drawer: widget.drawer,
          endDrawer: widget.endDrawer,
          floatingActionButton: widget.floatingActionButton,
          floatingActionButtonLocation: widget.floatingActionButtonLocation,
          bottomNavigationBar: widget.bottomNavigationBar,
          bottomSheet: widget.bottomSheet,
          backgroundColor: widget.backgroundColor,
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          extendBody: widget.extendBody,
          extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
        ),
      ),
    ),
  );
}

class V2HomeButton extends StatelessWidget {
  const V2HomeButton({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void home() {
        final state = V2DraftScope.maybeOf(context);
        if (state != null) {
          state.home();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }

      if (MediaQuery.sizeOf(context).width < 600)
        return IconButton(
          tooltip: 'Accueil',
          onPressed: home,
          icon: const Icon(Icons.home_outlined),
        );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white),
          ),
          onPressed: home,
          icon: const Icon(Icons.home_outlined),
          label: const Text('Accueil'),
        ),
      );
    },
  );
}

class V2AppBar extends StatelessWidget implements PreferredSizeWidget {
  const V2AppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.centerTitle = false,
    this.toolbarHeight = 64,
    this.elevation,
    this.automaticallyImplyLeading = true,
    this.showHome = true,
  });
  final Widget? title, leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor, foregroundColor;
  final bool centerTitle, automaticallyImplyLeading, showHome;
  final double toolbarHeight;
  final double? elevation;
  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    leading: leading,
    actions: [...?actions, if (showHome) const V2HomeButton()],
    bottom: bottom,
    backgroundColor: V2Colors.navy,
    foregroundColor: Colors.white,
    centerTitle: centerTitle,
    toolbarHeight: toolbarHeight,
    elevation: elevation,
    automaticallyImplyLeading: automaticallyImplyLeading,
  );
}

class V2Help extends StatelessWidget {
  const V2Help({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: IconButton(
      tooltip: 'Informations : $title',
      icon: const Icon(Icons.info_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: child),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Navigation only after the caller has validated its existing success contract.
/// Pending offline declarations and uncertain responses must not call this.
void v2Confirmed(
  BuildContext context, {
  String message = 'Enregistrement confirmé',
  Object? result = true,
}) {
  V2DraftScope.maybeOf(context)?.confirmed();
  final navigator = Navigator.of(context),
      messenger = ScaffoldMessenger.maybeOf(context);
  if (navigator.canPop()) navigator.pop(result);
  messenger?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

String v2Day(Object? raw) {
  final text = raw?.toString() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  return match == null
      ? (text.isEmpty ? 'Non renseignée' : text)
      : '${match[3]}/${match[2]}/${match[1]}';
}

String v2Moment(Object? raw) {
  if (raw == null) return 'Non renseignée';
  final d = DateTime.tryParse('$raw')?.toLocal();
  if (d == null) return v2Day(raw);
  String n(int x) => x.toString().padLeft(2, '0');
  return '${n(d.day)}/${n(d.month)}/${d.year} ${n(d.hour)}:${n(d.minute)}';
}

class V2DateField extends StatefulWidget {
  const V2DateField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.withTime = false,
    this.firstDate,
    this.lastDate,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled, withTime;
  final DateTime? firstDate, lastDate;
  @override
  State<V2DateField> createState() => _V2DateFieldState();
}

class _V2DateFieldState extends State<V2DateField> {
  late final display = TextEditingController(text: formatted());
  bool updating = false;
  String formatted() => widget.controller.text.isEmpty
      ? ''
      : widget.withTime
      ? v2Moment(widget.controller.text)
      : v2Day(widget.controller.text);
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(sync);
  }

  void sync() {
    if (!updating) display.text = formatted();
  }

  @override
  void dispose() {
    widget.controller.removeListener(sync);
    display.dispose();
    super.dispose();
  }

  void store(DateTime date) {
    final previous = DateTime.tryParse(widget.controller.text);
    // Keep an existing UTC representation and full precision when only date/time
    // components are changed; storage/validation stays owned by the caller.
    final value = widget.withTime
        ? (previous?.isUtc == true ? date.toUtc() : date).toIso8601String()
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    widget.controller.text = value;
    V2DraftScope.maybeOf(context)?.markChanged();
  }

  Future<void> choose() async {
    final initial =
        DateTime.tryParse(widget.controller.text)?.toLocal() ?? DateTime.now();
    final first = widget.firstDate ?? DateTime(1900),
        last = widget.lastDate ?? DateTime(2100);
    final day = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : initial.isAfter(last)
          ? last
          : initial,
      firstDate: first,
      lastDate: last,
    );
    if (day == null || !mounted) return;
    if (!widget.withTime) {
      store(day);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null && mounted)
      store(
        DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
          initial.second,
          initial.millisecond,
          initial.microsecond,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => V2Field(
    child: TextField(
      controller: display,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      decoration: V2InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.calendar_month_outlined),
        suffixIcon: IconButton(
          tooltip: 'Choisir une date',
          onPressed: widget.enabled ? choose : null,
          icon: const Icon(Icons.expand_more),
        ),
      ),
      onChanged: (text) {
        updating = true;
        final match = RegExp(
          r'^(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{2}):(\d{2}))?$',
        ).firstMatch(text);
        widget.controller.text = match == null
            ? text
            : '${match[3]}-${match[2]}-${match[1]}${widget.withTime ? 'T${match[4] ?? '00'}:${match[5] ?? '00'}:00' : ''}';
        updating = false;
        V2DraftScope.maybeOf(context)?.markChanged();
      },
    ),
  );
}

class V2DateSelection extends StatefulWidget {
  const V2DateSelection({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  @override
  State<V2DateSelection> createState() => _V2DateSelectionState();
}

class _V2DateSelectionState extends State<V2DateSelection> {
  DateTime focus = DateTime.now();
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            focusedDay: focus,
            locale: 'fr',
            availableGestures: AvailableGestures.horizontalSwipe,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: V2Colors.green,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Color(0xFFE1F3E8),
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(color: V2Colors.navy),
            ),
            selectedDayPredicate: (day) => widget.selected.contains(iso(day)),
            onPageChanged: (day) => focus = day,
            onDaySelected: !widget.enabled
                ? null
                : (day, current) {
                    setState(() => focus = current);
                    final next = {...widget.selected};
                    final value = iso(day);
                    if (!next.remove(value)) next.add(value);
                    widget.onChanged(next);
                    V2DraftScope.maybeOf(context)?.markChanged();
                  },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in widget.selected.toList()..sort())
                InputChip(
                  label: Text(v2Day(day)),
                  onDeleted: widget.enabled
                      ? () {
                          final next = {...widget.selected}..remove(day);
                          widget.onChanged(next);
                          V2DraftScope.maybeOf(context)?.markChanged();
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class V2DurationField extends StatefulWidget {
  const V2DurationField({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  final TextEditingController controller;
  final bool enabled;
  @override
  State<V2DurationField> createState() => _V2DurationFieldState();
}

class _V2DurationFieldState extends State<V2DurationField> {
  late final minutes = TextEditingController(
    text: widget.controller.text.isEmpty
        ? ''
        : '${(num.tryParse(widget.controller.text) ?? 0) / 60}',
  );
  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => V2Field(
    child: TextField(
      controller: minutes,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const V2InputDecoration(
        labelText: 'Durée après ouverture (minutes, facultative)',
        prefixIcon: Icon(Icons.timer_outlined),
      ),
      onChanged: (text) {
        final n = num.tryParse(text.replaceAll(',', '.'));
        widget.controller.text = text.isEmpty
            ? ''
            : n != null && (n * 60) % 1 == 0
            ? '${(n * 60).toInt()}'
            : 'invalide';
      },
    ),
  );
}

class V2Pair extends StatelessWidget {
  const V2Pair({super.key, required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 700 || MediaQuery.textScalerOf(context).scale(16) > 22)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    },
  );
}

class V2PickerTile extends StatelessWidget {
  const V2PickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: V2Colors.border, width: 1.25),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: V2Colors.green, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.expand_more),
          ],
        ),
      ),
    ),
  );
}

class V2AlertDialog extends StatelessWidget {
  const V2AlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.icon,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
    this.insetPadding,
    this.backgroundColor,
    this.shape,
    this.scrollable = false,
    this.actionsAlignment,
    this.buttonPadding,
    this.semanticLabel,
  });
  final Widget? title, content, icon;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? titlePadding,
      contentPadding,
      actionsPadding,
      buttonPadding;
  final EdgeInsets? insetPadding;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final bool scrollable;
  final MainAxisAlignment? actionsAlignment;
  final String? semanticLabel;
  String label(Widget? widget) {
    if (widget is Text)
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (widget is Row) return widget.children.map(label).join(' ').trim();
    if (widget is Flexible) return label(widget.child);
    return '';
  }

  bool cancel(Widget widget) =>
      widget is ButtonStyleButton &&
      {
        'Annuler',
        'Fermer',
        'Retour',
        'Non',
        'Cancel',
        'Close',
      }.contains(label(widget.child));
  @override
  Widget build(BuildContext context) {
    final positive = (actions ?? [])
        .whereType<ButtonStyleButton>()
        .where((button) => !cancel(button))
        .toList();
    return _V2DialogGuard(
      busy:
          positive.isNotEmpty &&
          (actions ?? []).whereType<ButtonStyleButton>().every(
            (button) => button.onPressed == null,
          ),
      builder: (context, state) {
        Widget action(Widget widget) {
          if (!cancel(widget)) {
            if (widget is TextButton) {
              final text = label(widget.child).toLowerCase();
              final destructive =
                  text.contains('supprim') ||
                  text.contains('annulation') ||
                  text.contains('delete');
              return TextButton(
                key: widget.key,
                onPressed: widget.onPressed,
                onLongPress: widget.onLongPress,
                style: TextButton.styleFrom(
                  backgroundColor: destructive
                      ? Theme.of(context).colorScheme.error
                      : V2Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: Colors.grey.shade700,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ).merge(widget.style),
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                child: widget.child!,
              );
            }
            return widget;
          }
          final button = widget as ButtonStyleButton;
          final VoidCallback? callback = button.onPressed == null
              ? null
              : () async {
                  if (await state.confirmLeave() && context.mounted)
                    button.onPressed!();
                };
          if (button is TextButton)
            return TextButton(
              key: button.key,
              onPressed: callback,
              onLongPress: button.onLongPress,
              style: TextButton.styleFrom(
                foregroundColor: V2Colors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: V2Colors.border, width: 1.25),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ).merge(button.style),
              focusNode: button.focusNode,
              autofocus: button.autofocus,
              child: button.child!,
            );
          if (button is OutlinedButton)
            return OutlinedButton(
              key: button.key,
              onPressed: callback,
              onLongPress: button.onLongPress,
              style: TextButton.styleFrom(
                foregroundColor: V2Colors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: V2Colors.border, width: 1.25),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ).merge(button.style),
              focusNode: button.focusNode,
              autofocus: button.autofocus,
              child: button.child!,
            );
          if (button is FilledButton)
            return FilledButton(
              key: button.key,
              onPressed: callback,
              onLongPress: button.onLongPress,
              style: TextButton.styleFrom(
                foregroundColor: V2Colors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: V2Colors.border, width: 1.25),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ).merge(button.style),
              focusNode: button.focusNode,
              autofocus: button.autofocus,
              child: button.child!,
            );
          if (button is ElevatedButton)
            return ElevatedButton(
              key: button.key,
              onPressed: callback,
              onLongPress: button.onLongPress,
              style: TextButton.styleFrom(
                foregroundColor: V2Colors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: V2Colors.border, width: 1.25),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ).merge(button.style),
              focusNode: button.focusNode,
              autofocus: button.autofocus,
              child: button.child!,
            );
          return widget;
        }

        return AlertDialog(
          title: title,
          content: content,
          actions: actions?.map(action).toList(),
          icon: icon,
          titlePadding: titlePadding,
          contentPadding:
              contentPadding ?? const EdgeInsets.fromLTRB(24, 20, 24, 24),
          actionsPadding: actionsPadding,
          insetPadding:
              insetPadding ??
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: backgroundColor ?? Colors.white,
          shape:
              shape ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: V2Colors.border, width: 1.25),
              ),
          scrollable: scrollable,
          actionsAlignment: actionsAlignment,
          buttonPadding: buttonPadding,
          semanticLabel: semanticLabel,
        );
      },
    );
  }
}

class _V2DialogGuard extends StatefulWidget {
  const _V2DialogGuard({required this.builder, this.busy = false});
  final Widget Function(BuildContext, _V2DialogGuardState) builder;
  final bool busy;
  @override
  State<_V2DialogGuard> createState() => _V2DialogGuardState();
}

class _V2DialogGuardState extends State<_V2DialogGuard>
    implements V2DraftActions {
  bool changed = false, leaving = false, asking = false;
  Route<dynamic>? route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    if (route != null) V2ScaffoldState._pages[route] = this;
  }

  @override
  void dispose() {
    if (V2ScaffoldState._pages[route] == this)
      V2ScaffoldState._pages.remove(route);
    super.dispose();
  }

  @override
  void markChanged() {
    if (!changed && mounted) setState(() => changed = true);
  }

  @override
  void confirmed() {
    if (mounted) setState(() => changed = false);
  }

  Future<bool> confirmLeave() async {
    if (widget.busy) return false;
    if (!changed || leaving) return true;
    if (asking) return false;
    asking = true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Quitter la saisie ?'),
        content: const Text(
          'Les informations non enregistrées seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Continuer la saisie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    asking = false;
    return choice == true;
  }

  @override
  Future<void> home() async {
    if (await confirmLeave() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => V2DraftScope(
    state: this,
    child: PopScope(
      canPop: !widget.busy && (!changed || leaving),
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await confirmLeave() && mounted) {
          setState(() => leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop(result);
          });
        }
      },
      child: widget.builder(context, this),
    ),
  );
}
