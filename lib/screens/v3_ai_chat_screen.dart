import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/ml_config.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';

class V3AiChatScreen extends StatefulWidget {
  const V3AiChatScreen({super.key});

  @override
  State<V3AiChatScreen> createState() => _V3AiChatScreenState();
}

class _V3AiChatScreenState extends State<V3AiChatScreen> {
  // ML server base URL — isti kao u v3_ai_znanje_screen.dart
  static const _mlBaseUrl = MlConfig.baseUrl;

  final TextEditingController _questionCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _autoTrainModels();
  }

  Future<void> _autoTrainModels() async {
    try {
      final response = await http.post(
        Uri.parse('$_mlBaseUrl/auto-train'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        print('[AutoTrain] Complete: ${data['message']}');
      }
    } catch (e) {
      print('[AutoTrain] Error: $e');
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

    String answer;

    try {
      final response = await http
          .post(
            Uri.parse('$_mlBaseUrl/znanje/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pitanje': question}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        answer = data['odgovor']?.toString() ?? 'Nema odgovora';
      } else {
        answer = 'Greška: ${response.statusCode}';
      }
    } catch (e) {
      answer = 'Greška pri povezivanju sa AI serverom: $e';
    }

    setState(() {
      _messages.add(_ChatMessage(text: answer, isUser: false));
      _thinking = false;
    });
    _scrollToBottom();
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
