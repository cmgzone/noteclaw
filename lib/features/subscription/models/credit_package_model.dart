class CreditPackageModel {
  final String id;
  final String name;
  final String? description;
  final int credits;
  final double price;
  final bool isActive;
  final String? googlePlayProductId;

  CreditPackageModel({
    required this.id,
    required this.name,
    this.description,
    required this.credits,
    required this.price,
    required this.isActive,
    this.googlePlayProductId,
  });

  factory CreditPackageModel.fromJson(Map<String, dynamic> json) {
    return CreditPackageModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      credits: _parseInt(json['credits']) ?? 0,
      price: _parseDouble(json['price']) ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
      googlePlayProductId: json['google_play_product_id'] as String?,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'credits': credits,
      'price': price,
      'is_active': isActive,
      'google_play_product_id': googlePlayProductId,
    };
  }

  double get pricePerCredit => price / credits;
}
