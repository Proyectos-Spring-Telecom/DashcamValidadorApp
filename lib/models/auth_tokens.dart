/// Tokens devueltos por `/login` y `/login/operador/login`.
class AuthTokens {
  final String token;
  final String refreshToken;

  const AuthTokens({
    required this.token,
    required this.refreshToken,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      token: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
    );
  }

  bool get isValid => token.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
      };
}
