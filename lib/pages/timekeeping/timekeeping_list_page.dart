import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/attendance.dart';

class TimeKeepingListPage extends StatefulWidget {
  const TimeKeepingListPage({super.key});

  @override
  State<TimeKeepingListPage> createState() => _TimeKeepingListPageState();
}

class _TimeKeepingListPageState extends State<TimeKeepingListPage> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  DateTime get _startOfDay => _selectedDay;
  DateTime get _endOfDay => _selectedDay.add(const Duration(days: 1));

  // ===== Firestore stream (để sau này bật lại) =====
  Stream<List<Attendance>> _streamByDay() {
    return FirebaseFirestore.instance
        .collection('timekeeping')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(_endOfDay))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => Attendance.fromDoc(d as DocumentSnapshot<Map<String, dynamic>>))
            .toList());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Chọn ngày chấm công',
    );
    if (picked != null) {
      setState(() {
        _selectedDay = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _roleText(int r) => r == 2 ? 'Quản lý' : 'Nhân viên';

  // Tạo giờ checkout giả định từ id + ngày để ổn định giữa các lần build
  DateTime? _mockCheckoutOf(Attendance a) {
    // ~80% có checkout
    final seed = '${a.id}-${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}'.hashCode;
    final rnd = Random(seed);
    final didCheckout = rnd.nextInt(100) >= 20;
    if (!didCheckout) return null;

    // Làm 7–9 giờ kể từ giờ check-in (dùng serverAt/clientAt làm check-in)
    final checkIn = a.serverAt ?? a.clientAt ?? DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 8, 0);
    final mins = 7 * 60 + rnd.nextInt(120); // 420..539 phút
    return checkIn.add(Duration(minutes: mins));
  }

  Widget _item(Attendance a) {
    final checkInTime = _fmtTime(a.serverAt ?? a.clientAt);
    final checkoutAt = _mockCheckoutOf(a);
    final badgeColor = a.status.toLowerCase() == 'success'
        ? const Color(0xFF21D07A)
        : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (a.faceImageUrl != null && a.faceImageUrl!.isNotEmpty)
                  ? Image.network(a.faceImageUrl!,
                      width: 46, height: 46, fit: BoxFit.cover)
                  : Container(
                      width: 46,
                      height: 46,
                      color: const Color(0xFFEAEAEA),
                      child: const Icon(Icons.person, color: Color(0xFF233986)),
                    ),
            ),
            const SizedBox(width: 12),

            // Thông tin chính
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name.isEmpty ? a.uid : a.name,
                    style: const TextStyle(
                      color: Color(0xFF233986),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_roleText(a.role)} • ${a.by.toUpperCase()}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Check-in / Check-out / Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.login, size: 16, color: Color(0xFF233986)),
                    const SizedBox(width: 4),
                    Text(
                      checkInTime,
                      style: const TextStyle(
                        color: Color(0xFF233986),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (checkoutAt != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout, size: 16, color: Color(0xFF233986)),
                      const SizedBox(width: 4),
                      Text(
                        _fmtTime(checkoutAt),
                        style: const TextStyle(
                          color: Color(0xFF233986),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8A317).withOpacity(.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'CHƯA CHECK-OUT',
                      style: TextStyle(
                        color: Color(0xFFE8A317),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    a.status.toUpperCase(),
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Stream<List<Attendance>> _mockStreamByDay() {
    final day = _selectedDay;
    final seed = '${day.year}-${day.month}-${day.day}'.hashCode;
    final rnd = Random(seed);

    const names = [
      'Nguyễn Hồng Tồn','Trần Vũ','Lê Nguyễn','Phạm Trung','Hoàng Thu',
      'Đỗ Minh','Từ Hải','Đinh Lan','Bùi Tiến','Phan Ngọc',
    ];

    final List<Attendance> mock = [];
    for (int i = 0; i < 10; i++) {
      // Check-in khoảng 08:00–09:29
      final baseIn = DateTime(day.year, day.month, day.day, 8, 0);
      final inOffset = rnd.nextInt(90); 
      final checkIn = baseIn.add(Duration(minutes: inOffset));

      mock.add(
        Attendance(
          id: 'mock-${day.year}${day.month}${day.day}-$i',
          uid: 'u${(i + 1).toString().padLeft(3, '0')}',
          name: names[i % names.length],
          role: (i % 5 == 0) ? 2 : 1, 
          status: rnd.nextInt(100) < 90 ? 'success' : 'failed', 
          serverAt: checkIn,      
          clientAt: checkIn,   
          by: rnd.nextBool() ? 'camera' : 'manual',
          faceImageUrl: 'https://i.pravatar.cc/150?img=${(i % 70) + 1}',
        ),
      );
    }

    // sắp xếp mới → cũ theo check-in
    mock.sort((a, b) => (b.serverAt ?? b.clientAt)!.compareTo((a.serverAt ?? a.clientAt)!));

    // giả lập fetch 1 lần
    return Stream<List<Attendance>>.value(mock);
  }

  @override
  Widget build(BuildContext context) {
    const bgGradient = LinearGradient(
      colors: [Colors.white, Color(0xFF054A99)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final dayLabel = '${_selectedDay.day.toString().padLeft(2, '0')}/'
        '${_selectedDay.month.toString().padLeft(2, '0')}/${_selectedDay.year}';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF233986)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'DANH SÁCH CHẤM CÔNG',
                      style: TextStyle(
                        color: Color(0xFF233986),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // (giữ trống slot nút chọn ngày trong Row theo yêu cầu “còn lại k đổi”)
                  ],
                ),
                const SizedBox(height: 12),

                // Nút chọn ngày (giữ nguyên)
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFF233986)),
                  label: Text(
                    dayLabel,
                    style: const TextStyle(
                      color: Color(0xFF233986),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // List (đang dùng MOCK). Khi xong mock → đổi stream: _streamByDay()
                Expanded(
                  child: StreamBuilder<List<Attendance>>(
                    stream: _mockStreamByDay(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Lỗi tải dữ liệu: ${snap.error}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final data = snap.data ?? [];
                      if (data.isEmpty) {
                        return const Center(
                          child: Text(
                            'Không có bản ghi chấm công trong ngày này.',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: data.length,
                        itemBuilder: (_, i) => _item(data[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
