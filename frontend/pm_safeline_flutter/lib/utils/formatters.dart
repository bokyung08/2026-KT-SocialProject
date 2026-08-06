String formatDistance(double meters) => meters < 1000
    ? '${meters.round()}m'
    : '${(meters / 1000).toStringAsFixed(1)}km';

String formatDuration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}
