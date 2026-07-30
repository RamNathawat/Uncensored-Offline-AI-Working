import 'dart:async';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';

class ChatController extends GetxController {
  final LlmService _llm = Get.find<LlmService>();
  final ChatStorageService _storage = Get.find<ChatStorageService>();

  final chats = <ChatModel>[].obs;
  final activeChatId = RxnString();
  final isGenerating = false.obs;
  final streamedResponse = ''.obs;
  final temperature = 0.7.obs;
  final systemPrompt = ''.obs;

  StreamSubscription<String>? _genSub;

  @override
  void onInit() {
    super.onInit();
    _loadChats();
    temperature.value = _storage.defaultTemperature;
    systemPrompt.value = _storage.globalSystemPrompt;
  }

  void _loadChats() {
    chats.value = _storage.getAllChats();
  }

  ChatModel? get activeChat {
    if (activeChatId.value == null) return null;
    try {
      return chats.firstWhere((c) => c.id == activeChatId.value);
    } catch (_) {
      return null;
    }
  }

  /// Create a new chat and switch to it.
  void newChat() {
    final chat = ChatModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      systemPrompt: systemPrompt.value,
    );
    chats.insert(0, chat);
    _storage.saveChat(chat);
    activeChatId.value = chat.id;
  }

  /// Switch to an existing chat.
  void switchChat(String id) {
    activeChatId.value = id;
    final chat = activeChat;
    if (chat != null) {
      systemPrompt.value = chat.systemPrompt;
    }
  }

  /// Delete a chat.
  void deleteChat(String id) {
    chats.removeWhere((c) => c.id == id);
    _storage.deleteChat(id);
    if (activeChatId.value == id) {
      activeChatId.value = chats.isNotEmpty ? chats.first.id : null;
    }
  }

  /// Send a user message and stream AI response.
  Future<void> sendMessage(String text, {String? modelFilename}) async {
    if (text.trim().isEmpty) return;
    final chat = activeChat;
    if (chat == null) return;

    // Add user message
    final userMsg = MessageModel(role: MessageRole.user, content: text.trim());
    chat.messages.add(userMsg);
    chat.autoTitle();
    chat.updatedAt = DateTime.now();

    // Lock model to this chat on first message
    if (chat.modelId.isEmpty && modelFilename != null) {
      chat.modelId = modelFilename;
    }

    _storage.saveChat(chat);
    chats.refresh();

    // Build message history for LLM
    final history = chat.messages
        .where((m) => !m.isSystem)
        .map((m) => LlamaChatMessage.fromText(
              role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
              text: m.content,
            ))
        .toList();

    // Prepend system prompt if it exists
    final activeSystemPrompt = chat.systemPrompt.isNotEmpty
        ? chat.systemPrompt
        : systemPrompt.value;
    
    // Estimate available characters for history to prevent hitting context limits
    // We assume contextSize is 8192 on all devices.
    // We want to leave 2048 tokens for the AI response (maxTokens), so we have ~6144 tokens for history.
    // 1 token ≈ 4 characters. So 6144 tokens ≈ 24576 characters.
    int availableChars = 24576;
    
    if (activeSystemPrompt.isNotEmpty) {
      availableChars -= activeSystemPrompt.length;
    }

    // Prune history to keep only the most recent messages that fit
    final List<LlamaChatMessage> prunedHistory = [];
    int currentChars = 0;
    
    for (final msg in history.reversed) {
      final msgLen = msg.text.length;
      if (currentChars + msgLen > availableChars && prunedHistory.isNotEmpty) {
        break; // Stop adding older messages if we run out of room
      }
      prunedHistory.insert(0, msg);
      currentChars += msgLen;
    }

    if (activeSystemPrompt.isNotEmpty) {
      prunedHistory.insert(0, LlamaChatMessage.fromText(
        role: LlamaChatRole.system, 
        text: activeSystemPrompt
      ));
    }

    // Start generation
    isGenerating.value = true;
    streamedResponse.value = '';

    final aiMsg = MessageModel(role: MessageRole.assistant, content: '');
    chat.messages.add(aiMsg);
    chats.refresh();

    // Typewriter timer setup
    final List<String> charBuffer = [];
    Timer? typewriterTimer;
    bool streamDone = false;

    typewriterTimer = Timer.periodic(const Duration(milliseconds: 15), (timer) {
      if (charBuffer.isNotEmpty) {
        streamedResponse.value += charBuffer.removeAt(0);
        aiMsg.content = streamedResponse.value;
      } else if (streamDone) {
        timer.cancel();
      }
    });

    try {
      final stream = _llm.generateChatCompletion(
        messages: prunedHistory,
        params: GenerationParams(
          temp: temperature.value,
          maxTokens: 2048,
        ),
      );

      await for (final chunk in stream) {
        charBuffer.addAll(chunk.split(''));
      }
      streamDone = true;
      while (charBuffer.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      if (aiMsg.content.isEmpty) {
        aiMsg.content = '⚠ Error: ${e.toString()}';
      }
    } finally {
      // Clean up any trailing stop tokens or whitespace
      aiMsg.content = aiMsg.content
          .replaceAll(RegExp(
            r'<\|end\|>|<\|eot_id\|>|<\|endoftext\|>|<\|im_end\|>|<\|im_start\|>'
            r'|<end_of_turn>|<start_of_turn>|<\|assistant\|>|<\|user\|>|<\|system\|>'
            r'|<\|pad\|>|</s>|<s>|\[INST\]|\[/INST\]|\[end\]'
          ), '')
          .trim();
      isGenerating.value = false;
      streamedResponse.value = '';
      chat.updatedAt = DateTime.now();
      _storage.saveChat(chat);
      chats.refresh();
    }
  }

  /// Stop current generation.
  void stopGeneration() {
    _llm.stopGeneration();
    isGenerating.value = false;
  }

  /// Update the system prompt for the active chat.
  void updateSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    final chat = activeChat;
    if (chat != null) {
      chat.systemPrompt = prompt;
      _storage.saveChat(chat);
    }
  }

  /// Set and persist the global system prompt.
  void setGlobalSystemPrompt(String prompt) {
    systemPrompt.value = prompt;
    _storage.globalSystemPrompt = prompt;
  }

  /// Clear global system prompt.
  void clearGlobalSystemPrompt() {
    systemPrompt.value = '';
    _storage.globalSystemPrompt = '';
  }

  void updateTemperature(double temp) {
    temperature.value = temp;
    _storage.defaultTemperature = temp;
  }

  @override
  void onClose() {
    _genSub?.cancel();
    super.onClose();
  }
}
