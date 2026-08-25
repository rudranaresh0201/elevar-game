/// Groups a number with commas so a large balance stays readable at a glance:
/// `12,480` rather than `12480`.
///
/// Hand-rolled rather than `intl`'s `NumberFormat`. This is the only formatting
/// the app does, and `intl` would pull in locale data and an initialisation
/// step to save six lines.
String groupedNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}
