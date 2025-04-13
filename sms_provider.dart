import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';

import 'banks.dart';

class SMSProvider extends ChangeNotifier {
  final SmsQuery _smsQuery = SmsQuery();
  List<SmsMessage> _messages = [];
  double _progress = 0.0;
  Map<String, List<SmsMessage>> _groupedMessages = {}; // Grouped by sender
  Map<String, bool> _groupSelection = {}; // Checkbox state for groups
  bool _isCompleted = false; // Track whether fetching is completed

  List<SmsMessage> get messages => _messages;
  double get progress => _progress;
  Map<String, List<SmsMessage>> get groupedMessages => _groupedMessages;
  bool get isCompleted => _isCompleted;
  Map<String, bool> get groupSelection => _groupSelection;

  Future<void> fetchSMS() async {
    _messages.clear();
    _progress = 0.0;
    _isCompleted = false;
    notifyListeners();

    // **Fetch last_saved timestamp from Firestore**
    Timestamp? lastSaved;
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          lastSaved = userDoc["last_saved"] as Timestamp?;
        }
      }
    } catch (e) {
      print("Error fetching last_saved timestamp: $e");
    }

    // **Fetch all SMS messages from inbox**
    List<SmsMessage> allMessages = await _smsQuery.querySms(
      kinds: [SmsQueryKind.inbox],
    );

    int total = allMessages.length;
    List<SmsMessage> filteredMessages = [];

    for (int i = 0; i < total; i++) {
      final SmsMessage msg = allMessages[i];

      // **Check if message is a bank transaction and newer than last_saved**
      if (_isBankTransaction(msg) && (lastSaved == null || msg.date!.isAfter(lastSaved.toDate()))) {
        filteredMessages.add(msg);
      }

      _messages = filteredMessages;
      _progress = (i + 1) / total;
      notifyListeners();
      await Future.delayed(Duration(milliseconds: 20)); // Simulate delay
    }

    _groupedMessages = _groupBySender(filteredMessages);
    _groupSelection = {for (var sender in _groupedMessages.keys) sender: false};
    _isCompleted = true;
    notifyListeners();
  }


  // Function to detect only bank transactions
  // Function to detect only bank transactions (Now filters OTP, Cashback, Promotions)
  bool _isBankTransaction(SmsMessage msg) {
    if (msg.address == null || msg.body == null) return false;

    String body = msg.body!.toLowerCase();

    // **Exclude OTP messages**
    if (RegExp(r"\b(one time password|otp|do not share|verification code)\b", caseSensitive: false).hasMatch(body)) {
      return false;
    }

    // **Exclude Cashback messages**
    if (RegExp(r"\b(cashback|reward points|bonus|offer|discount|gift card|promo code|lucky draw)\b", caseSensitive: false).hasMatch(body)) {
      return false;
    }
    if (RegExp(r"\b(refunded|cancelled|refund|order|requesting|out for delivery|requested|redeem|earned|expired|not completed|failed |collect request)\b", caseSensitive: false).hasMatch(body)) {
      return false;
    }

    // **Exclude Promotional messages**
    if (RegExp(r"\b(congratulations|loan offer|apply now|free trial|limited time|exclusive deal|shopping sale|Come back?|flat|deals|wishlist| off)\b", caseSensitive: false).hasMatch(body)) {
      return false;
    }

    // **Detect actual transactions**
    bool hasTransactionKeyword = ["debited", "txn", "transaction", "payment", "upi"]
        .any((word) => body.contains(word));

    bool hasAmount = RegExp(r"(₹|rs\.|inr)\s?\d{1,3}(,\d{3})*(\.\d{1,2})?").hasMatch(body);

    return hasTransactionKeyword && hasAmount;
  }


  // Function to extract transaction details locally
  Future<Map<String, String>> extractTransactionDetails(SmsMessage msg) async {
    String body = msg.body!;

    // Extract amount (Handles INR, Rs., ₹, with or without commas)
    RegExp amountRegex = RegExp(r"(₹|rs\.|inr)\s?([\d,]+\.\d{1,2}|\d+)", caseSensitive: false);
    Match? amountMatch = amountRegex.firstMatch(body);
    String amount = amountMatch != null
        ? amountMatch.group(2)!.replaceAll(',', '') // **Fix: Removes all commas correctly**
        : "Unknown";

    // Extract account number (Now supports various formats)
    RegExp accountRegex = RegExp(r"(?:A/c|A/C|A/C No:|Account No:|A/C number|XXXX|XX)\s?(\w{3,5}\d{2,5})", caseSensitive: false);
    Match? accountMatch = accountRegex.firstMatch(body);
    String accountNumber = accountMatch != null ? "XXXX" + accountMatch.group(1)! : "Unknown";



    String bank = "Unknown";
    for (var b in banks) {
      if (body.toLowerCase().contains(b.toLowerCase())) {
        bank = b;
        break;
      }
    }

    // Extract merchant (Ensures no false merchants like "your account XXXX2337")
    RegExp merchantRegex = RegExp(r"to\s([\w\s]+)|towards\s([\w\s]+)|at\s([\w\s]+)|UPI/DR/[\d]+/([\w\s]+)");
    Match? merchantMatch = merchantRegex.firstMatch(body);
    String merchant = merchantMatch != null
        ? (merchantMatch.group(1) ?? merchantMatch.group(2) ?? merchantMatch.group(3) ?? merchantMatch.group(4) ?? "Bank Transaction")
        : "Bank Transaction";

    // **Fix: If merchant contains "account XXXX" or "your account", mark as "Bank Transaction"**
    if (merchant.toLowerCase().contains("account") || merchant.toLowerCase().contains("xxxx")) {
      merchant = "Bank Transaction";
    }

    // Extract transaction type
    Map<String, List<String>> categories = {
      "food": ["zomato", "swiggy", "restaurant", "cafe", "dining", "eatery", "food", "dominos", "mcdonalds", "pizza"],
      "travel": ["uber", "ola", "metro", "bus", "flight", "train", "cab", "taxi", "redbus", "indigo", "spicejet"],
      "bills": ["electricity", "water", "gas", "internet", "bill", "recharge", "dth", "broadband", "airtel", "jio",
        "vodafone", "fastag"],
      "medicine": ["pharmacy", "hospital", "clinic", "meds", "doctor", "apollo", "practo"],
      "shopping": ["amazon", "flipkart", "myntra", "tatacliq", "ajio", "shop", "ebay"],
      "entertainment": ["netflix", "hotstar", "sony liv", "prime video", "spotify", "zee5"],
      "finance": ["loan", "emi", "insurance", "credit card", "mutual funds"],
      "misc": ["paytm", "google pay", "phonepe", "upi", "unknown", "services"]
    };

    String transactionType = "Misc.";
    for (var type in categories.keys) {
      if (categories[type]!.any((keyword) => body.toLowerCase().contains(keyword))) {
        transactionType = type.capitalize();
        break;
      }
    }

    return {
      "amount": amount,
      "merchant": merchant,
      "bank": bank,
      "accountNumber": accountNumber,
      "transactionType": transactionType,
    };
  }

  // Grouping function
  Map<String, List<SmsMessage>> _groupBySender(List<SmsMessage> messages) {
    Map<String, List<SmsMessage>> grouped = {};
    for (var msg in messages) {
      String sender = msg.address ?? "Unknown Sender";
      if (!grouped.containsKey(sender)) {
        grouped[sender] = [];
      }
      grouped[sender]!.add(msg);
    }
    return grouped;
  }

  // Toggle selection for a group
  void toggleGroupSelection(String sender, bool isSelected) {
    _groupSelection[sender] = isSelected;
    notifyListeners();
  }
  void clearMessages() {
    _messages.clear();
    _progress = 0.0;
    _groupedMessages.clear();
    _groupSelection.clear();
    _isCompleted = false;
    notifyListeners();
  }
}

// **Helper function to capitalize first letter**
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
