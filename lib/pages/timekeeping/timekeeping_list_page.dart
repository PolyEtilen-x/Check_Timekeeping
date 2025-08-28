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

  Stream<List<Attendance>> _streamByDay() {
    // Query theo khoảng thời gian trong ngày trên field 'timestamp'
    return FirebaseFirestore.instance
        .collection('timekeeping')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(_endOfDay))
        .orderBy('timestamp', descending: true) // sắp xếp mới → cũ
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? {},
          toFirestore: (data, _) => data,
        )
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

  Widget _item(Attendance a) {
    final time = _fmtTime(a.serverAt ?? a.clientAt);
    final badgeColor = a.status == 'success' ? const Color(0xFF21D07A) : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: (a.faceImageUrl != null && a.faceImageUrl!.isNotEmpty)
              ? Image.network(a.faceImageUrl!, width: 46, height: 46, fit: BoxFit.cover)
              : Container(
                  width: 46, height: 46,
                  color: const Color(0xFFEAEAEA),
                  child: const Icon(Icons.person, color: Color(0xFF233986)),
                ),
        ),
        title: Text(
          a.name.isEmpty ? a.uid : a.name,
          style: const TextStyle(
            color: Color(0xFF233986),
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${_roleText(a.role as int)} • ${a.by.toUpperCase()}',
          style: const TextStyle(color: Colors.black54),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              time,
              style: const TextStyle(
                color: Color(0xFF233986),
                fontWeight: FontWeight.w800,
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
                  letterSpacing: .4,
                ),
              ),
            ),
          ],
        ),
        onTap: () {
          // TODO: nếu cần xem chi tiết bản ghi
        },
      ),
    );
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
                    // Nút chọn ngày
                    
                  ],
                ),
                const SizedBox(height: 12),
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
                
                // List
                Expanded(
                  child: StreamBuilder<List<Attendance>>(
                    stream: _streamByDay(),
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
