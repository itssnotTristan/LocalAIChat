/// Answers simple calendar questions from the device clock so an offline model
/// cannot invent the date. Other questions still go to the selected model.
String? localDateAnswer(String message, DateTime now) {
  final text = message.trim().toLowerCase().replaceAll(RegExp(r'[?.!]+$'), '');
  final asksDate = RegExp(
    r"^(?:what(?:'s| is)\s+today'?s?\s+date|what(?:'s| is)\s+the\s+date\s+today|"
    r"what(?:'s| is)\s+the\s+(?:current\s+)?date|"
    r"what\s+day\s+is\s+it(?:\s+today)?|"
    r"what\s+day\s+is\s+today|today'?s?\s+date|current\s+date)$",
  ).hasMatch(text);
  if (!asksDate) return null;
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return 'Today is ${weekdays[now.weekday - 1]}, '
      '${months[now.month - 1]} ${now.day}, ${now.year}.';
}
