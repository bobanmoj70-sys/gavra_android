import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/ml_config.dart';

/// Ekran koji realizuje kompletno AI Znanje, Chat sa Gemini modelom,
/// praćenje samostalnih zaključaka i live logova učenja u realnom vremenu.
class V3AiZnanjeScreen extends StatefulWidget {
  const V3AiZnanjeScreen({super.key});

  @override
  State<V3AiZnanjeScreen> createState() => _V3AiZnanjeScreenState();
}

class _V3AiZnanjeScreenState extends State<V3AiZnanjeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _logScrollController = ScrollController();

  // Čuvanje stanja
  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'content':
          'Zdravo! Ja sam Gavra AI, tvoj samostalni analitički asistent. Učim podatke iz tvoje baze u realnom vremenu i spreman sam da odgovorim na svako pitanje zasnovano isključivo na istini iz tabela. Pitaj me bilo šta!'
    }
  ];
  List<Map<String, dynamic>> _insights = [];
  List<String> _logs = [];

  bool _isTyping = false;
  bool _isLoadingInsights = false;
  bool _isLoadingLogs = false;
  bool _serverReachable = true;
  String? _lastError;
  Timer? _pollingTimer;
  late final AppLifecycleListener _lifecycleListener;
  bool _pollingPaused = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Inicijalna sinhronizacija i pokretanje periodičnog pollinga za live učenje
    _fetchInsights();
    _fetchLogs();
    _startPolling();

    _lifecycleListener = AppLifecycleListener(
      onHide: () => setState(() => _pollingPaused = true),
      onInactive: () => setState(() => _pollingPaused = true),
      onShow: () => setState(() {
        _pollingPaused = false;
        _fetchLogs();
        _fetchInsights();
      }),
      onResume: () => setState(() {
        _pollingPaused = false;
        _fetchLogs();
        _fetchInsights();
      }),
    );
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_pollingPaused) {
        _fetchLogs();
        _fetchInsights();
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _pollingTimer?.cancel();
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // --- API METODE ---

  Future<void> _fetchLogs() async {
    if (_isLoadingLogs) return;
    setState(() => _isLoadingLogs = true);

    try {
      final response = await http
          .get(
            Uri.parse('${MlConfig.baseUrl}/logs'),
            headers: MlConfig.headers(),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> logList = data['logs'] ?? [];
        final newLogs = logList.map((e) => e.toString()).toList();
        final hasChanges = newLogs.length != _logs.length || !newLogs.every((log) => _logs.contains(log));
        setState(() {
          _logs = newLogs;
          _serverReachable = true;
          _lastError = null;
        });
        if (hasChanges) {
          _scrollToBottom(_logScrollController);
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _serverReachable = false;
          _lastError = 'Nevažeći API ključ za AI server';
        });
      }
    } catch (e) {
      setState(() {
        _serverReachable = false;
        _lastError = 'AI server nije dostupan';
      });
    } finally {
      if (mounted) setState(() => _isLoadingLogs = false);
    }
  }

  Future<void> _fetchInsights() async {
    if (_isLoadingInsights) return;
    setState(() => _isLoadingInsights = true);

    try {
      final response = await http
          .get(
            Uri.parse('${MlConfig.baseUrl}/insights'),
            headers: MlConfig.headers(),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> insightList = data['insights'] ?? [];
        setState(() {
          _insights = insightList.map((e) => Map<String, dynamic>.from(e)).toList();
          _serverReachable = true;
          _lastError = null;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _serverReachable = false;
          _lastError = 'Nevažeći API ključ za AI server';
        });
      }
    } catch (e) {
      setState(() {
        _serverReachable = false;
        _lastError = 'AI server nije dostupan';
      });
    } finally {
      if (mounted) setState(() => _isLoadingInsights = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    if (text.length > 2000) {
      setState(() {
        _messages.add({
          'role': 'ai',
          'content': 'Poruka je predugačka. Maksimalno dozvoljeno je 2000 karaktera.',
        });
      });
      _scrollToBottom(_chatScrollController);
      return;
    }

    _chatController.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isTyping = true;
      _lastError = null;
    });
    _scrollToBottom(_chatScrollController);

    try {
      final response = await http
          .post(
            Uri.parse('${MlConfig.baseUrl}/chat'),
            headers: MlConfig.headers(),
            body: json.encode({'message': text}),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final replyText = data['response'] ?? 'Došlo je do greške u interpretaciji odgovora.';
        setState(() {
          _messages.add({'role': 'ai', 'content': replyText});
          _serverReachable = true;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _messages.add(
              {'role': 'ai', 'content': 'Autentikacija sa AI serverom nije uspela. Proveri ML_API_KEY u .env fajlu.'});
          _serverReachable = false;
          _lastError = 'Nevažeći API ključ';
        });
      } else {
        setState(() {
          _messages.add({
            'role': 'ai',
            'content':
                'Došlo je do greške na AI serveru. Proveri da li je server pokrenut i da li je ML_BASE_URL ispravno podešen.'
          });
          _serverReachable = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'ai',
          'content': 'Nije uspela komunikacija sa AI serverom. Proveri mrežnu konekciju i podešavanja u .env fajlu.'
        });
        _serverReachable = false;
        _lastError = 'AI server nije dostupan';
      });
    } finally {
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom(_chatScrollController);
      }
    }
  }

  Future<void> _triggerResync() async {
    try {
      final response = await http
          .post(
            Uri.parse('${MlConfig.baseUrl}/resync'),
            headers: MlConfig.headers(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resync pokrenut. AI ponovo uči sve podatke.')),
          );
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _serverReachable = false;
          _lastError = 'Nevažeći API ključ za AI server';
        });
      }
    } catch (e) {
      setState(() {
        _serverReachable = false;
        _lastError = 'AI server nije dostupan';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI server nije dostupan. Proveri konekciju.')),
        );
      }
    }
  }

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  // --- VIZUELNI UI DELOVI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.psychology_outlined, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child:
                  const Text('🧠 Gavra AI Brain', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            if (!_serverReachable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _lastError ?? 'Offline',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Ponovo uči sve podatke',
            onPressed: _triggerResync,
          ),
        ],
        backgroundColor: const Color(0xFF11111B),
        elevation: 4,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Ćaskanje'),
            Tab(icon: Icon(Icons.insights), text: 'Zaključci'),
            Tab(icon: Icon(Icons.terminal), text: 'Konzola učenja'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatTab(),
          _buildInsightsTab(),
          _buildLogsTab(),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Istorija razgovora
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF11111B), Color(0xFF1E1E2C)],
              ),
            ),
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildTypingIndicator();
                }
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return _buildChatBubble(msg['content'] ?? '', isUser);
              },
            ),
          ),
        ),
        // Panel za kucanje poruka
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF11111B),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Pitaj me (npr. "koliko je bilo putnika u BC u 07:00")...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF252538),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                radius: 22,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(String content, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : const Color(0xFF28283E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Text(
          content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.0,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF28283E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Gavra AI se priseća i analizira bazu...',
              style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsTab() {
    if (_insights.isEmpty) {
      return Container(
        color: const Color(0xFF1E1E2C),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assessment_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Još uvek nema samostalnih zaključaka.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'AI uči tvoju bazu i kreiraće ih kako podaci pristižu...',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1E1E2C),
      child: RefreshIndicator(
        onRefresh: _fetchInsights,
        color: Colors.blueAccent,
        backgroundColor: const Color(0xFF11111B),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _insights.length,
          itemBuilder: (context, index) {
            final ins = _insights[index];
            final severity = ins['severity'] ?? 'nominal';

            // Definišemo boje i ikone prema nivou bitnosti
            Color headerColor = Colors.green;
            IconData icon = Icons.check_circle_outline;
            if (severity == 'significant') {
              headerColor = Colors.orangeAccent;
              icon = Icons.warning_amber_rounded;
            } else if (severity == 'critical') {
              headerColor = Colors.redAccent;
              icon = Icons.error_outline_rounded;
            }

            return Card(
              color: const Color(0xFF252538),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: headerColor, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ins['title'] ?? 'Bez naslova',
                            style: TextStyle(
                              color: headerColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF32324D), height: 20),
                    Text(
                      ins['description'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if ((ins['source_table'] ?? '').toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A26),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Izvor: ${ins['source_table']}',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          )
                        else
                          const SizedBox(),
                        Text(
                          ins['created_at'] ?? '',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogsTab() {
    return Container(
      color: const Color(0xFF0F0F15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Informacije o konzoli
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF161622),
            child: const Row(
              children: [
                Icon(Icons.online_prediction, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aktivno mrežno nadgledanje učenja (Realtime log)',
                    style: TextStyle(
                        color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
          // Lista logova
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Čekanje na prve logove učenja...',
                      style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          _logs[index],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.3,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
