import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// The live UMWEO backend. Change this if the server moves.
const String apiBase = 'https://web-production-da27d.up.railway.app';

// ---- Design system --------------------------------------------------------
// Colors taken from the UMWEO logo: burnt-orange globe on chocolate brown.
const kBg = Color(0xFF261C15); // deep chocolate brown
const kSurface = Color(0xFF342620); // raised brown surface
const kSurfaceAlt = Color(0xFF3E2E26);
const kBorder = Color(0xFF4C3A2F);
const kOrange = Color(0xFFD2622A); // logo orange
const kOrangeSoft = Color(0xFFE07B45);
const kText = Color(0xFFF4ECE4); // warm off-white
const kMuted = Color(0xFFB9A99C);

void main() {
  runApp(const UmweoApp());
}

class UmweoApp extends StatelessWidget {
  const UmweoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UMWEO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kOrange,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kText,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: kOrange,
          unselectedLabelColor: kMuted,
          indicatorColor: kOrange,
          dividerColor: kBorder,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(70),
              child: Image.asset('assets/logo.jpeg',
                  width: 140, height: 140, fit: BoxFit.cover),
            ),
            const SizedBox(height: 26),
            const Text('UMWEO AI',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: kText)),
            const SizedBox(height: 8),
            const Text('Mining Information Assistant',
                style: TextStyle(fontSize: 14, color: kMuted)),
            const SizedBox(height: 40),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: kOrange),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Image.asset('assets/logo.jpeg',
                    width: 42, height: 42, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UMWEO',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: kText)),
                  Text('Mining Information Assistant',
                      style: TextStyle(fontSize: 11, color: kMuted)),
                ],
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline, size: 20), text: 'Chat'),
              Tab(icon: Icon(Icons.lightbulb_outline, size: 20), text: 'Tips'),
              Tab(icon: Icon(Icons.school_outlined, size: 20), text: 'Courses'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ChatTab(), TipsTab(), CoursesTab()],
        ),
      ),
    );
  }
}

// ---- Models ----------------------------------------------------------------

class Source {
  final String name;
  final bool isWeb;
  final String url;
  Source(this.name, this.isWeb, this.url);
}

class ChatMessage {
  final String text;
  final bool isUser;
  final List<Source> sources;

  ChatMessage(this.text, this.isUser, {this.sources = const []});
}

/// Cleans model markdown: strips heading markers, turns list markers into
/// bullets. Bold segments are handled by [markdownSpans].
String cleanMarkdown(String text) {
  var s = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^[ \t]*[\*\-][ \t]+', multiLine: true), '•  ');
  return s;
}

/// Splits text into spans, rendering **bold** segments with heavy weight.
List<TextSpan> markdownSpans(String text) {
  final spans = <TextSpan>[];
  final bold = RegExp(r'\*\*(.+?)\*\*');
  var index = 0;
  for (final match in bold.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700)));
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}

// ---- Chat tab ---------------------------------------------------------------

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final List<ChatMessage> _messages = [
    ChatMessage(
      'Welcome. I am UMWEO, your mining information assistant.\n\n'
      'Ask me about mining safety, licences, the environment, or gold and '
      'copper mining. Sources are shown for every answer.',
      false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _language = 'english';
  bool _sending = false;

  // ---- Light-touch survey: one question after every few answers ----
  int _answerCount = 0;
  int _surveyRound = 0;
  Map<String, dynamic>? _activeSurvey;
  String? _lastQuestion;

  static const _surveys = [
    {
      'field': 'helpful',
      'question': 'Quick question - are these answers helping you?',
      'options': ['Yes', 'Not really'],
    },
    {
      'field': 'mining_type',
      'question': 'One question for the Ministry - what type of mining do you do?',
      'options': ['Gold', 'Copper', 'Gemstones', 'Other'],
    },
    {
      'field': 'challenge',
      'question': 'Last one - what is your biggest challenge today?',
      'options': [
        'Safety',
        'Licensing',
        'Equipment',
        'Mercury-free processing',
        'Selling minerals'
      ],
    },
  ];

  static const _suggestions = [
    'What protective equipment do I need?',
    'How can I process gold without mercury?',
    'How do I get a small-scale mining licence?',
    'What should I do if a pit wall cracks?',
  ];

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(question, true));
      _sending = true;
      _activeSurvey = null;
      _lastQuestion = question;
    });
    _controller.clear();
    _scrollDown();

    try {
      final response = await http
          .post(
            Uri.parse('$apiBase/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': question, 'language': _language}),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final sources = ((data['sources'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map((s) => Source(s['source'] as String? ?? 'source',
              s['type'] == 'web', s['url'] as String? ?? ''))
          .toList();
      setState(() {
        _messages.add(ChatMessage(data['answer'] as String? ?? '...', false,
            sources: sources));
        _answerCount++;
      });
      _maybeStartSurvey();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          'I could not reach the server. Please check your internet '
          'connection and try again.',
          false,
        ));
      });
    } finally {
      setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _maybeStartSurvey() {
    // One short question after every 3rd answer, three rounds maximum.
    if (_answerCount % 3 != 0 || _surveyRound >= _surveys.length) return;
    final survey = _surveys[_surveyRound];
    setState(() {
      _activeSurvey = survey;
      _messages.add(ChatMessage(survey['question'] as String, false));
    });
  }

  Future<void> _answerSurvey(String choice) async {
    final survey = _activeSurvey!;
    setState(() {
      _messages.add(ChatMessage(choice, true));
      _messages.add(ChatMessage('Thank you - noted.', false));
      _activeSurvey = null;
      _surveyRound++;
    });
    _scrollDown();
    final field = survey['field'] as String;
    final body = <String, dynamic>{
      'survey_question': survey['question'],
      'survey_answer': choice,
      'question': _lastQuestion,
      'language': _language,
    };
    if (field == 'helpful') body['helpful'] = choice == 'Yes';
    if (field == 'mining_type') body['mining_type'] = choice;
    if (field == 'challenge') body['challenge'] = choice;
    try {
      await http.post(
        Uri.parse('$apiBase/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {/* best-effort */}
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: kSurface,
          child: Row(
            children: [
              const Icon(Icons.language, size: 16, color: kMuted),
              const SizedBox(width: 8),
              const Text('Language:',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _language,
                dropdownColor: kSurfaceAlt,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 13, color: kText),
                items: const [
                  DropdownMenuItem(value: 'english', child: Text('English')),
                  DropdownMenuItem(value: 'bemba', child: Text('Bemba')),
                  DropdownMenuItem(value: 'nyanja', child: Text('Nyanja')),
                  DropdownMenuItem(value: 'tonga', child: Text('Tonga')),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'english'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _messages.length) return _typingIndicator();
              return _bubble(_messages[i]);
            },
          ),
        ),
        if (_activeSurvey != null) _surveyChips(),
        if (_messages.length <= 1) _suggestionChips(),
        _composer(),
      ],
    );
  }

  Widget _typingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: kOrange)),
        SizedBox(width: 10),
        Text('Searching mining guidance...',
            style: TextStyle(color: kMuted, fontSize: 13)),
      ]),
    );
  }

  Widget _suggestionChips() {
    return Container(
      height: 62,
      alignment: Alignment.center,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        children: _suggestions
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Material(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _ask(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(color: kBorder),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(s,
                            style: const TextStyle(
                                fontSize: 13, color: kText, height: 1.0)),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _surveyChips() {
    final options = (_activeSurvey!['options'] as List).cast<String>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options
            .map((o) => ActionChip(
                  backgroundColor: kSurface,
                  side: const BorderSide(color: kOrange),
                  label: Text(o,
                      style:
                          const TextStyle(fontSize: 13, color: kOrangeSoft)),
                  onPressed: () => _answerSurvey(o),
                ))
            .toList(),
      ),
    );
  }

  Widget _composer() {
    return Container(
      color: kSurface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _ask,
                  style: const TextStyle(fontSize: 15, color: kText),
                  decoration: InputDecoration(
                    hintText: 'Ask a mining question...',
                    hintStyle: const TextStyle(color: kMuted),
                    filled: true,
                    fillColor: kBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: Material(
                  color: kOrange,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _sending ? null : () => _ask(_controller.text),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: m.isUser ? kOrange : kSurface,
          border: m.isUser ? null : Border.all(color: kBorder),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(m.isUser ? 14 : 4),
            bottomRight: Radius.circular(m.isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            m.isUser
                ? Text(
                    m.text,
                    style: const TextStyle(
                        fontSize: 15, height: 1.45, color: Colors.white),
                  )
                : Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 15, height: 1.45, color: kText),
                      children: markdownSpans(cleanMarkdown(m.text)),
                    ),
                  ),
            if (m.sources.isNotEmpty) ...[
              const Divider(height: 20, color: kBorder),
              ...m.sources.take(4).map((s) => InkWell(
                    onTap: s.url.isEmpty
                        ? null
                        : () => launchUrl(Uri.parse(s.url),
                            mode: LaunchMode.externalApplication),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.isWeb ? Icons.public : Icons.description,
                              size: 14, color: kOrangeSoft),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: kOrangeSoft,
                                decoration: s.url.isEmpty
                                    ? TextDecoration.none
                                    : TextDecoration.underline,
                                decorationColor: kOrangeSoft,
                              ),
                            ),
                          ),
                          if (s.url.isNotEmpty)
                            const Icon(Icons.open_in_new,
                                size: 12, color: kMuted),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Tips tab ---------------------------------------------------------------

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  State<TipsTab> createState() => _TipsTabState();
}

class _TipsTabState extends State<TipsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<String> _tips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse('$apiBase/tips'))
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      setState(() {
        _tips = ((data['tips'] as List?) ?? []).cast<String>();
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _tips = const [
          'Check your pit walls every morning before work. Cracks, bulges, '
              'or water seeping out are warning signs.',
          'Always wear your hard hat, boots, and dust mask.',
          'Never work alone underground.',
        ];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _tips.length,
      itemBuilder: (context, i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.lightbulb_outline, color: kOrange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TIP ${i + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kOrangeSoft,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(_tips[i],
                      style: const TextStyle(
                          fontSize: 14, color: kText, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Courses ---------------------------------------------------------------

class Lesson {
  final String title;
  final String body;
  const Lesson(this.title, this.body);
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int answer; // index of the correct option
  const QuizQuestion(this.question, this.options, this.answer);
}

class Course {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Lesson> lessons;
  final List<QuizQuestion> quiz;
  const Course(this.title, this.subtitle, this.icon,
      {this.lessons = const [], this.quiz = const []});

  bool get available => lessons.isNotEmpty;
}

const kCourses = [
  Course(
    'Mining Safety Basics',
    'PPE, pit safety, and emergency response',
    Icons.health_and_safety_outlined,
    lessons: [
      Lesson(
        'Protect Your Body (PPE)',
        'Personal Protective Equipment (PPE) is your first defence against '
            'injury.\n\n'
            '- HARD HAT: protects your head from falling rocks. Wear it at '
            'all times on site.\n'
            '- STRONG BOOTS: protect your feet from sharp rocks and heavy '
            'objects. Never mine in sandals.\n'
            '- DUST MASK: mining dust damages your lungs slowly. You may not '
            'feel it today, but it can cause serious disease later.\n'
            '- GLOVES: protect your hands when handling rock and tools.\n'
            '- HIGH-VISIBILITY VEST: makes sure others can see you, '
            'especially near machines and vehicles.\n\n'
            'A miner who cannot work because of injury cannot feed a family. '
            'PPE is not a cost - it is protection for your income.',
      ),
      Lesson(
        'Pit and Tunnel Safety',
        'Most deaths in small-scale mining come from collapsing pits and '
            'tunnels.\n\n'
            '- CHECK EVERY MORNING: before entering, look at the pit walls. '
            'Cracks, bulges, or water seeping out are danger signs. Do not '
            'enter until it is made safe.\n'
            '- AFTER RAIN, WAIT: rain makes walls soft and heavy. Many '
            'collapses happen in the rainy season.\n'
            '- SUPPORT THE ROOF: in tunnels, use strong timber supports. If '
            'the roof drips or cracks, leave immediately.\n'
            '- SLOPE THE WALLS: dig pit walls at an angle, not straight '
            'down. Straight walls fall without warning.\n'
            '- NEVER DIG UNDER A WALL: undercutting is the fastest way to '
            'cause a collapse.',
      ),
      Lesson(
        'Work Together, Respond Fast',
        'When an accident happens, the first minutes decide everything.\n\n'
            '- NEVER WORK ALONE: always have a partner who knows exactly '
            'where you are.\n'
            '- AGREE ON SIGNALS: decide together how to warn each other of '
            'danger - a whistle, a shout, a rope pull.\n'
            '- KEEP A FIRST AID KIT: at every site. Learn to stop bleeding '
            'and treat crush injuries before help arrives.\n'
            '- KNOW YOUR EMERGENCY CONTACTS: save the numbers of the '
            'nearest clinic, police, and the Mine Safety Department.\n'
            '- REPORT ACCIDENTS: reporting helps the Ministry make mining '
            'safer for everyone.',
      ),
    ],
    quiz: [
      QuizQuestion(
        'What should you check every morning before entering a pit?',
        ['The weather forecast', 'The pit walls for cracks and bulges',
            'Your phone battery', 'The price of copper'],
        1,
      ),
      QuizQuestion(
        'Why is a dust mask important?',
        ['It keeps your face warm', 'It hides your identity',
            'Mining dust slowly damages your lungs', 'It is required for photos'],
        2,
      ),
      QuizQuestion(
        'When are pit collapses most common?',
        ['During the rainy season', 'On Mondays', 'At night', 'In the dry season'],
        0,
      ),
      QuizQuestion(
        'What is the rule about working underground?',
        ['Work fast and leave', 'Never work alone',
            'Only work at night', 'Take your radio'],
        1,
      ),
      QuizQuestion(
        'How should pit walls be dug?',
        ['Straight down to save time', 'At an angle (sloped)',
            'Undercut at the bottom', 'It does not matter'],
        1,
      ),
    ],
  ),
  Course(
    'Mercury-Free Gold Processing',
    'Safer methods that protect your health',
    Icons.science_outlined,
    lessons: [
      Lesson(
        'Why Mercury Is Dangerous',
        'Mercury is a poison that builds up in your body over years.\n\n'
            '- It damages the brain, kidneys, and nerves. The damage cannot '
            'be reversed.\n'
            '- It harms unborn babies when pregnant women are exposed.\n'
            '- Burning amalgam releases mercury vapour - breathing it is the '
            'most dangerous exposure of all.\n'
            '- Mercury washed into rivers poisons fish that your family and '
            'community eat.\n\n'
            'Zambia has signed the Minamata Convention, a global agreement '
            'to reduce mercury use. Mercury-free methods protect your health '
            'AND often recover more gold.',
      ),
      Lesson(
        'Gravity Methods: Let Weight Do the Work',
        'Gold is much heavier than sand and rock. Gravity methods use this.\n\n'
            '- PANNING: swirling ore with water so the heavy gold settles at '
            'the bottom. Simple and cheap.\n'
            '- SLUICING: washing ore down a channel with ridges (riffles). '
            'The heavy gold is trapped behind the riffles.\n'
            '- SHAKING TABLES: a vibrating table separates gold from sand '
            'very efficiently - often used by groups or cooperatives.\n'
            '- CENTRIFUGES: spinning machines that concentrate fine gold '
            'that panning misses.\n\n'
            'Good gravity setups can recover MORE gold than mercury, because '
            'mercury misses very fine gold particles.',
      ),
      Lesson(
        'Direct Smelting and Borax',
        'After concentrating your gold with gravity methods:\n\n'
            '- DIRECT SMELTING: heat the rich concentrate in a crucible '
            'until the gold melts together. No mercury needed.\n'
            '- BORAX METHOD: adding borax lowers the melting temperature, so '
            'the gold collects into a bead using a simple charcoal furnace.\n'
            '- WORK IN GROUPS: smelting equipment is affordable when a '
            'cooperative shares it - and cooperatives get better prices '
            'when selling too.\n\n'
            'Ask about training: organisations like planetGOLD run '
            'mercury-free processing programmes for small-scale miners.',
      ),
    ],
    quiz: [
      QuizQuestion(
        'Which mercury exposure is the most dangerous?',
        ['Touching it briefly', 'Breathing vapour when burning amalgam',
            'Looking at it', 'Storing it in a bottle'],
        1,
      ),
      QuizQuestion(
        'Why can gravity methods recover MORE gold than mercury?',
        ['They are magic', 'Mercury misses very fine gold particles',
            'Gold floats on water', 'They work faster'],
        1,
      ),
      QuizQuestion(
        'What does the borax method do?',
        ['Makes gold heavier', 'Lowers the melting temperature of gold',
            'Turns rock into gold', 'Cleans the water'],
        1,
      ),
      QuizQuestion(
        'Who is most at risk from mercury exposure?',
        ['Only old miners', 'Unborn babies and children',
            'Nobody, it is safe', 'Only people who eat fish'],
        1,
      ),
      QuizQuestion(
        'What is one advantage of working in a cooperative?',
        ['Sharing equipment costs and getting better prices',
            'Longer working hours', 'More mercury', 'Less training'],
        0,
      ),
    ],
  ),
  Course('Licensing & Legal Requirements',
      'Licences, PACRA registration, and your rights', Icons.gavel_outlined),
  Course('Environmental Protection',
      'Tailings, water protection, and mine rehabilitation', Icons.eco_outlined),
  Course('First Aid for Miners', 'Treating injuries before help arrives',
      Icons.medical_services_outlined),
  Course('Business & Financial Skills',
      'Selling minerals, fair prices, and record keeping', Icons.trending_up),
];

// ---- Courses tab -------------------------------------------------------------

class CoursesTab extends StatelessWidget {
  const CoursesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: kCourses.length,
      itemBuilder: (context, i) {
        final c = kCourses[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: c.available
              ? () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CourseScreen(course: c)))
              : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.available ? kOrange : kBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(c.icon, color: kOrange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: kText)),
                      const SizedBox(height: 3),
                      Text(c.subtitle,
                          style:
                              const TextStyle(fontSize: 12.5, color: kMuted)),
                      const SizedBox(height: 6),
                      Text(
                          c.available
                              ? '${c.lessons.length} lessons - quiz - certificate'
                              : 'Coming soon',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: c.available ? kOrangeSoft : kMuted,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(c.available ? Icons.chevron_right : Icons.lock_outline,
                    color: c.available ? kOrange : kMuted, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Course screen (lessons) --------------------------------------------------

class CourseScreen extends StatefulWidget {
  final Course course;
  const CourseScreen({super.key, required this.course});

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  int _lesson = 0;

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final lesson = course.lessons[_lesson];
    final isLast = _lesson == course.lessons.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(course.title, style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_lesson + 1) / (course.lessons.length + 1),
            backgroundColor: kBorder,
            color: kOrange,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LESSON ${_lesson + 1} OF ${course.lessons.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kOrangeSoft,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(lesson.title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: kText)),
                  const SizedBox(height: 14),
                  Text(lesson.body,
                      style: const TextStyle(
                          fontSize: 15, height: 1.55, color: kText)),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (_lesson > 0)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _lesson--),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: kMuted,
                          side: const BorderSide(color: kBorder),
                          minimumSize: const Size(0, 48)),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => QuizScreen(course: course)));
                      } else {
                        setState(() => _lesson++);
                      }
                    },
                    icon: Icon(isLast ? Icons.quiz_outlined : Icons.arrow_forward,
                        size: 18),
                    label: Text(isLast ? 'Take the quiz' : 'Next lesson'),
                    style: FilledButton.styleFrom(
                        backgroundColor: kOrange,
                        minimumSize: const Size(0, 48)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Quiz screen ---------------------------------------------------------------

class QuizScreen extends StatefulWidget {
  final Course course;
  const QuizScreen({super.key, required this.course});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _index = 0;
  int _correct = 0;
  int? _selected;

  void _next() {
    if (_selected == widget.course.quiz[_index].answer) _correct++;
    if (_index < widget.course.quiz.length - 1) {
      setState(() {
        _index++;
        _selected = null;
      });
    } else {
      final passed = _correct / widget.course.quiz.length >= 0.8;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ResultScreen(
              course: widget.course,
              correct: _correct,
              total: widget.course.quiz.length,
              passed: passed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.course.quiz[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('Quiz - ${widget.course.title}',
            style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_index + 1) / widget.course.quiz.length,
            backgroundColor: kBorder,
            color: kOrange,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QUESTION ${_index + 1} OF ${widget.course.quiz.length}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kOrangeSoft,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Text(q.question,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: kText)),
            const SizedBox(height: 18),
            ...List.generate(q.options.length, (i) {
              final selected = _selected == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selected = i),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? kOrange.withValues(alpha: 0.18)
                          : kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected ? kOrange : kBorder,
                          width: selected ? 1.6 : 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: selected ? kOrange : kMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(q.options[i],
                              style: const TextStyle(
                                  fontSize: 14.5, color: kText)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected == null ? null : _next,
                  style: FilledButton.styleFrom(
                      backgroundColor: kOrange,
                      minimumSize: const Size(0, 50)),
                  child: Text(_index == widget.course.quiz.length - 1
                      ? 'Finish quiz'
                      : 'Next question'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Result + certificate -------------------------------------------------------

class ResultScreen extends StatefulWidget {
  final Course course;
  final int correct;
  final int total;
  final bool passed;
  const ResultScreen(
      {super.key,
      required this.course,
      required this.correct,
      required this.total,
      required this.passed});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz result')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
                widget.passed
                    ? Icons.verified_outlined
                    : Icons.replay_circle_filled_outlined,
                size: 72,
                color: widget.passed ? kOrange : kMuted),
            const SizedBox(height: 16),
            Text(
              widget.passed ? 'Well done!' : 'Almost there',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: kText),
            ),
            const SizedBox(height: 8),
            Text(
              'You scored ${widget.correct} out of ${widget.total}.'
              '${widget.passed ? '' : ' You need ${(widget.total * 0.8).ceil()} to pass - review the lessons and try again.'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: kMuted, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (widget.passed) ...[
              TextField(
                controller: _name,
                style: const TextStyle(color: kText),
                decoration: InputDecoration(
                  labelText: 'Your name (for the certificate)',
                  labelStyle: const TextStyle(color: kMuted),
                  filled: true,
                  fillColor: kSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  final name = _name.text.trim().isEmpty
                      ? 'Miner'
                      : _name.text.trim();
                  // Report completion so the Ministry sees training uptake.
                  http.post(
                    Uri.parse('$apiBase/feedback'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'survey_question': 'course_completed',
                      'survey_answer':
                          '${widget.course.title} (${widget.correct}/${widget.total})',
                    }),
                  ).catchError((_) => http.Response('', 0));
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => CertificateScreen(
                          course: widget.course,
                          name: name,
                          correct: widget.correct,
                          total: widget.total)));
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Get my certificate'),
                style: FilledButton.styleFrom(
                    backgroundColor: kOrange, minimumSize: const Size(0, 50)),
              ),
            ] else
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => CourseScreen(course: widget.course))),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Review lessons'),
                style: FilledButton.styleFrom(
                    backgroundColor: kOrange, minimumSize: const Size(0, 50)),
              ),
          ],
        ),
      ),
    );
  }
}

class CertificateScreen extends StatelessWidget {
  final Course course;
  final String name;
  final int correct;
  final int total;
  const CertificateScreen(
      {super.key,
      required this.course,
      required this.name,
      required this.correct,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final date =
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kOrange, width: 2),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset('assets/logo.jpeg',
                          width: 56, height: 56, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 14),
                    const Text('CERTIFICATE OF COMPLETION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: kOrangeSoft)),
                    const SizedBox(height: 20),
                    const Text('This certifies that',
                        style: TextStyle(fontSize: 13, color: kMuted)),
                    const SizedBox(height: 8),
                    Text(name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: kText)),
                    const SizedBox(height: 8),
                    const Text('has successfully completed the course',
                        style: TextStyle(fontSize: 13, color: kMuted)),
                    const SizedBox(height: 8),
                    Text(course.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: kOrange)),
                    const SizedBox(height: 18),
                    Container(height: 1, width: 160, color: kBorder),
                    const SizedBox(height: 14),
                    Text('Score: $correct / $total    Date: $date',
                        style: const TextStyle(fontSize: 12.5, color: kMuted)),
                    const SizedBox(height: 6),
                    const Text('UMWEO Mining Learning - Prototype',
                        style: TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Take a screenshot to keep your certificate.',
                  style: TextStyle(fontSize: 12.5, color: kMuted)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('Back to courses'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kOrangeSoft,
                    side: const BorderSide(color: kOrange),
                    minimumSize: const Size(0, 48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
