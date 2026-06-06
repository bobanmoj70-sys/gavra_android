import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';

class V3AiChatScreen extends StatefulWidget {
  const V3AiChatScreen({super.key});

  @override
  State<V3AiChatScreen> createState() => _V3AiChatScreenState();
}

class _V3AiChatScreenState extends State<V3AiChatScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _questionCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _thinking = false;
  List<dynamic> _znanje = [];

  @override
  void initState() {
    super.initState();
    _loadZnanje();
  }

  Future<void> _loadZnanje() async {
    try {
      final response = await supabase.functions.invoke(
        'v3-ai-uci',
        body: {'action': 'znanje'},
      );
      final data = response.data as Map<String, dynamic>?;
      setState(() {
        _znanje = data?['znanje'] as List<dynamic>? ?? [];
      });
    } catch (e) {
      debugPrint('[AI Chat] Greska pri ucitavanju znanja: $e');
    }
  }

  void _ask() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _thinking = true;
    });
    _questionCtrl.clear();
    _scrollToBottom();

    if (_znanje.isEmpty) {
      await _loadZnanje();
    }

    final answer = _generateAnswer(question);

    setState(() {
      _messages.add(_ChatMessage(text: answer, isUser: false));
      _thinking = false;
    });
    _scrollToBottom();
  }

  String _generateAnswer(String question) {
    final q = question.toLowerCase();

    // Filtriraj relevantna znanja
    final relevantni = _znanje.where((z) {
      final zakljucak = (z['zakljucak'] ?? '').toString().toLowerCase();
      final entitet = (z['entitet'] ?? '').toString().toLowerCase();
      final atribut = (z['atribut'] ?? '').toString().toLowerCase();

      // Heuristika: poklapa li se bilo koja rec iz pitanja sa zakljuckom/entitetom
      final reci = q.split(RegExp(r'\s+'));
      for (final rec in reci) {
        if (rec.length < 3) continue;
        if (zakljucak.contains(rec) || entitet.contains(rec) || atribut.contains(rec)) {
          return true;
        }
      }
      return false;
    }).toList();

    if (relevantni.isEmpty) {
      return 'Nemam dovoljno znanja da odgovorim na to pitanje. Pokusaj "Nauci sve" u ekranu AI Znanje, pa pitaj ponovo.';
    }

    // Sortiraj po confidence (prvo potvrdjeno, pa confidence)
    relevantni.sort((a, b) {
      final aPot = (a['potvrdjeno'] ?? false) ? 1 : 0;
      final bPot = (b['potvrdjeno'] ?? false) ? 1 : 0;
      if (aPot != bPot) return bPot - aPot;
      return ((b['confidence'] ?? 0) as num).compareTo((a['confidence'] ?? 0) as num);
    });

    // Uzmi top 5
    final top = relevantni.take(5).toList();

    // Generisi odgovor
    final buffer = StringBuffer();
    buffer.writeln('Evo sta sam nasao:');
    buffer.writeln();

    for (final z in top) {
      final tip = z['tip'] ?? '';
      final entitet = z['entitet'] ?? '';
      final atribut = z['atribut'];
      final zakljucak = z['zakljucak'] ?? '';
      final potvrdjeno = z['potvrdjeno'] ?? false;

      String prefix;
      if (tip == 'pravilo') {
        prefix = '';
      } else if (atribut != null && atribut.toString().isNotEmpty) {
        prefix = '[$entitet.$atribut] ';
      } else {
        prefix = '[$entitet] ';
      }

      buffer.write(prefix);
      buffer.write(zakljucak);
      if (potvrdjeno) {
        buffer.write(' (potvrdeno)');
      }
      buffer.writeln();
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.write('Ovo su zakljucci koje sam izvukao iz baze. Confidence: ');
    buffer.write('${(top.first['confidence'] ?? 0) * 100}% za najrelevantniji.');

    return buffer.toString();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.gradientContainer(
      gradient: V3ThemeManager().currentGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: const Text(
            '🤖 AI Asistent',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'Postavi pitanje o bazi, npr:\n\n• "Imamo li goriva?"\n• "Sta je v3_auth?"\n• "Koliko ima zahteva?"',
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _ChatBubble(message: msg);
                      },
                    ),
            ),
            if (_thinking)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'AI razmislja...',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Container(
              color: Colors.black26,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Pitaj AI nesto o bazi...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _ask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      onPressed: _ask,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue.withOpacity(0.3) : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: message.isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: message.isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.white.withOpacity(0.9),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
