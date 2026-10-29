double? toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  return double.tryParse(v.toString());
}

String? toStr(dynamic v) => v?.toString();
