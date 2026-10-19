import 'package:flutter_test/flutter_test.dart';
import 'package:volward/widgets/ai_results_hub.dart';

void main() {
  test('ready when analyzed verdicts exist and not analyzing', () {
    expect(
      resolveResultsHubMode(
        analyzing: false,
        hasAnalyzedVerdicts: true,
        coverageRunning: false,
      ),
      ResultsHubMode.ready,
    );
  });

  test('analyzing when analyzing flag true', () {
    expect(
      resolveResultsHubMode(
        analyzing: true,
        hasAnalyzedVerdicts: true,
        coverageRunning: false,
      ),
      ResultsHubMode.analyzing,
    );
  });

  test('analyzing when coverage job running', () {
    expect(
      resolveResultsHubMode(
        analyzing: false,
        hasAnalyzedVerdicts: false,
        coverageRunning: true,
      ),
      ResultsHubMode.analyzing,
    );
  });

  test('awaitingAnalysis when no verdicts and idle', () {
    expect(
      resolveResultsHubMode(
        analyzing: false,
        hasAnalyzedVerdicts: false,
        coverageRunning: false,
      ),
      ResultsHubMode.awaitingAnalysis,
    );
  });
}
