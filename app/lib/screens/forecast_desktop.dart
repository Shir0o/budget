import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'schedules_screen.dart';
import 'transaction_parts.dart';

/// How far ahead the desktop Forecast looks (ticket 67). Scheduled
/// Transactions are counted by month, so a range is the months it covers.
enum ForecastRange {
  month('30 days', 1, 30),
  quarter('90 days', 3, 90),
  year('1 year', 12, 365);

  const ForecastRange(this.label, this.months, this.days);

  final String label;

  /// The months [Forecast.of] is asked for.
  final int months;

  /// How many days of due dates Coming up lists.
  final int days;
}

/// Forecast in the desktop window (ticket 67): the predicted balance as a
/// chart with today, the lowest point and what the schedules spend, a Coming
/// up list beside it, and the 30 days / 90 days / 1 year range. The phone's
/// month-by-month list is unchanged.
class DesktopForecastScreen extends StatefulWidget {
  const DesktopForecastScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<DesktopForecastScreen> createState() => _DesktopForecastScreenState();
}

/// Below this content width Coming up wraps under the chart.
const _besideWidth = 1000.0;
const _comingWidth = 360.0;

class _DesktopForecastScreenState extends State<DesktopForecastScreen> {
  var _range = ForecastRange.month;

  BudgetState get _state => widget.engine.state;

  Future<void> _openSchedules() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SchedulesScreen(engine: widget.engine),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final forecast = Forecast.of(
      state,
      start: thisMonth(),
      months: _range.months,
    );
    // The balance today, then each month's end, is the line the chart draws.
    final balances = [
      forecast.startingBalance,
      for (final month in forecast.months) month.balance,
    ];
    var lowest = 0;
    for (final (i, balance) in balances.indexed) {
      if (balance.cents < balances[lowest].cents) lowest = i;
    }
    final lowestDate = lowest == 0
        ? 'Today'
        : formatDay(_endOf(forecast.months[lowest - 1].month));
    final expenses = forecast.months.fold<Money>(
      Money.zero,
      (total, month) => total + month.outflow,
    );
    final short = forecast.underfunded;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              // The range and the Schedules link sit on the title's line, or
              // under it when the window is narrow.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    'Forecast',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: Segmented<ForecastRange>(
                          options: [
                            for (final range in ForecastRange.values)
                              (range, range.label),
                          ],
                          selected: _range,
                          onChanged: (range) => setState(() => _range = range),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('forecast-schedules'),
                        onPressed: _openSchedules,
                        icon: const Icon(Icons.event_repeat, size: 16),
                        label: const Text('Scheduled transactions'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          textStyle: const TextStyle(
                            fontFamily: sansFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (short.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  key: const ValueKey('forecast-short'),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: Palette.problemPill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Palette.problemText,
                      ),
                      Expanded(
                        child: Text(
                          short.length == 1
                              ? '${monthName(short.single.month)} cannot cover '
                                    'its scheduled bills.'
                              : '${short.length} months cannot cover their '
                                    'scheduled bills.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Palette.problemText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chart = _ChartCard(
                    balances: balances,
                    lowest: lowest,
                    lowestDate: lowestDate,
                    expenses: expenses,
                    end: formatMonth(forecast.months.last.month),
                  );
                  final coming = _ComingUp(
                    key: const ValueKey('forecast-coming'),
                    state: state,
                    range: _range,
                  );
                  final scrollingComing = _ComingUp(
                    key: const ValueKey('forecast-coming'),
                    state: state,
                    range: _range,
                    scrollable: true,
                  );
                  if (constraints.maxWidth < _besideWidth) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [chart, coming],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Expanded(child: chart),
                        SizedBox(width: _comingWidth, child: scrollingComing),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last day of [month].
CivilDate _endOf(CalendarMonth month) =>
    CivilDate(month.year, month.month, 1).addMonths(1).addDays(-1);

/// Today's balance, the low point and what the schedules spend, above the
/// chart that draws them.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.balances,
    required this.lowest,
    required this.lowestDate,
    required this.expenses,
    required this.end,
  });

  /// Today's balance, then the predicted balance at each month's end.
  final List<Money> balances;
  final int lowest;
  final String lowestDate;

  /// What the Scheduled Transactions spend over the range.
  final Money expenses;

  /// The last month the line reaches.
  final String end;

  @override
  Widget build(BuildContext context) {
    final low = balances[lowest];
    return CardBox(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 28,
            children: [
              Expanded(
                child: _Stat(
                  label: 'TODAY',
                  value: balances.first.formatDollars(),
                  valueKey: 'forecast-today',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'LOWEST',
                  value: low.formatDollars(),
                  valueKey: 'forecast-lowest',
                  detail: low.compareTo(balances.first) < 0 ? lowestDate : null,
                  problem: low.isNegative,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'PREDICTED EXPENSES',
                  value: expenses.formatDollars(),
                  valueKey: 'forecast-expenses',
                ),
              ),
            ],
          ),
          SizedBox(
            height: 200,
            child: CustomPaint(
              key: const ValueKey('forecast-chart'),
              painter: _BalanceChart(balances: balances, lowest: lowest),
              child: const SizedBox.expand(),
            ),
          ),
          Text(
            'Today to $end',
            style: const TextStyle(fontSize: 11, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.valueKey,
    this.detail,
    this.problem = false,
  });

  final String label;
  final String value;
  final String valueKey;

  /// Where the low point falls, when it is not today.
  final String? detail;
  final bool problem;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 2,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.88,
          color: Palette.muted,
        ),
      ),
      Text(
        value,
        key: ValueKey(valueKey),
        style: amountStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: problem ? Palette.problemText : Palette.ink,
        ).copyWith(letterSpacing: -0.4),
      ),
      if (detail case final detail?)
        Text(
          'on $detail',
          style: const TextStyle(fontSize: 12, color: Palette.muted),
        ),
    ],
  );
}

/// The predicted balance as one line, from today to the end of the range,
/// with a dot on the low point.
class _BalanceChart extends CustomPainter {
  _BalanceChart({required this.balances, required this.lowest});

  final List<Money> balances;
  final int lowest;

  @override
  void paint(Canvas canvas, Size size) {
    if (balances.length < 2) return;
    var low = balances.first.cents;
    var high = low;
    for (final balance in balances) {
      if (balance.cents < low) low = balance.cents;
      if (balance.cents > high) high = balance.cents;
    }
    if (low > 0) low = 0;
    if (high == low) high = low + 100;

    double x(int index) => size.width * index / (balances.length - 1);
    double y(int cents) => size.height * (high - cents) / (high - low);

    final line = Path()..moveTo(x(0), y(balances.first.cents));
    for (var i = 1; i < balances.length; i++) {
      line.lineTo(x(i), y(balances[i].cents));
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Palette.positivePill,
    );
    // A dashed baseline at zero, which the area is filled down to.
    if (low == 0 || balances.any((balance) => balance.isNegative)) {
      final zero = y(0);
      final dash = Paint()
        ..color = Palette.fieldBorder
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, zero), Offset(dx + 4, zero), dash);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.teal,
    );
    for (final (i, balance) in balances.indexed) {
      canvas.drawCircle(
        Offset(x(i), y(balance.cents)),
        i == lowest ? 4 : 2.5,
        Paint()
          ..color = i == lowest && balance.isNegative
              ? Palette.problemText
              : Palette.teal,
      );
    }
  }

  @override
  bool shouldRepaint(_BalanceChart old) {
    if (old.lowest != lowest) return true;
    if (old.balances.length != balances.length) return true;
    for (var i = 0; i < balances.length; i++) {
      if (old.balances[i].cents != balances[i].cents) return true;
    }
    return false;
  }
}

/// The Scheduled Transactions due in the range, soonest first.
class _ComingUp extends StatelessWidget {
  const _ComingUp({
    super.key,
    required this.state,
    required this.range,
    this.scrollable = false,
  });

  final BudgetState state;
  final ForecastRange range;

  /// Whether it has a height of its own to scroll in, as it does beside the
  /// chart. Under the chart the page scrolls instead.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final dues = _dueDates(state, range);
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Coming up',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (dues.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Hint(
                'Nothing scheduled. Add a Scheduled Transaction to see what is '
                'coming.',
              ),
            )
          else if (scrollable)
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final due in dues) _DueRow(state: state, due: due),
                ],
              ),
            )
          else
            for (final due in dues) _DueRow(state: state, due: due),
        ],
      ),
    );
  }
}

/// A Scheduled Transaction and one of its due dates in the range.
typedef _Due = ({CivilDate date, Schedule schedule});

List<_Due> _dueDates(BudgetState state, ForecastRange range) {
  final from = today();
  final until = from.addDays(range.days);
  final dues = <_Due>[];
  for (final schedule in state.schedules) {
    var date = schedule.nextDue;
    // A due date already gone by is not coming up.
    for (var i = 0; i < 400 && date.compareTo(from) < 0; i++) {
      date = _following(date, schedule);
    }
    if (date.compareTo(until) <= 0) {
      dues.add((date: date, schedule: schedule));
    }
  }
  dues.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.schedule.payee.compareTo(b.schedule.payee);
  });
  return dues;
}

/// [schedule]'s due date after [date], advanced one interval at a time.
CivilDate _following(CivilDate date, Schedule schedule) =>
    switch (schedule.interval) {
      TargetInterval.days => date.addDays(schedule.every),
      TargetInterval.weeks => date.addDays(schedule.every * 7),
      TargetInterval.months => date.addMonths(schedule.every),
      TargetInterval.years => date.addMonths(schedule.every * 12),
    };

class _DueRow extends StatelessWidget {
  const _DueRow({required this.state, required this.due});

  final BudgetState state;
  final _Due due;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Palette.divider)),
    ),
    child: Row(
      spacing: 10,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            formatDay(due.date),
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                due.schedule.payee,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                [
                  state.account(due.schedule.accountId)?.name ?? '',
                  categoryName(state, due.schedule.category),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Palette.muted),
              ),
            ],
          ),
        ),
        Text(
          formatSigned(due.schedule.amount),
          style: amountStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
