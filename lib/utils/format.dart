// Small, dependency-free formatting helpers (dates, durations, Indian digit grouping).

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int v) => v.toString().padLeft(2, '0');

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime parseIso(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int daysBetween(DateTime a, DateTime b) => (dayOnly(b).difference(dayOnly(a)).inHours / 24).round();

String fmtDur(double minutes) {
  var h = minutes ~/ 60;
  var m = (minutes - h * 60).round();
  if (m == 60) {
    h += 1;
    m = 0;
  }
  return h > 0 ? '${h}h ${_two(m)}m' : '${m}m';
}

String fmtClock(double minutes) {
  final m = minutes.round() % 1440;
  final h24 = m ~/ 60;
  final mm = m % 60;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:${_two(mm)} ${h24 < 12 ? 'AM' : 'PM'}';
}

String fmtTime(DateTime t) => fmtClock((t.hour * 60 + t.minute).toDouble());

/// Indian grouping: 12,34,567.
String fmtInt(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  if (s.length <= 3) return neg ? '-$s' : s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  final out = '${groups.join(',')},$last3';
  return neg ? '-$out' : out;
}

String fmtDate(String iso, {bool long = false, bool weekday = false}) {
  final d = parseIso(iso);
  final month = long ? _monthsLong[d.month - 1] : _months[d.month - 1];
  final base = '${d.day} $month';
  return weekday ? '${_weekdays[d.weekday - 1]}, $base' : base;
}

String fmtDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];

String signed(num v) => v > 0 ? '+${v.round()}' : '${v.round()}';

String fmtValue(String key, double? v) {
  if (v == null) return '–';
  switch (key) {
    case 'sleepMin':
      return fmtDur(v);
    case 'lastMealMin':
      return fmtClock(v);
    case 'steps':
    case 'kcal':
      return fmtInt(v);
    case 'spo2':
    case 'breathing':
      return v.toStringAsFixed(1);
    default:
      return v.round().toString();
  }
}
