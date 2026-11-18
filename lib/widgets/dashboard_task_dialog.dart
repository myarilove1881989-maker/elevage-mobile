import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_system_v2.dart';

// Published Web dialog behavior, scoped in memory to this dialog only.
class DashboardTaskField extends StatelessWidget {
  const DashboardTaskField({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey != LogicalKeyboardKey.tab)
          DashboardDialogScope.maybeOf(context)?.markChanged();
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) => DashboardDialogScope.maybeOf(context)?.markChanged(),
        child: child,
      ),
    ),
  );
}

abstract interface class DashboardDialogActions {
  void markChanged();
  void confirmed();
  Future<void> home();
}

class DashboardDialogScope extends InheritedWidget {
  const DashboardDialogScope({super.key, required this.state, required super.child});
  final DashboardDialogActions state;
  static DashboardDialogActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardDialogScope>()?.state;
  @override
  bool updateShouldNotify(DashboardDialogScope oldWidget) => oldWidget.state != state;
}

String dashboardDay(Object? raw) {
  final text = raw?.toString() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  return match == null
      ? (text.isEmpty ? 'Non renseignée' : text)
      : '${match[3]}/${match[2]}/${match[1]}';
}

class DashboardPickerTile extends StatelessWidget {
  const DashboardPickerTile({
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

class DashboardTaskDialog extends StatelessWidget {
  const DashboardTaskDialog({
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
    return _DashboardDialogGuard(
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

class _DashboardDialogGuard extends StatefulWidget {
  const _DashboardDialogGuard({required this.builder, this.busy = false});
  final Widget Function(BuildContext, _DashboardDialogGuardState) builder;
  final bool busy;
  @override
  State<_DashboardDialogGuard> createState() => _DashboardDialogGuardState();
}

class _DashboardDialogGuardState extends State<_DashboardDialogGuard>
    implements DashboardDialogActions {
  bool changed = false, leaving = false, asking = false;
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
    if (choice == true && mounted) setState(() => leaving = true);
    return choice == true;
  }

  @override
  Future<void> home() async {
    if (await confirmLeave() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => DashboardDialogScope(
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
