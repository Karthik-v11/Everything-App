import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// [CalendarStrip] is the calendar above the task list (Requirement 4.1).
///
/// Two modes: a single week row, and a full month grid. A downward drag or a tap
/// on the chevron expands it, an upward drag collapses it. Swiping left and right
/// moves by a week or a month depending on the mode. A day holding open tasks
/// carries a dot (Requirement 4.2).
///
/// [focusedDate] is the highlighted day. [markedDates] must hold `dateOnly`
/// values — they are matched by equality. [onSelect] fires with the tapped day.
class CalendarStrip extends StatefulWidget {
  const CalendarStrip({
    required this.focusedDate,
    required this.markedDates,
    required this.onSelect,
    super.key,
  });

  final DateTime focusedDate;
  final Set<DateTime> markedDates;
  final ValueChanged<DateTime> onSelect;

  @override
  State<CalendarStrip> createState() => _CalendarStripState();
}

class _CalendarStripState extends State<CalendarStrip> {
  /// The origin page. Both modes page infinitely in either direction, so this is
  /// only where the offset zero sits.
  static const int _initialPage = 1200;

  static const double _rowHeight = 46;
  static const int _monthRows = 6;

  late final PageController _weekController;
  late final PageController _monthController;

  /// Pages are offsets from these anchors, so no list of dates is held.
  late final DateTime _baseWeek;
  late final DateTime _baseMonth;

  /// The month named in the header. It follows the visible page, not the
  /// selection.
  late DateTime _visibleMonth;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();

    _baseWeek = widget.focusedDate.startOfWeek;
    _baseMonth = widget.focusedDate.startOfMonth;
    _visibleMonth = _baseMonth;

    _weekController = PageController(initialPage: _initialPage);
    _monthController = PageController(initialPage: _initialPage);
  }

  @override
  void didUpdateWidget(CalendarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The focus also moves from outside the strip (the list is scrolled), so page
    // to whichever week or month now holds it.
    if (!widget.focusedDate.isSameDayAs(oldWidget.focusedDate)) {
      _animateTo(widget.focusedDate);
    }
  }

  @override
  void dispose() {
    _weekController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  int _weekPageOf(DateTime date) =>
      _initialPage + date.startOfWeek.difference(_baseWeek).inDays ~/ 7;

  int _monthPageOf(DateTime date) =>
      _initialPage +
      (date.year - _baseMonth.year) * 12 +
      (date.month - _baseMonth.month);

  DateTime _weekOfPage(int page) =>
      _baseWeek.add(Duration(days: (page - _initialPage) * 7));

  DateTime _monthOfPage(int page) =>
      DateTime(_baseMonth.year, _baseMonth.month + (page - _initialPage));

  void _animateTo(DateTime date) {
    final controller = _isExpanded ? _monthController : _weekController;
    final target = _isExpanded ? _monthPageOf(date) : _weekPageOf(date);

    if (!controller.hasClients || controller.page?.round() == target) return;

    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// [_setExpanded] switches mode and moves the incoming controller to the page
  /// holding the focused day.
  void _setExpanded(bool isExpanded) {
    if (isExpanded == _isExpanded) return;

    setState(() => _isExpanded = isExpanded);

    final controller = isExpanded ? _monthController : _weekController;
    final target = isExpanded
        ? _monthPageOf(widget.focusedDate)
        : _weekPageOf(widget.focusedDate);

    setState(() => _visibleMonth = widget.focusedDate.startOfMonth);

    // The incoming PageView is built during this frame, so its controller has no
    // clients until the frame completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) controller.jumpToPage(target);
    });
  }

  void _step(int direction) {
    final controller = _isExpanded ? _monthController : _weekController;
    if (!controller.hasClients) return;

    controller.animateToPage(
      (controller.page?.round() ?? _initialPage) + direction,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// A downward flick expands, an upward flick collapses. Keyed on velocity, so
  /// the gesture completes without dragging the grid its full height.
  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 120) _setExpanded(true);
    if (velocity < -120) _setExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: _onVerticalDragEnd,
      // Opaque, so the gaps between the day cells also receive the drag.
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            month: _visibleMonth,
            isExpanded: _isExpanded,
            onPrevious: () => _step(-1),
            onNext: () => _step(1),
            onToggle: () => _setExpanded(!_isExpanded),
          ),
          const _WeekdayLabels(),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: (_isExpanded ? _monthRows : 1) * _rowHeight,
              child: _isExpanded ? _monthPages() : _weekPages(),
            ),
          ),
          _DragHandle(
            isExpanded: _isExpanded,
            onTap: () => _setExpanded(!_isExpanded),
          ),
        ],
      ),
    );
  }

  Widget _weekPages() {
    return PageView.builder(
      controller: _weekController,
      onPageChanged: (page) => setState(
        // Midweek names the header, so a week straddling two months does not flip
        // the title on a one-day overlap.
        () => _visibleMonth = _weekOfPage(page).add(const Duration(days: 3)),
      ),
      itemBuilder: (context, page) => _DayRow(
        start: _weekOfPage(page),
        focusedDate: widget.focusedDate,
        markedDates: widget.markedDates,
        onSelect: widget.onSelect,
      ),
    );
  }

  Widget _monthPages() {
    return PageView.builder(
      controller: _monthController,
      onPageChanged: (page) =>
          setState(() => _visibleMonth = _monthOfPage(page)),
      itemBuilder: (context, page) {
        final month = _monthOfPage(page);

        // The grid starts on the Monday on or before the 1st and always runs six
        // rows, so its height is the same for every month.
        final gridStart = month.startOfWeek;

        return Column(
          children: [
            for (var row = 0; row < _monthRows; row++)
              SizedBox(
                height: _rowHeight,
                child: _DayRow(
                  start: gridStart.add(Duration(days: row * 7)),
                  focusedDate: widget.focusedDate,
                  markedDates: widget.markedDates,
                  onSelect: widget.onSelect,
                  ownMonth: month.month,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.isExpanded,
    required this.onPrevious,
    required this.onNext,
    required this.onToggle,
  });

  final DateTime month;
  final bool isExpanded;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: context.texts.titleMedium,
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onPrevious,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          color: context.colors.onSurfaceVariant,
          tooltip: isExpanded ? 'Previous month' : 'Previous week',
        ),
        IconButton(
          onPressed: onNext,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          color: context.colors.onSurfaceVariant,
          tooltip: isExpanded ? 'Next month' : 'Next week',
        ),
      ],
    );
  }
}

/// [_WeekdayLabels] is the fixed M–S header. It sits outside the [PageView] so it
/// does not slide with the dates.
class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  @override
  Widget build(BuildContext context) {
    // Any Monday will do; only the weekday names are read off it.
    final monday = DateTime.now().startOfWeek;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                monday.add(Duration(days: i)).weekdayInitial,
                textAlign: TextAlign.center,
                style: context.texts.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// [_DayRow] is seven day cells starting at [start].
///
/// [ownMonth] is the month the grid belongs to; days spilling in from the
/// neighbouring months are faded. Null in week mode, where every day belongs.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.start,
    required this.focusedDate,
    required this.markedDates,
    required this.onSelect,
    this.ownMonth,
  });

  final DateTime start;
  final DateTime focusedDate;
  final Set<DateTime> markedDates;
  final ValueChanged<DateTime> onSelect;
  final int? ownMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayCell(
              date: start.add(Duration(days: i)),
              focusedDate: focusedDate,
              markedDates: markedDates,
              ownMonth: ownMonth,
              onTap: onSelect,
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.focusedDate,
    required this.markedDates,
    required this.ownMonth,
    required this.onTap,
  });

  final DateTime date;
  final DateTime focusedDate;
  final Set<DateTime> markedDates;
  final int? ownMonth;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final isSelected = date.isSameDayAs(focusedDate);
    final isOutside = ownMonth != null && date.month != ownMonth;
    final hasTasks = markedDates.contains(date.dateOnly);

    final foreground = isSelected
        ? colors.onPrimary
        : isOutside
            ? colors.onSurfaceVariant.withValues(alpha: 0.4)
            : date.isToday
                ? colors.primary
                : colors.onSurface;

    return Semantics(
      selected: isSelected,
      button: true,
      label: date.dashboardDate,
      child: InkResponse(
        onTap: () => onTap(date),
        radius: 24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: date.isToday && !isSelected
                    ? Border.all(color: colors.primary)
                    : null,
              ),
              child: Text(
                date.dayNumber,
                style: context.texts.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // The dot's space is reserved whether or not it is drawn, so a day
            // gaining its first task does not shift the row.
            SizedBox(
              height: 5,
              child: hasTasks
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        // Inverted on the selected cell, which is accent-filled.
                        color: isSelected ? colors.onPrimary : colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 5),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// [_DragHandle] is the grabber under the calendar. It is also a button, so the
/// expand gesture is reachable without discovering the drag.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.isExpanded, required this.onTap});

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isExpanded ? 'Collapse calendar' : 'Expand calendar',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
