import 'package:intl/intl.dart';

final NumberFormat _moneyFormat = NumberFormat.currency(
  locale: 'en_IN',
  symbol: 'Rs. ',
  decimalDigits: 2,
);

String formatMoney(int paise) => _moneyFormat.format(paise / 100);

String formatDateTime(DateTime value) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(value.toLocal());

String formatDate(DateTime? value) =>
    value == null ? '' : DateFormat('dd MMM yyyy').format(value.toLocal());

int parseMoneyToPaise(String value) {
  final parsed = double.tryParse(value.trim()) ?? 0;
  return (parsed.clamp(0, double.infinity) * 100).round();
}

double parsePercentage(String value, {double maximum = double.infinity}) {
  final parsed = double.tryParse(value.trim()) ?? 0;
  return parsed.clamp(0, maximum).toDouble();
}
