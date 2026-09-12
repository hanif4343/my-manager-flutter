/// A single secret in the password vault. One model covers all types —
/// which fields are shown/labeled how is decided by the UI based on
/// [type], but the underlying storage stays simple and uniform.
class VaultEntry {
  final String id;
  final String type; // 'login' | 'note' | 'card' | 'token' | 'wifi'
  final String title;
  final String? username; // login: username · card: cardholder name
  final String secret; // login/wifi: password · card: number · token: value · note: body
  final String? url; // login only
  final String? notes; // free-form extra info (card expiry/CVV, token scope, etc.)
  final String? totpSecret; // optional 2FA secret for logins (Base32)
  final int createdAt;
  final int updatedAt;

  VaultEntry({
    required this.id, required this.type, required this.title,
    this.username, required this.secret, this.url, this.notes,
    this.totpSecret, required this.createdAt, required this.updatedAt,
  });

  factory VaultEntry.fromJson(Map<String, dynamic> m) => VaultEntry(
    id: m['id'], type: m['type'], title: m['title'],
    username: m['username'], secret: m['secret'] ?? '',
    url: m['url'], notes: m['notes'], totpSecret: m['totpSecret'],
    createdAt: m['createdAt'], updatedAt: m['updatedAt'],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'title': title, 'username': username,
    'secret': secret, 'url': url, 'notes': notes, 'totpSecret': totpSecret,
    'createdAt': createdAt, 'updatedAt': updatedAt,
  };

  VaultEntry copyWith({
    String? type, String? title, String? username, String? secret,
    String? url, String? notes, String? totpSecret, int? updatedAt,
  }) => VaultEntry(
    id: id, type: type ?? this.type, title: title ?? this.title,
    username: username ?? this.username, secret: secret ?? this.secret,
    url: url ?? this.url, notes: notes ?? this.notes,
    totpSecret: totpSecret ?? this.totpSecret,
    createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );
}
