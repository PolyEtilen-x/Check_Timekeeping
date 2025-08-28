import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';

class HomeEmployee extends StatefulWidget {
  const HomeEmployee({super.key});

  @override
  State<HomeEmployee> createState() => _HomeEmployeeState();
}

class _HomeEmployeeState extends State<HomeEmployee> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  Future<Map<DateTime, _DayMark>> _fetchMonthMarks(
    DateTime month,
    String uid,
  ) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1)
        .subtract(const Duration(seconds: 1));

    final snap = await FirebaseFirestore.instance
        .collection('attendance')
        .where('uid', isEqualTo: uid)
        .where('checkInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkInAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final Map<DateTime, _DayMark> marks = {};
    for (final d in snap.docs) {
      final data = d.data();
      final checkIn = (data['checkInAt'] as Timestamp).toDate();
      final checkOutTs = data['checkOutAt'];
      final hasCheckout = checkOutTs is Timestamp;

      final key = DateTime(checkIn.year, checkIn.month, checkIn.day);
      final color = hasCheckout ? Colors.green : Colors.red;

      final old = marks[key];
      if (old == null || (old.color != Colors.green && hasCheckout)) {
        marks[key] = _DayMark(color: color);
      }
    }
    return marks;
  }

  void _goPrevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _goNextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthStr = "${_vnMonth(_currentMonth.month)} ${_currentMonth.year}";
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Chưa đăng nhập')),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('Không tìm thấy hồ sơ người dùng')));
        }

        final me = UserModel.fromFirestore(snap.data!);

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE6F0FF), Color(0xFF1F66B0)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Image.asset('assets/logo.png', width: 150, height: 150),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Xin chào, ${me.name}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card lịch
                  Expanded(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header tháng
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _goPrevMonth,
                                  icon: const Icon(Icons.chevron_left),
                                  tooltip: "Tháng trước",
                                ),
                                Expanded(
                                  child: Text(
                                    "Thời gian làm việc + chấm công\n$monthStr",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _goNextMonth,
                                  icon: const Icon(Icons.chevron_right),
                                  tooltip: "Tháng sau",
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const _WeekHeader(),
                            const SizedBox(height: 4),

                            FutureBuilder<Map<DateTime, _DayMark>>(
                              future: _fetchMonthMarks(_currentMonth, me.uid),
                              builder: (context, markSnap) {
                                if (markSnap.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final marks = markSnap.data ?? const <DateTime, _DayMark>{};
                                return _MonthGrid(month: _currentMonth, marks: marks);
                              },
                            ),
                            const SizedBox(height: 8),

                            // Legend
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                _LegendDot(color: Colors.green, text: "Đã checkin + checkout"),
                                SizedBox(width: 12),
                                _LegendDot(color: Colors.red, text: "Chỉ checkin"),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _vnMonth(int m) {
    const names = [
      '',
      'Tháng 1','Tháng 2','Tháng 3','Tháng 4','Tháng 5','Tháng 6',
      'Tháng 7','Tháng 8','Tháng 9','Tháng 10','Tháng 11','Tháng 12'
    ];
    return names[m];
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['T2','T3','T4','T5','T6','T7','CN'];
    return Row(
      children: List.generate(7, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              labels[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, _DayMark> marks;
  const _MonthGrid({required this.month, required this.marks});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final firstWeekday = (first.weekday == DateTime.sunday) ? 7 : first.weekday; // 1..7 (T2..CN)
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final List<Widget> rows = [];
    int dayCursor = 1 - (firstWeekday - 1);

    while (dayCursor <= daysInMonth) {
      final cells = <Widget>[];
      for (int i = 0; i < 7; i++) {
        final d = DateTime(month.year, month.month, dayCursor);
        final inMonth = dayCursor >= 1 && dayCursor <= daysInMonth;

        Color? dotColor;
        if (inMonth) {
          final key = DateTime(d.year, d.month, d.day);
          dotColor = marks[key]?.color;
        }

        cells.add(Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: inMonth ? Colors.white : Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      inMonth ? '$dayCursor' : '',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: inMonth ? Colors.black87 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (dotColor != null)
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ));
        dayCursor++;
      }
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DayMark {
  final Color color;
  const _DayMark({required this.color});
}
