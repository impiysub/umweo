import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      home: const HomeShell(),
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
  Source(this.name, this.isWeb);
}

class ChatMessage {
  final String text;
  final bool isUser;
  final List<Source> sources;

  ChatMessage(this.text, this.isUser, {this.sources = const []});
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
          .map((s) =>
              Source(s['source'] as String? ?? 'source', s['type'] == 'web'))
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
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _suggestions
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: kSurface,
                    side: const BorderSide(color: kBorder),
                    label: Text(s,
                        style:
                            const TextStyle(fontSize: 12.5, color: kText)),
                    onPressed: () => _ask(s),
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
            Text(
              m.text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: m.isUser ? Colors.white : kText,
              ),
            ),
            if (m.sources.isNotEmpty) ...[
              const Divider(height: 20, color: kBorder),
              ...m.sources.take(4).map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.isWeb ? Icons.public : Icons.description,
                            size: 14, color: kMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(s.name,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kMuted)),
                        ),
                      ],
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

// ---- Courses tab -------------------------------------------------------------

class CoursesTab extends StatelessWidget {
  const CoursesTab({super.key});

  static const _courses = [
    ('Mining Safety Basics', 'PPE, pit safety, and emergency response', 5,
        Icons.health_and_safety_outlined),
    ('Mercury-Free Gold Processing', 'Safer methods that protect your health',
        4, Icons.science_outlined),
    ('Licensing & Legal Requirements',
        'Licences, PACRA registration, and your rights', 3,
        Icons.gavel_outlined),
    ('Environmental Protection',
        'Tailings, water protection, and mine rehabilitation', 4,
        Icons.eco_outlined),
    ('First Aid for Miners', 'Treating injuries before help arrives', 3,
        Icons.medical_services_outlined),
    ('Business & Financial Skills',
        'Selling minerals, fair prices, and record keeping', 4,
        Icons.trending_up),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _courses.length,
      itemBuilder: (context, i) {
        final (title, subtitle, modules, icon) = _courses[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kOrange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kText)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12.5, color: kMuted)),
                    const SizedBox(height: 6),
                    Text('$modules modules',
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: kOrangeSoft,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: kBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Coming soon',
                    style: TextStyle(fontSize: 11, color: kMuted)),
              ),
            ],
          ),
        );
      },
    );
  }
}
