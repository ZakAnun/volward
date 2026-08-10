import 'package:url_launcher/url_launcher.dart';

abstract class UrlOpener {
  Future<bool> open(String url);
}

class UrlLauncherOpener implements UrlOpener {
  @override
  Future<bool> open(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
