/// In-memory, short-lived authorization; never a business session or stored token.
class InitialPasswordRequired implements Exception {
  const InitialPasswordRequired(this.changeToken);
  final String changeToken;
  @override
  String toString() =>
      'Remplacez votre mot de passe initial pour vous connecter.';
}
