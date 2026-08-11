import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/github_version_source.dart';

void main() {
  test('parseGitHubLatestRelease maps tag assets and body', () {
    final info = parseGitHubLatestRelease({
      'tag_name': 'v0.0.2',
      'html_url': 'https://github.com/ZakAnun/volward/releases/tag/v0.0.2',
      'body': '## Notes\n- fix',
      'assets': [
        {
          'name': 'volward-v0.0.2-macos-arm64.zip',
          'browser_download_url': 'https://cdn.example/a.zip',
          'size': 42,
        },
      ],
    });

    expect(info.tagName, 'v0.0.2');
    expect(info.version, '0.0.2');
    expect(info.htmlUrl, contains('releases/tag'));
    expect(info.body, contains('Notes'));
    expect(info.assets.single.name, 'volward-v0.0.2-macos-arm64.zip');
    expect(info.assets.single.sizeBytes, 42);
  });

  test('parseGitHubLatestRelease rejects prerelease tags', () {
    expect(
      () => parseGitHubLatestRelease({
        'tag_name': 'v0.0.2-beta',
        'html_url': 'https://example.com',
        'body': '',
        'assets': [],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('tagFromReleasePageUrl reads tag from release page URL', () {
    expect(
      tagFromReleasePageUrl(
        Uri.parse('https://github.com/ZakAnun/volward/releases/tag/v0.0.1'),
      ),
      'v0.0.1',
    );
    expect(
      tagFromReleasePageUrl(
        Uri.parse(
          'https://github.com/ZakAnun/volward/releases/tag/v0.0.1?foo=1',
        ),
      ),
      'v0.0.1',
    );
    expect(
      tagFromReleasePageUrl(Uri.parse('https://github.com/ZakAnun/volward')),
      isNull,
    );
  });

  test('tagFromReleasesAtom reads first entry tag', () {
    const atom = '''
<feed>
  <entry>
    <title>v0.0.1</title>
    <link rel="alternate" href="https://github.com/ZakAnun/volward/releases/tag/v0.0.1"/>
  </entry>
</feed>
''';
    expect(GitHubVersionSource.tagFromReleasesAtom(atom), 'v0.0.1');
  });

  test('conventionReleaseAssets builds CI download URLs', () {
    final assets = conventionReleaseAssets(
      owner: 'ZakAnun',
      repo: 'volward',
      tagName: 'v0.0.2',
      version: '0.0.2',
    );
    expect(assets, hasLength(4));
    expect(
      assets.map((a) => a.name),
      containsAll([
        'volward-v0.0.2-macos-arm64.zip',
        'VolwardSetup-v0.0.2-windows-x64.exe',
        'Volward-v0.0.2-linux-x86_64.AppImage',
      ]),
    );
    expect(
      assets.first.downloadUrl,
      'https://github.com/ZakAnun/volward/releases/download/v0.0.2/volward-v0.0.2-macos-arm64.zip',
    );
  });
}
