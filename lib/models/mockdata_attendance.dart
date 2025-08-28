// lib/mock/mock_attendance.dart
import 'dart:core';

class MockAttendance {
  final String id;
  final String name;
  final int role; // 1 = Nhân viên, 2 = Quản lý
  final String by;
  final DateTime checkInAt;
  final DateTime? checkOutAt;

  MockAttendance({
    required this.id,
    required this.name,
    required this.role,
    required this.by,
    required this.checkInAt,
    this.checkOutAt,
  });
}

// hôm nay
final List<MockAttendance> mockDay1 = [
  MockAttendance(
    id: '1',
    name: 'Nguyễn Văn A',
    role: 1,
    by: 'camera',
    checkInAt: DateTime.now().subtract(const Duration(hours: 8)),
    checkOutAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  MockAttendance(
    id: '2',
    name: 'Trần Thị B',
    role: 2,
    by: 'manual',
    checkInAt: DateTime.now().subtract(const Duration(hours: 7, minutes: 45)),
    checkOutAt: null, // chưa checkout
  ),
  MockAttendance(
    id: '3',
    name: 'Lê Văn C',
    role: 1,
    by: 'camera',
    checkInAt: DateTime.now().subtract(const Duration(hours: 7, minutes: 30)),
    checkOutAt: DateTime.now().subtract(const Duration(minutes: 20)),
  ),
  // … thêm 7 người nữa cho đủ 10
];

// hôm qua
final List<MockAttendance> mockDay2 = [
  MockAttendance(
    id: '11',
    name: 'Phạm Quốc D',
    role: 1,
    by: 'camera',
    checkInAt: DateTime.now().subtract(const Duration(days: 1, hours: 8)),
    checkOutAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
  ),
  MockAttendance(
    id: '12',
    name: 'Hoàng Thu E',
    role: 1,
    by: 'camera',
    checkInAt: DateTime.now().subtract(const Duration(days: 1, hours: 7, minutes: 30)),
    checkOutAt: null,
  ),
  MockAttendance(
    id: '13',
    name: 'Đỗ Minh F',
    role: 2,
    by: 'camera',
    checkInAt: DateTime.now().subtract(const Duration(days: 1, hours: 9)),
    checkOutAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
  ),
  // … thêm 7 người nữa cho đủ 10
];

// gộp lại
final Map<String, List<MockAttendance>> mockDataByDay = {
  'today': mockDay1,
  'yesterday': mockDay2,
};
