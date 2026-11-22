/// Accept only our invitation links or explicit codes. Never open scanned URLs.
String? invitationToken(String input, {String? linkHost}) {
  final value = input.trim();
  if (value.isEmpty || value.length > 1024) return null;
  final uri = Uri.tryParse(value);
  String candidate = value;
  if (uri != null && uri.hasScheme) {
    final host = linkHost ?? const String.fromEnvironment('APP_LINK_HOST');
    final custom = uri.scheme == 'bettertogether' && uri.host == 'invite';
    final web = host.isNotEmpty && uri.scheme == 'https' && uri.host == host;
    if ((!custom && !web) || uri.userInfo.isNotEmpty || uri.hasPort) {
      return null;
    }
    final parts = uri.pathSegments;
    if (custom && parts.length == 1) {
      candidate = parts.single;
    } else if (web && parts.length == 2 && parts.first == 'invite') {
      candidate = parts.last;
    } else if ((custom && parts.isEmpty) ||
        (web && parts.length == 1 && parts.first == 'invite')) {
      candidate = uri.queryParameters['token'] ?? '';
    } else {
      return null;
    }
  }
  final short = candidate.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(short)) return short;
  if (RegExp(r'^[a-fA-F0-9]{48}$').hasMatch(candidate)) {
    return candidate.toLowerCase();
  }
  return null;
}

String displayInvitationCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
