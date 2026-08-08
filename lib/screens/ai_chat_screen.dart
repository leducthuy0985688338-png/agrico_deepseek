import 'package:flutter/material.dart';
import '../models/ai_message_model.dart';
import '../services/ai_service.dart';
import '../providers/warehouse_provider.dart';
import '../providers/machine_provider.dart';
import '../providers/employee_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/fuel_provider.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final List<AIMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Khởi tạo các provider
  final WarehouseProvider _warehouseProvider = WarehouseProvider();
  final MachineProvider _machineProvider = MachineProvider();
  final EmployeeProvider _employeeProvider = EmployeeProvider();
  final FinanceProvider _financeProvider = FinanceProvider();
  final FuelProvider _fuelProvider = FuelProvider();

  @override
  void initState() {
    super.initState();
    // Tin nhắn chào mừng
    _messages.add(
      AIMessage(
        id: 'welcome',
        text:
            'Xin chào! Tôi là trợ lý AI của Agrico. Tôi có thể giúp bạn tra cứu thông tin về:\n'
            '📦 Tồn kho\n'
            '🚜 Máy móc\n'
            '👨‍💼 Nhân sự\n'
            '💰 Tài chính\n'
            '⛽ Nhiên liệu\n'
            'Bạn muốn hỏi gì?',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 8),
            const Text('Trợ lý AI'),
          ],
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ====== DANH SÁCH TIN NHẮN ======
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (ctx, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),

          // ====== Ô NHẬP TIN NHẮN ======
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Nhập câu hỏi...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (text) {
                      _sendMessage();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====== TẠO BONG BÓNG TIN NHẮN ======
  Widget _buildMessageBubble(AIMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.green : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser
                ? const Radius.circular(4)
                : const Radius.circular(16),
            bottomLeft: isUser
                ? const Radius.circular(16)
                : const Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: isUser ? Colors.white70 : Colors.grey.shade600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== GỬI TIN NHẮN ======
  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Thêm tin nhắn của người dùng
    setState(() {
      _messages.add(
        AIMessage(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _controller.clear();
    });

    // Cuộn xuống cuối
    _scrollToBottom();

    // Xử lý và trả lời
    _processAndReply(text);
  }

  // ====== XỬ LÝ VÀ TRẢ LỜI ======
  void _processAndReply(String question) async {
    // Giả lập thời gian xử lý
    await Future.delayed(const Duration(milliseconds: 500));

    // Gọi AI Service
    final answer = AIService.processQuestion(
      question,
      _warehouseProvider,
      _machineProvider,
      _employeeProvider,
      _financeProvider,
      _fuelProvider,
    );

    // Thêm tin nhắn trả lời
    setState(() {
      _messages.add(
        AIMessage(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
          text: answer,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });

    // Cuộn xuống cuối
    _scrollToBottom();
  }

  // ====== CUỘN XUỐNG CUỐI ======
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
