import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'database/database.dart';
import 'screens/deck_list_screen.dart';
import 'theme/app_theme.dart';

/// Empty until a real Sentry DSN is added — the SDK quietly no-ops with an
/// empty DSN rather than failing, so this is safe to ship as-is. Get one
/// free at https://sentry.io → Settings → Projects → (your project) →
/// Client Keys (DSN). A DSN is safe to embed in client code (unlike an API
/// key) — it only lets the SDK *send* events, not read anything back.
const _kSentryDsn = '';

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
