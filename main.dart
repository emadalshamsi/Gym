import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  // تفعيل التعامل مع أخطاء الخطوط في الويب لـ Zapp
  try {
    GoogleFonts.config.allowRuntimeFetching = true;
  } catch (e) {
    print('GoogleFonts config failed: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gym App',
      theme: ThemeData(
        textTheme: GoogleFonts.interTextTheme(),
        primaryColor: const Color(0xFF4A80F0),
        scaffoldBackgroundColor: const Color(0xFFF5F9FF),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // CONFIG: Base URL for backend
  final String baseUrl = "https://gym-5pvr.onrender.com"; 
  final String userId = "6ec22654-069a-4ab1-8535-3ac66e0b5047";

  bool isMenuOpen = false;
  DateTime selectedDate = DateTime.now();
  
  // Data State
  Map totals = {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "water": 0};
  Map targets = {"cal": 2000, "prot": 150, "carb": 250, "fat": 70, "water": 2000};
  Map profile = {"full_name": "Emad Alshamsi"};
  int dailyScore = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData([DateTime? date]) async {
    setState(() => isLoading = true);
    final targetDate = date ?? selectedDate;
    final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
    final url = "$baseUrl/get_daily_intake?user_id=$userId&date=$dateStr";
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          selectedDate = targetDate; // ترسيخ التاريخ المختار
          
          final Map? newTotals = data['totals'] as Map?;
          final Map? newTargets = data['targets'] as Map?;
          
          if (newTotals != null) {
            totals['cal'] = newTotals['cal'] ?? 0.0;
            totals['prot'] = newTotals['prot'] ?? 0.0;
            totals['carb'] = newTotals['carb'] ?? 0.0;
            totals['fat'] = newTotals['fat'] ?? 0.0;
            totals['water'] = newTotals['water'] ?? 0.0;
          }

          if (newTargets != null) {
            targets['cal'] = newTargets['cal'] ?? 2000.0;
            targets['prot'] = newTargets['prot'] ?? 150.0;
            targets['carb'] = newTargets['carb'] ?? 250.0;
            targets['fat'] = newTargets['fat'] ?? 70.0;
            targets['water'] = newTargets['water'] ?? 2000.0;
          }

          profile = data['profile'] ?? profile;
          
          double calP = (targets['cal'] != null && targets['cal'] > 0) ? (totals['cal'] / targets['cal']) : 0.0;
          double waterP = (targets['water'] != null && targets['water'] > 0) ? (totals['water'] / targets['water']) : 0.0;
          
          dailyScore = (((calP + waterP) / 2) * 100).toInt().clamp(0, 100);
        });
      } else {
        _showError("Server Error: ${response.statusCode}\nURL: $url");
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      _showError("Connection Error: $e\nCheck if your Render URL is correct: $baseUrl");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _logMealWithAI(String query) async {
    setState(() => isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    final url = "$baseUrl/log_meal?user_id=$userId&meal_type=Lunch";
    
    try {
      final response = await http.post(
        Uri.parse(url),
        body: {
          "items_ar": query,
          "date": dateStr,
        }, 
      );
      
      if (response.statusCode == 200) {
        await _fetchData(selectedDate); // تحديث البيانات لليوم المختار
        _showSuccess("AI Analysed: $query");
      } else {
        _showError("AI Failed: ${response.statusCode}\nBody: ${response.body}");
      }
    } catch (e) {
      _showError("Network Error: $e\nURL: $url");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _logWater(int amount) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/log_water?user_id=$userId"),
        body: {
          "amount_ml": amount.toString(),
          "date": dateStr,
        },
      );
      if (response.statusCode == 200) {
        await _fetchData(selectedDate); // تحديث البيانات فوراً
        _showSuccess("Water logged: $amount ml");
      }
    } catch (e) {
      _showError("Failed to log water");
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildHeader(),
                  const SizedBox(height: 25),
                  _buildTodayBar(),
                  _buildTimeline(),
                  const SizedBox(height: 20),
                  _buildCaloriesCard(),
                  const SizedBox(height: 20),
                  _buildMacrosSection(),
                  const SizedBox(height: 30),
                  _buildDiaryHeader(),
                  const SizedBox(height: 15),
                  _buildDiaryItem("Log Summary", "Latest AI-Parsed Items", "${totals['cal']} cal", "C ${totals['carb']}g  F ${totals['fat']}g  P ${totals['prot']}g", Icons.auto_awesome),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
          if (isLoading) Container(color: Colors.white70, child: const Center(child: CircularProgressIndicator())),
          if (isMenuOpen) _buildMenuOverlay(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildExpandableFab(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF4A80F0).withOpacity(0.1),
              child: const Icon(Icons.person, color: Color(0xFF4A80F0), size: 28),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile['full_name'] ?? "User",
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Goal: ${targets['cal']} cal",
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF4A80F0).withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
          child: Text(
            DateFormat('MMM yyyy').format(selectedDate),
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4A80F0)),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today",
              style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A)),
            ),
            Text(
              "${(dailyScore / 10).toStringAsFixed(1)} Sparks",
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(10, (index) {
            bool active = (index * 10) < dailyScore;
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: active ? Colors.orange : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (index) {
          final day = DateTime.now().add(Duration(days: index - 3));
          bool isSelected = day.day == selectedDate.day && day.month == selectedDate.month;
          return Expanded(
            child: GestureDetector(
              onTap: () => _fetchData(day),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4A80F0) : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('E').format(day)[0],
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      day.day.toString(),
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCaloriesCard() {
    double calProgress = (totals['cal'] / targets['cal']).clamp(0.0, 1.0);
    double waterProgress = (totals['water'] / targets['water']).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          // Calories Section (2/3)
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Calories", style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w600)),
                    Text("${(calProgress * 100).toInt()}%", style: GoogleFonts.inter(color: const Color(0xFF4A80F0), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text("${totals['cal'].round()} cal", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900)),
                    Text(" / ${targets['cal'].round()}", style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: calProgress,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFF0F4FF),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4A80F0)),
                  ),
                ),
                const SizedBox(height: 8),
                Text("${(targets['cal'] - totals['cal']).round().clamp(0, 9999)} left", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Water Section (1/3)
          Expanded(
            flex: 1,
            child: _buildWaterBottle(waterProgress),
          ),
        ],
      ),
    );
  }

  Widget _buildWaterBottle(double progress) {
    return Column(
      children: [
        Text("Water", style: GoogleFonts.inter(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Bottle Outline
            Container(
              height: 100,
              width: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: Colors.blue.withOpacity(0.2), width: 2),
              ),
              child: Center(
                child: Text(
                  "${totals['water']}ml",
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF4A80F0)),
                ),
              ),
            ),
            // Water Fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 100 * progress,
              width: 45,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.4),
                borderRadius: BorderRadius.only(
                  bottomLeft: const Radius.circular(6),
                  bottomRight: const Radius.circular(6),
                  topLeft: Radius.circular(progress > 0.9 ? 10 : 0),
                  topRight: Radius.circular(progress > 0.9 ? 10 : 0),
                ),
              ),
            ),
            // Bottle Cap
            Positioned(
              top: 0,
              child: Container(
                height: 10,
                width: 25,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text("${(targets['water']).toInt()}ml", style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMacrosSection() {
    return Row(
      children: [
        _buildMacroCard("Protein", totals['prot'], targets['prot'], const Color(0xFFF39C12)),
        const SizedBox(width: 12),
        _buildMacroCard("Carbs", totals['carb'], targets['carb'], const Color(0xFF4AC2A4)),
        const SizedBox(width: 12),
        _buildMacroCard("Fat", totals['fat'], targets['fat'], const Color(0xFF8E44AD)),
      ],
    );
  }

  Widget _buildMacroCard(String label, dynamic taken, dynamic target, Color color) {
    double progress = (taken / target).clamp(0.0, 1.0);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 6),
            Text("${taken.round()}g", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            Text("of ${target.round()}g", style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Diary", style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
        Text("Refresh", style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildDiaryItem(String title, String subtitle, String cal, String details, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: const Color(0xFF4A80F0), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 13)),
                Text("$cal • $details", style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isMenuOpen) ...[
          _buildFabMenuItem(Icons.water_drop, "Water Intake", Colors.blue, _showWaterDialog),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.auto_awesome, "AI Meal Scan", Colors.purple, _showMealDialog),
          const SizedBox(height: 20),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => isMenuOpen = !isMenuOpen),
          backgroundColor: const Color(0xFF4A80F0),
          child: Icon(isMenuOpen ? Icons.close : Icons.add, size: 30),
        ),
      ],
    );
  }

  Widget _buildFabMenuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        setState(() => isMenuOpen = false);
        onTap();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1A1A1A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuOverlay() {
    return GestureDetector(
      onTap: () => setState(() => isMenuOpen = false),
      child: Container(color: Colors.black.withOpacity(0.4)),
    );
  }

  void _showWaterDialog() {
    int amount = 250;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Log Water Intake", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(builder: (c, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${amount}ml", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: const Color(0xFF4A80F0))),
              const SizedBox(height: 20),
              Slider(
                value: amount.toDouble(),
                min: 0, max: 1000, divisions: 20,
                onChanged: (v) => setS(() => amount = v.toInt()),
              ),
              Text("Drag to adjust", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            ],
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A80F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () { _logWater(amount); Navigator.pop(ctx); },
            child: const Text("Log Water"),
          ),
        ],
      ),
    );
  }

  void _showMealDialog() {
    final TextEditingController queryC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("AI Meal Analysis", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: queryC, 
          decoration: const InputDecoration(
            labelText: "What did you eat?", 
            hintText: "e.g. 2 eggs and a coffee",
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A80F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (queryC.text.isNotEmpty) {
                _logMealWithAI(queryC.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text("Analyse & Log"),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      height: 75, shape: const CircularNotchedRectangle(), notchMargin: 8, elevation: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_rounded, "Today", true),
          _buildNavItem(Icons.calendar_today_rounded, "Plan", false),
          const SizedBox(width: 48),
          _buildNavItem(Icons.bar_chart_rounded, "Stats", false),
          _buildNavItem(Icons.person_outline_rounded, "Profile", false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool active) {
    return Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: active ? const Color(0xFF4A80F0) : Colors.grey[400], size: 28), const SizedBox(height: 2), Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: active ? const Color(0xFF4A80F0) : Colors.grey[400]))]);
  }
}
