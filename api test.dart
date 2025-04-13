import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(GeminiAPITestApp());
}

class GeminiAPITestApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: APITestScreen(),
    );
  }
}

class APITestScreen extends StatefulWidget {
  @override
  _APITestScreenState createState() => _APITestScreenState();
}

class _APITestScreenState extends State<APITestScreen> {
  String geminiApiKey = "AIzaSyADu_dBIx7ASF7iDLl1wvUOj7YXN_6pzpA"; // Replace with your API Key
  String extractedData = "Press the button to test API";

  Future<void> testGeminiAPI() async {
    String message = """Debited INR 1221.00 from A/c X3562 on 28-FEB-2025
UPI/DR/100079071611/Paytm Services/INDB/
Bal INR 32,360.54
Not you? Call 180012001200 & dial 0
-Canara Bank""";

    String prompt = """
Extract the following details from the given banking transaction message:
- **Transaction Mode** (e.g., UPI, Net Banking, Card Payment, ATM Withdrawal)
- **Transaction Type** (Credit/Debit)
- **Merchant Name**
- **Bank Name**
- **Transaction Amount**
- **Masked Account Number (last 4 digits)**
- **Transaction ID**

**Message:**
$message

**Respond in JSON format:**
{
  "mode": "UPI",
  "type": "Debit",
  "merchant": "Paytm Services",
  "bank": "AU Bank",
  "amount": "INR 101.00",
  "accountNumber": "X3562",
  "transactionId": "100079071611",
}
""";

    final response = await http.post(
      Uri.parse("https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=$geminiApiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "contents": [
          {
            "role": "user",
            "parts": [
              {"text": prompt}
            ]
          }
        ]
      }),
    );

    if (response.statusCode == 200) {
      var jsonResponse = jsonDecode(response.body);
      var output = jsonResponse["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ?? "Invalid response";

      setState(() {
        extractedData = output;
      });
    } else {
      setState(() {
        extractedData = "Error: ${response.statusCode} - ${response.body}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gemini API Test")),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              extractedData,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: testGeminiAPI,
              child: Text("Test Gemini API"),
            ),
          ],
        ),
      ),
    );
  }
}
