class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.enabled,
    required this.minimumBuild,
    required this.updateUrl,
  });

  factory AppUpdatePolicy.fromMap(Map<String, dynamic> map) {
    final url = Uri.parse(map['update_url'] as String);
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid update URL');
    }
    final minimum = (map['minimum_build'] as num).toInt();
    if (minimum < 1) throw const FormatException('Invalid minimum build');
    return AppUpdatePolicy(
      enabled: map['enabled'] as bool,
      minimumBuild: minimum,
      updateUrl: url,
    );
  }

  final bool enabled;
  final int minimumBuild;
  final Uri updateUrl;

  bool requiresUpdate(int installedBuild) =>
      enabled && installedBuild < minimumBuild;
}
