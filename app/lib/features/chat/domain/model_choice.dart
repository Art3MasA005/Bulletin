/// A generation model the user may pick (handoff README, "Model picker").
///
/// The app only ever holds the server's `key` for it. The OpenRouter model id
/// stays on the server (`GET /models`), so a client cannot send a model of
/// its own choosing.
library;

enum ModelCost { low, high }

class ModelChoice {
  const ModelChoice({
    required this.key,
    required this.name,
    required this.maker,
    this.cost = ModelCost.low,
    this.isDefault = false,
  });

  factory ModelChoice.fromJson(Map<String, dynamic> json) => ModelChoice(
    key: json['key'] as String,
    name: json['name'] as String,
    maker: json['maker'] as String,
    cost: json['cost'] == 'high' ? ModelCost.high : ModelCost.low,
    isDefault: json['default'] == true,
  );

  final String key;
  final String name;
  final String maker;
  final ModelCost cost;
  final bool isDefault;

  @override
  bool operator ==(Object other) => other is ModelChoice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The model a question goes to: the pick if it is still offered, else the
/// server's default, else the first offered. Null when none are offered,
/// which hides the picker.
ModelChoice? currentModel(List<ModelChoice> offered, String? pickedKey) {
  if (offered.isEmpty) return null;
  for (final m in offered) {
    if (m.key == pickedKey) return m;
  }
  for (final m in offered) {
    if (m.isDefault) return m;
  }
  return offered.first;
}
