import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  // تفعيل التعامل مع أخطاء الخطوط في الويب لـ Zapp
  try {
    GoogleFonts.config.allowRuntimeFetching = true;
  } catch (e) {
    // print('GoogleFonts config failed:  $e'); // Commented out to avoid console noise in production
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
      supportedLocales: const [Locale('ar', 'AE'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // CONFIG: Base URL for backend - FIXED: Removed extra space
  final String baseUrl = "https://gym-5pvr.onrender.com";
  final String userId = "6ec22654-069a-4ab1-8535-3ac66e0b5047";

  bool isMenuOpen = false;
  DateTime selectedDate = DateTime.now();
  int _currentIndex = 0;

  // Data State
  Map<String, double> totals = {"cal": 0.0, "prot": 0.0, "carb": 0.0, "fat": 0.0, "water": 0.0};
  Map<String, double> targets = {"cal": 2000.0, "prot": 150.0, "carb": 250.0, "fat": 70.0, "water": 2000.0};
  Map<String, dynamic> profile = {"full_name": "Emad Alshamsi"};
  int dailyScore = 0;
  bool isLoading = true;
  List<dynamic> items = [];

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

    debugPrint("Attempting fetch from: $url");

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          selectedDate = targetDate;

          // إرساء قيم افتراضية قبل التحديث لضمان عدم بقاء بيانات اليوم السابق
          totals = {"cal": 0.0, "prot": 0.0, "carb": 0.0, "fat": 0.0, "water": 0.0};
          targets = {"cal": 2000.0, "prot": 150.0, "carb": 250.0, "fat": 70.0, "water": 2000.0};

          final Map<String, dynamic>? newTotals = data['totals'] as Map<String, dynamic>?;
          final Map<String, dynamic>? newTargets = data['targets'] as Map<String, dynamic>?;

          if (newTotals != null) {
            totals['cal'] = (newTotals['cal'] ?? 0.0).toDouble();
            totals['prot'] = (newTotals['prot'] ?? 0.0).toDouble();
            totals['carb'] = (newTotals['carb'] ?? 0.0).toDouble();
            totals['fat'] = (newTotals['fat'] ?? 0.0).toDouble();
            totals['water'] = (newTotals['water'] ?? 0.0).toDouble();
          }

          if (newTargets != null) {
            targets['cal'] = (newTargets['cal'] ?? 2000.0).toDouble();
            targets['prot'] = (newTargets['prot'] ?? 150.0).toDouble();
            targets['carb'] = (newTargets['carb'] ?? 250.0).toDouble();
            targets['fat'] = (newTargets['fat'] ?? 70.0).toDouble();
            targets['water'] = (newTargets['water'] ?? 2000.0).toDouble();
          }

          profile = data['profile'] ?? profile;
          items = data['items'] ?? [];

          // FIXED: Added null checks before using > operator
          double calP = (targets['cal'] ?? 0.0) > 0 ? ((totals['cal'] ?? 0.0) / (targets['cal'] ?? 1.0)) : 0.0;
          double waterP = (targets['water'] ?? 0.0) > 0 ? ((totals['water'] ?? 0.0) / (targets['water'] ?? 1.0)) : 0.0;

          dailyScore = (((calP + waterP) / 2) * 100).toInt().clamp(0, 100);
        });
      } else {
        _showError("Server Error ${response.statusCode}: ${response.reasonPhrase}");
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      String errorMsg = "Connection Error.\n";
      _showError("$errorMsg");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    final url = "$baseUrl/health";
    _showSuccess("Testing connection to: $url");
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        _showSuccess("Connection Successful!\nServer: ${res.body}");
        await _fetchData();
      } else {
        _showError("Health check failed (${res.statusCode}). Check Render logs.");
      }
    } catch (e) {
      _showError("Failed to reach server: $e\nURL: $url");
    }
  }

  Future<void> _logMealWithAI(String query, [String mealType = "Lunch"]) async {
    setState(() => isLoading = true);
    // FIXED: Removed extra spaces in date format
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    final url = "$baseUrl/log_meal?user_id=$userId&meal_type=$mealType";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({
          "user_id": userId,
          "meal_type": mealType,
          "items_ar": query,
          "date": dateStr,
        }),
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
    // FIXED: Removed extra spaces in date format
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/log_water"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({
          "user_id": userId,
          "amount_ml": amount,
          "date": dateStr,
        }),
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
      resizeToAvoidBottomInset: false, // Prevents FAB and other elements from jumping when keyboard appears
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
                  _buildDiaryHeader(),
                  const SizedBox(height: 15),
                  _buildGroupedDiary(),
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
                  "Goal: ${(targets['cal'] ?? 2000).round()} cal",
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
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4A80F0)),
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
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            Row(
              children: [
                Text(
                  (dailyScore / 10).toStringAsFixed(1),
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFFB800),
                  ),
                ),
                const SizedBox(width: 6),
                // 2. Replace the Icon widget with this:
                SvgPicture.asset(
                  'assets/icons/01_spark.svg',
                  width: 20,
                  height: 20,
                  color: const Color(0xFFFFB800),
                  colorBlendMode: BlendMode.srcIn,
                )
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(10, (index) {
            bool active = (index * 10) < dailyScore;
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFFFB800) : Colors.grey[200]!,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
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
          );
        },
      ),
    );
  }

  Widget _buildCaloriesCard() {
    // FIXED: Added null checks before using > operator
    double calProgress = (targets['cal'] ?? 0.0) > 0 ? ((totals['cal'] ?? 0.0) / (targets['cal'] ?? 1.0)).clamp(0.0, 1.0) : 0.0;
    double waterProgress = (targets['water'] ?? 0.0) > 0 ? ((totals['water'] ?? 0.0) / (targets['water'] ?? 1.0)).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side: Calories & Macros (80% weight)
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Add your SVG here
                    SvgPicture.asset(
                      'assets/icons/03_fire.svg', // Ensure your fire.svg is in assets/icons/
                      width: 24,
                      height: 24,
                      color: const Color(0xFF4A80F0),
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(width: 8), // Add some space between icon and text
                    Text("${(totals['cal'] ?? 0).round()} cal", 
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900)),
                    Text(" / ${(targets['cal'] ?? 0).round()}", 
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: calProgress,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFF0F4FF),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4A80F0)),
                  ),
                ),
                const SizedBox(height: 20),
                // FIXED: Removed duplicated macro row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _buildInnerMacro("Protein", totals['prot'] ?? 0, targets['prot'] ?? 0,Color.fromRGBO(243, 156, 18, 1),'assets/icons/04_protein.svg')),
                    const SizedBox(width: 16),
                    Expanded(child: _buildInnerMacro("Carbs", totals['carb'] ?? 0, targets['carb'] ?? 0, Color.fromRGBO(74, 194, 164, 1), 'assets/icons/05_carbs.svg')),
                    const SizedBox(width: 16),
                    Expanded(child: _buildInnerMacro("Fat", totals['fat'] ?? 0, targets['fat'] ?? 0,Color.fromRGBO(142, 68, 173, 1), 'assets/icons/06_fat.svg')),
                  ],
                ),
              ],
            ),
          ),

          // The Gap (Separation)
          const SizedBox(width: 20),

          // Right Side: Water Bottle (20% weight)
          Expanded(
            flex: 1,
            child: _buildWaterBottle(waterProgress),
          ),
        ],
      ),
    );
  }

  Widget _buildInnerMacro(String label, double taken, double target, Color color, String assetPath) {
    double progress = target > 0 ? (taken / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // The new SVG icon
            SvgPicture.asset(
              assetPath,
              width: 14,
              height: 14,
              color: color,
              colorBlendMode: BlendMode.srcIn,
            ),
             const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: Color.fromARGB(255, 0, 0, 0), fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${taken.toInt()}g",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: (target * 1.1 - taken) > 0 ? Colors.black : Colors.red, // Changed to black
                  ),
                ),
                TextSpan(
                  text: " / ${((target - taken) > 0 ? (target - taken).toInt() : 0)}g left",
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    fontWeight: FontWeight.normal,
                    color: (target * 1.1 - taken) > 0 ? Colors.grey : Colors.grey, // Optionally turn red when over
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

Widget _buildWaterBottle(double progress) {
  const Color waterColor = Color.fromARGB(255, 57, 179, 246);
  const double totalHeight = 100;
  
  // Assuming your goal is stored in targets['water']
  double goalInLiters = (targets['water'] ?? 0) / 1000;
  String formattedGoal = "${goalInLiters.toStringAsFixed(2)} Ltr";
  double currentLogLiters = (totals['water'] ?? 0.0) / 1000;

  return Column(
    children: [
      // UPDATED ROW: Label on left, Goal on right
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Water",
              style: GoogleFonts.inter(
                  color: waterColor, fontSize: 8, fontWeight: FontWeight.w600)),
          Text(formattedGoal, // Displays "2.00 Ltr"
              style: GoogleFonts.inter(
                  color: Colors.blueGrey.shade300, 
                  fontSize: 8, 
                  fontWeight: FontWeight.w500)),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        height: totalHeight,
        width: 65,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. The Water Fill
            Positioned(
              bottom: 2,
              left: 3,
              right: 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                height: totalHeight * progress.clamp(0.02, 0.96),
                color: waterColor.withOpacity(0.5),
              ),
            ),
            
            // 2. The Bottle Mask/Overlay
            SvgPicture.asset(
              'assets/icons/02_water_bottle.svg',
              fit: BoxFit.fill,
              width: 111,
              height: totalHeight,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
            SvgPicture.asset(
              'assets/icons/02_water_bottle3.svg',
              fit: BoxFit.fill,
              width: 111,
              height: totalHeight,
              color: const Color.fromARGB(255, 143, 143, 143),
              colorBlendMode: BlendMode.srcIn,
            ),
            Positioned(
              bottom: 33, // Adjust this to move the label up/down to match your red box
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8), // Glass effect
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${currentLogLiters.toStringAsFixed(2)} L",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color:  Color.fromARGB(255, 0, 0, 0),
                  ),
                ),
              ),
            ),
            
          ],
        ),
      ),
    ],
  );
}

  Widget _buildDiaryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Diary", style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
        TextButton(
          onPressed: _testConnection,
          child: Text("Test Connect", style: GoogleFonts.inter(color: const Color(0xFF4A80F0), fontWeight: FontWeight.w600)),
        ),
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
          elevation: 4,
          child: SvgPicture.asset(isMenuOpen ? 'assets/icons/delete.svg' : 'assets/icons/09_add.svg', 
            width: 28, height: 28, 
            color: Colors.white, 
            colorBlendMode: BlendMode.srcIn),
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
    showDialog<void>(
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
                min: 0,
                max: 1000,
                divisions: 20,
                onChanged: (double v) => setS(() => amount = v.toInt()),
              ),
              Text("Drag to adjust", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            ],
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A80F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              _logWater(amount);
              Navigator.pop(ctx);
            },
            child: const Text("Log Water"),
          ),
        ],
      ),
    );
  }

  void _showMealDialog() {
    final TextEditingController queryC = TextEditingController();
    String selectedMealType = "Breakfast";
    final mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"];
    
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        scrollable: true, // Allows the dialog to be scrollable when the keyboard is visible
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("AI Meal Analysis", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: selectedMealType,
                  isExpanded: true,
                  items: mealTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) => setDialogState(() => selectedMealType = val!),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: queryC, 
                  autofocus: true, // Opens keyboard immediately
                  decoration: const InputDecoration(
                    labelText: "What did you eat?", 
                    hintText: "e.g. 2 eggs and a coffee",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A80F0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                if (queryC.text.isNotEmpty) {
                  _logMealWithAI(queryC.text, selectedMealType);
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Analyse & Log"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedDiary() {
    if (items.isEmpty) return const SizedBox.shrink();

    final Map<String, List<dynamic>> grouped = {};
    for (var item in items) {
      final type = item['meal_type'] ?? "Snack";
      grouped.putIfAbsent(type, () => []).add(item);
    }

    final typesOrder = ["Breakfast", "Lunch", "Dinner", "Snack"];
    final existingTypes = typesOrder.where((t) => grouped.containsKey(t)).toList();

    final Map<String, Color> mealColors = {
      "Breakfast": const Color(0xFFE67E22), // Deep Orange
      "Lunch": const Color(0xFF4A80F0),     // Primary Blue
      "Dinner": const Color(0xFF2C3E50),    // Midnight Blue
      "Snack": const Color(0xFF27AE60),     // Forest Green
    };

    return Column(
      children: existingTypes.map((type) {
        final mealItems = grouped[type]!;
        final Color color = mealColors[type] ?? const Color(0xFF4A80F0);
        double totalCal = 0, totalP = 0, totalC = 0, totalF = 0;
        for (var i in mealItems) {
          totalCal += (i['calories'] ?? 0).toDouble();
          totalP += (i['protein'] ?? 0).toDouble();
          totalC += (i['carbs'] ?? 0).toDouble();
          totalF += (i['fat'] ?? 0).toDouble();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: ExpansionTile(
              leading: Container(
                padding: const EdgeInsets.all(6), // Reduced from 8 to give more room
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: SvgPicture.asset('assets/icons/$type.svg', width: 24, height: 24, // Standard 24x24
                  fit: BoxFit.contain,
                  placeholderBuilder: (context) => Icon(Icons.restaurant, color: color)),
              ),
              title: Text(type, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
              subtitle: RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                  children: [
                    TextSpan(text: "${totalCal.round()} cal • ", style: GoogleFonts.inter(color: const Color(0xFF4A80F0), fontWeight: FontWeight.bold)),
                    TextSpan(text: "P ${totalP.round()}g  ", style: GoogleFonts.inter(color: const Color(0xFFF39C12), fontWeight: FontWeight.bold)),
                    TextSpan(text: "C ${totalC.round()}g  ", style: GoogleFonts.inter(color: const Color(0xFF4AC2A4), fontWeight: FontWeight.bold)),
                    TextSpan(text: "F ${totalF.round()}g", style: GoogleFonts.inter(color: const Color(0xFF8E44AD), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              children: mealItems.map((item) {
                // Ensure name is single line and ignores newlines
                String foodName = (item['food_name'] ?? "").toString().replaceAll("\n", " ").trim();
                
                return ListTile(
                  dense: true, // Tightens the layout
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0), // Zero vertical padding
                  visualDensity: const VisualDensity(vertical: -4), // Pulls items closer
                  title: Text(
                    foodName, 
                    style: GoogleFonts.inter(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text("${item['calories']} cal • P ${item['protein']}g C ${item['carbs']}g F ${item['fat']}g", style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _showEditMealDialog(item['id'], foodName),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          child: SvgPicture.asset('assets/icons/edit.svg', width: 20, height: 20, 
                            placeholderBuilder: (_) => Icon(Icons.edit, size: 20, color: Colors.grey[800])),
                        ),
                      ),
                      const SizedBox(width: 1), // ADJUST THIS NUMBER for space between edit and delete
                      GestureDetector(
                        onTap: () => _deleteMealItem(item['id']),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          child: SvgPicture.asset('assets/icons/delete.svg', width: 19, height: 19, 
                            placeholderBuilder: (_) => Icon(Icons.delete, size: 20, color: Colors.grey[800])),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showEditMealDialog(dynamic itemId, String oldName) {
    final TextEditingController editC = TextEditingController(text: oldName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Meal"),
        content: TextField(controller: editC, decoration: const InputDecoration(labelText: "Meal Details")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _updateMealItem(itemId, editC.text);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateMealItem(dynamic itemId, String newName) async {
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/update_meal_item"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({
          "item_id": itemId.toString(),
          "new_food": newName,
        }),
      );
      if (res.statusCode == 200) {
        _fetchData(selectedDate);
        _showSuccess("Updated");
      }
    } catch (e) {
      _showError("Update failed");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteMealItem(dynamic itemId) async {
    setState(() => isLoading = true);
    try {
      final res = await http.delete(Uri.parse("$baseUrl/delete_meal_item?item_id=$itemId"));
      if (res.statusCode == 200) {
        _fetchData(selectedDate);
        _showSuccess("Deleted");
      }
    } catch (e) {
      _showError("Delete failed");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: Colors.white,
      elevation: 20,
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem("Today", 'assets/icons/07_home.svg', 0),
          _buildNavItem("Plan", 'assets/icons/08_calender.svg', 1),
          const SizedBox(width: 48),
          _buildNavItem("Stats", 'assets/icons/10_stats.svg', 2),
          _buildNavItem("Profile", 'assets/icons/11_profile.svg', 3),
        ],
      ),
    );
  }

  Widget _buildNavItem(String label, String iconPath, int index) {
    bool isSel = _currentIndex == index;
    Color labelColor = isSel ? const Color(0xFF4A80F0) : Colors.grey[400]!;
    
    // Switch to '...2.svg' for inactive state as requested
    String currentIconPath = isSel ? iconPath : iconPath.replaceFirst('.svg', '2.svg');

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(currentIconPath, width: 24, height: 24),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: labelColor)),
        ],
      ),
    );
  }

}