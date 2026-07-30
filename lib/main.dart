import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'database/database.dart';
import 'screens/deck_list_screen.dart';
import 'theme/app_theme.dart';

/// Sentry project: recall-av / flutter. A DSN is safe to embed in client
/// code (unlike an API key) — it only lets the SDK *send* events, not read
/// anything back.
const _kSentryDsn =
    'https://ffddba6e7a39412f7a54c3fc3bc4e8a7@o4511823707963392.ingest.de.sentry.io/4511823712682064';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the .litertlm (LiteRT-LM) inference engine used for on-device
  // flashcard generation — flutter_gemma ships with zero engines by default,
  // so createModel()/getActiveModel() would otherwise throw on first use.
  await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
  final db = AppDatabase();

  await SentryFlutter.init(
    (options) {
      options.dsn = _kSentryDsn;
      // Crash/error reporting only — performance tracing isn't needed here
      // and would burn free-tier quota on transactions nobody's asked for.
      options.tracesSampleRate = 0.0;
    },
    appRunner: () => runApp(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const FlashcardApp(),
      ),
    ),
  );
}

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Recall',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const DeckListScreen(),
    );
  }
}
