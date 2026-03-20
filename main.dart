import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fl_chart/fl_chart.dart';

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
        textTheme: GoogleFonts.workSansTextTheme(),
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
  Map<String, double> totals = {"cal": 0.0, "prot": 0.0, "carb": 0.0, "fat": 0.0, "water": 0.0, "sleep": 0.0, "steps": 0.0};
  Map<String, double> targets = {"cal": 2000.0, "prot": 150.0, "carb": 250.0, "fat": 70.0, "water": 2000.0};
  Map<String, dynamic> profile = {"full_name": "Emad Alshamsi"};
  int dailyScore = 0;
  bool isLoading = true;
  List<dynamic> items = [];
  String _statsView = "Week"; // To toggle between Week/Month
  List<dynamic> calStatsData = []; // Real calorie data for chart
  List<dynamic> waterStatsData = []; // Real water data for chart
  List<dynamic> sleepStatsData = []; // Real sleep data for chart
  List<dynamic> stepsStatsData = []; // Real steps data for chart
  
  // Body Measurements State
  Map<String, dynamic> bodyMeasurements = {};
  bool isMaleFigure = true;
  String measurementUnit = 'cm';
  
  // Goals State (Plan Page)
  bool isEditingGoals = false;
  Map<String, Map<String, dynamic>> goals = {
    "Sleep": {"min": "", "max": "", "days": [false, false, false, false, false, true, false], "icon": "P1_sleep.svg"},
    "Calorie Intake": {"min": "", "max": "", "days": [false, false, false, false, false, true, false], "icon": "P2_food.svg"},
    "Water Intake": {"min": "", "max": "", "days": [false, false, false, false, false, true, false], "icon": "P3_water.svg"},
    "Walk Steps": {"min": "", "max": "", "days": [false, false, false, false, false, true, false], "icon": "P4_walk.svg"},
    "Protein": {"value": "", "min": "", "max": "", "days": [true, true, true, true, true, true, true], "icon": "04_protein.svg"},
    "Carbs": {"value": "", "min": "", "max": "", "days": [true, true, true, true, true, true, true], "icon": "05_carbs.svg"},
    "Fat": {"value": "", "min": "", "max": "", "days": [true, true, true, true, true, true, true], "icon": "06_fat.svg"},
    "Workout": {"min": null, "max": null, "days": [false, true, false, true, true, false, false], "icon": "P5_workout.svg"},
    "Measurement": {"min": null, "max": null, "days": [false, false, false, false, false, true, false], "icon": "P6_measure.svg"},
    "Progress Photo": {"min": null, "max": null, "days": [false, false, false, false, false, true, false], "icon": "P7_photo.svg"},
  };

  // Progress Photos State
  List<dynamic> progressPhotos = [];
  String selectedPhotoSide = 'Front';
  String? leftPhotoId, rightPhotoId;
  double comparisonValue = 0.5;

  final Map<String, TextEditingController> _goalControllers = {};
  
  TextEditingController _getGoalController(String key, String initialValue) {
    if (!_goalControllers.containsKey(key)) {
      _goalControllers[key] = TextEditingController(text: initialValue);
    }
    return _goalControllers[key]!;
  }

  void _clearGoalControllers() {
    for (var c in _goalControllers.values) {
      c.dispose();
    }
    _goalControllers.clear();
  }

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await _fetchData();
    await _fetchStats();
    await _fetchProgressPhotos();
  }

  Future<void> _fetchProgressPhotos() async {
    final url = "$baseUrl/get_progress_photos?user_id=$userId";
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          setState(() {
            progressPhotos = data['data'] ?? [];
            // Auto-select dates if available
            if (progressPhotos.isNotEmpty) {
               final filtered = progressPhotos.where((p) => p['side'].toString().toLowerCase() == selectedPhotoSide.toLowerCase()).toList();
               if (filtered.length >= 2) {
                 leftPhotoId = filtered[1]['id'].toString();
                 rightPhotoId = filtered[0]['id'].toString();
               } else if (filtered.length == 1) {
                 rightPhotoId = filtered[0]['id'].toString();
               }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch Photos Error: $e");
    }
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
          totals = {"cal": 0.0, "prot": 0.0, "carb": 0.0, "fat": 0.0, "water": 0.0, "sleep": 0.0, "steps": 0.0};
          targets = {"cal": 2000.0, "prot": 150.0, "carb": 250.0, "fat": 70.0, "water": 2000.0};

          final Map<String, dynamic>? newTotals = data['totals'] as Map<String, dynamic>?;
          final Map<String, dynamic>? newTargets = data['targets'] as Map<String, dynamic>?;

          if (newTotals != null) {
            totals['cal'] = (newTotals['cal'] ?? 0.0).toDouble();
            totals['prot'] = (newTotals['prot'] ?? 0.0).toDouble();
            totals['carb'] = (newTotals['carb'] ?? 0.0).toDouble();
            totals['fat'] = (newTotals['fat'] ?? 0.0).toDouble();
            totals['water'] = (newTotals['water'] ?? 0.0).toDouble();
            totals['sleep'] = (newTotals['sleep'] ?? 0.0).toDouble();
            totals['steps'] = (newTotals['steps'] ?? 0.0).toDouble();
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

          // Sync Goals from Profile
          if (newTargets != null && newTargets['habit_goals'] != null) {
             final Map<String, dynamic> remoteGoals = Map<String, dynamic>.from(newTargets['habit_goals']);
             remoteGoals.forEach((key, value) {
                if (goals.containsKey(key)) {
                   goals[key] = Map<String, dynamic>.from(value);
                }
             });
          }

          // Sync Body Measurements
          if (data['body_measurements'] != null) {
            bodyMeasurements = Map<String, dynamic>.from(data['body_measurements']);
            isMaleFigure = (bodyMeasurements['gender'] ?? 'male') == 'male';
            measurementUnit = bodyMeasurements['unit'] ?? 'cm';
            // Update controllers if they exist
            bodyMeasurements.forEach((key, value) {
               final cKey = "body-$key";
               if (_goalControllers.containsKey(cKey)) {
                 _goalControllers[cKey]!.text = value?.toString() ?? "";
               }
            });
          }

          // FIXED: Added null checks before using > operator
          double calP = (targets['cal'] ?? 0.0) > 0 ? ((totals['cal'] ?? 0.0) / (targets['cal'] ?? 1.0)) : 0.0;
          double waterP = (targets['water'] ?? 0.0) > 0 ? ((totals['water'] ?? 0.0) / (targets['water'] ?? 1.0)) : 0.0;

          dailyScore = (((calP + waterP) / 2) * 100).toInt().clamp(0, 100);
          _clearGoalControllers(); // Ensure controllers rebuild with new backend data
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

  Future<void> _fetchStats() async {
    final days = _statsView == "Week" ? 7 : 30;
    final url = "$baseUrl/get_stats?user_id=$userId&days=$days";
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20)); // Increased timeout
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          calStatsData = data['calories'] ?? [];
          waterStatsData = data['water'] ?? [];
          sleepStatsData = data['sleep'] ?? [];
          stepsStatsData = data['steps'] ?? [];
        });
      } else {
        debugPrint("Stats Server Error ${response.statusCode}: ${response.reasonPhrase}");
      }
    } catch (e) {
      debugPrint("Stats Fetch error details: $e");
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

  Future<void> _logSleep(double hours) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/log_sleep"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({"user_id": userId, "hours": hours, "date": dateStr}),
      );
      if (response.statusCode == 200) {
        await _fetchData(selectedDate);
        _showSuccess("Sleep logged: $hours hours");
      }
    } catch (e) {
      _showError("Failed to log sleep");
    }
  }

  Future<void> _logSteps(int steps) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDate);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/log_steps"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode({"user_id": userId, "steps": steps, "date": dateStr}),
      );
      if (response.statusCode == 200) {
        await _fetchData(selectedDate);
        _showSuccess("Steps logged: $steps");
      }
    } catch (e) {
      _showError("Failed to log steps");
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
      resizeToAvoidBottomInset: true, // Reverting to true for dialogs to work, will handle FAB manually
      body: Stack(
        children: [
          _buildBody(),
          if (isLoading) Container(color: Colors.white70, child: const Center(child: CircularProgressIndicator())),
          if (isMenuOpen) _buildMenuOverlay(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildExpandableFab(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0: return _buildDashboard();
      case 1: return _buildPlanPage();
      case 2: return _buildStatsScreen();
      default: return Center(child: Text("Page ${_currentIndex + 1}", style: GoogleFonts.workSans(fontSize: 18)));
    }
  }

  Widget _buildPlanPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Plan",
                style: GoogleFonts.workSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A))),
            const SizedBox(height: 20),
            
            // Goals List
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  ...goals.entries.where((e) => !["Protein", "Carbs", "Fat"].contains(e.key)).toList().asMap().entries.map((item) {
                    final entry = item.value;
                    bool isLast = item.key == goals.entries.where((e) => !["Protein", "Carbs", "Fat"].contains(e.key)).length - 1;
                    return Column(
                      children: [
                        _buildGoalItem(entry.key, entry.value),
                        if (!isLast) const DashedDivider(),
                      ],
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!isEditingGoals)
                        TextButton(
                          onPressed: () => setState(() => isEditingGoals = true),
                          child: Text("Modify",
                              style: GoogleFonts.workSans(
                                  color: const Color(0xFF4A80F0),
                                  fontWeight: FontWeight.w600)),
                        )
                      else ...[
                        TextButton(
                          onPressed: () {
                             _clearGoalControllers(); // Reset to current state
                             setState(() => isEditingGoals = false);
                          },
                          child: Text("Cancel",
                              style: GoogleFonts.workSans(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A80F0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _saveGoals,
                          child: const Text("Save Changes"),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            // Existing System Tools
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings_remote, color: Color(0xFF4A80F0)),
                      const SizedBox(width: 12),
                      Text("System Tools", style: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(Icons.link),
                      label: const Text("Test Connection"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A80F0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildBodyTrackingSection(),
            const SizedBox(height: 20),
            _buildProgressPhotoSection(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalItem(String title, Map<String, dynamic> data) {
    List<String> weekDays = ["Sa", "Su", "Mo", "Tu", "We", "Th", "Fr"];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset('assets/icons/${data['icon']}', width: 28, height: 28),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.workSans(
                            fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                    Text("Set a Day/s",
                        style: GoogleFonts.workSans(
                            fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey[500])),
                  ],
                ),
              ),
              if (data['min'] != null || data['max'] != null) ...[
                _buildGoalInput(title, "min", data['min']?.toString() ?? ""),
                const SizedBox(width: 10),
                _buildGoalInput(title, "max", data['max']?.toString() ?? ""),
              ],
              if (title == "Measurement" && bodyMeasurements['created_at'] != null) ...[
                Text(
                  _formatDate(bodyMeasurements['created_at']),
                  style: GoogleFonts.workSans(fontSize: 12, color: const Color(0xFF4A80F0), fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          if (title == "Calorie Intake") ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end, // Aligned with the end of the top row
              children: [
                _buildMacroSubInput("Protein", goals['Protein']!),
                const SizedBox(width: 12),
                _buildMacroSubInput("Carbs", goals['Carbs']!),
                const SizedBox(width: 12),
                _buildMacroSubInput("Fat", goals['Fat']!),
              ],
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final List<String> full = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"];
              final List<String> short = ["Sa", "Su", "Mo", "Tu", "We", "Th", "Fr"];
              final List<String> tiny = ["S", "S", "M", "T", "W", "T", "F"];
              
              final double dayWidth = constraints.maxWidth / 7;
              List<String> labels = short;
              if (dayWidth > 55) labels = full;
              else if (dayWidth < 38) labels = tiny;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  bool isSelected = data['days'][index];
                  return Flexible(
                    child: GestureDetector(
                      onTap: isEditingGoals
                          ? () => setState(() => data['days'][index] = !isSelected)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              isSelected ? 'assets/icons/PS_done.svg' : 'assets/icons/PS_not.svg',
                              width: 14, // Slightly smaller icons to fit better
                              height: 14,
                              color: isSelected ? const Color(0xFF4A80F0) : Colors.grey[200],
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                labels[index],
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.workSans(
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected ? Colors.grey[700] : Colors.grey[400]),
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
        ],
      ),
    );
  }

  Widget _buildMacroSubInput(String title, Map<String, dynamic> data) {
    String label = title; // Use full names "Protein", "Carbs", "Fat"
    return Row(
      children: [
        SvgPicture.asset('assets/icons/${data['icon']}', width: 14, height: 14),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.workSans(fontSize: 10, color: Colors.grey[600])),
        const SizedBox(width: 5),
        _buildGoalInput(title, "value", data['value']?.toString() ?? "", width: 45),
      ],
    );
  }

  Widget _buildGoalInput(String title, String type, String value, {double width = 60}) {
    final controllerKey = "$title-$type";
    final controller = _getGoalController(controllerKey, value);
    
    return Container(
      width: width,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: TextField(
        enabled: isEditingGoals,
        controller: controller,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        style: GoogleFonts.workSans(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          hintText: type == "value" ? "0" : type,
          hintStyle: GoogleFonts.workSans(fontSize: 10, color: Colors.grey[300], fontStyle: FontStyle.italic),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (val) {
           goals[title]![type] = val;
        },
      ),
    );
  }

  Future<void> _saveGoals() async {
    setState(() => isLoading = true);
    
    try {
      // Sync days from Calorie Intake to all macros
      if (goals.containsKey('Calorie Intake')) {
        final calDays = List<bool>.from(goals['Calorie Intake']!['days']);
        if (goals.containsKey('Protein')) goals['Protein']!['days'] = calDays;
        if (goals.containsKey('Carbs')) goals['Carbs']!['days'] = calDays;
        if (goals.containsKey('Fat')) goals['Fat']!['days'] = calDays;
      }

      int calTarget = _calculateTarget(goals['Calorie Intake'], targets['cal'] ?? 2000.0);
      int waterTarget = _calculateTarget(goals['Water Intake'], targets['water'] ?? 2000.0);
      int proteinTarget = _calculateTarget(goals['Protein'], targets['prot'] ?? 150.0);
      int carbTarget = _calculateTarget(goals['Carbs'], targets['carb'] ?? 250.0);
      int fatTarget = _calculateTarget(goals['Fat'], targets['fat'] ?? 70.0);

      final payload = {
        "user_id": userId,
        "habit_goals": goals,
        "calorie_target": calTarget,
        "water_target": waterTarget,
        "protein_target": proteinTarget,
        "carb_target": carbTarget,
        "fat_target": fatTarget,
      };

      final response = await http.post(
        Uri.parse("$baseUrl/update_goals"),
        headers: {"Content-Type": "application/json; charset=utf-8"},
        body: json.encode(payload),
      );
      
      if (response.statusCode == 200) {
        await _saveMeasurements(silent: true);
        _showSuccess("Goals saved successfully");
        setState(() => isEditingGoals = false);
        await _fetchData(selectedDate);
      } else {
        _showError("Failed to save goals: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Error saving goals: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  int _calculateTarget(Map<String, dynamic>? data, double fallback) {
    if (data == null) return fallback.toInt();
    double min = double.tryParse(data['min']?.toString() ?? "") ?? 0;
    double max = double.tryParse(data['max']?.toString() ?? "") ?? 0;
    double val = double.tryParse(data['value']?.toString() ?? "") ?? 0;

    if (val > 0) return val.toInt();
    if (min == 0 && max == 0) return fallback.toInt();
    if (min == 0) return max.toInt();
    if (max == 0) return min.toInt();
    double avg = (min + max) / 2;
    return (avg / 10).ceil() * 10;
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return "";
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return "";
    }
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 15),
            _buildTimeline(),
            const SizedBox(height: 20),
            _buildCaloriesCard(),
            const SizedBox(height: 20),
            _buildStatusRectangles(),
            _buildGroupedDiary(),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyTrackingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Body Measurement", style: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
              _buildUnitToggle(),
            ],
          ),
          const SizedBox(height: 8),
          _buildGenderToggle(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              double w = constraints.maxWidth;
              double h = w * 1.355; // Aspect ratio for the figure area (matches 1450/1070 images)
              
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  children: [
                    // 1. Bottom Layer: JPEG Figure
                    Positioned.fill(
                      child: Image.asset(
                        isMaleFigure ? 'assets/figure/male_figure.jpeg' : 'assets/figure/female_figure.jpeg',
                        key: ValueKey('fig-jpg-$isMaleFigure'),
                        width: w,
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                    // 2. Middle Layer: SVG Figure
                    Positioned.fill(
                      child: SvgPicture.asset(
                        isMaleFigure ? 'assets/figure/male_figure.svg' : 'assets/figure/female_figure.svg',
                        key: ValueKey('fig-svg-$isMaleFigure'),
                        width: w,
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                    // 3. Top Layer: Measurement Box Overlays
                    _buildPositionedInput("Neck", "neck", h * 0.14, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Shoulder", "shoulder", h * 0.19, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Chest", "chest", h * 0.24, w * 0.25, alignLeft: false),
                    
                    _buildPositionedInput("Biceps R", "biceps_r", h * 0.29, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Biceps L", "biceps_l", h * 0.29, w * 0.82, alignLeft: false),
                    
                    _buildPositionedInput("Forearms R", "forearms_r", h * 0.34, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Forearms L", "forearms_l", h * 0.34, w * 0.82, alignLeft: false),
                    
                    _buildPositionedInput("Waist", "waist", h * 0.39, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Hips", "hips", h * 0.43, w * 0.25, alignLeft: false),
                    
                    _buildPositionedInput("Thighs R", "thighs_r", h * 0.52, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Thighs L", "thighs_l", h * 0.52, w * 0.82, alignLeft: false),
                    
                    _buildPositionedInput("Calves R", "calves_r", h * 0.70, w * 0.25, alignLeft: false),
                    _buildPositionedInput("Calves L", "calves_l", h * 0.70, w * 0.82, alignLeft: false),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveMeasurements,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A80F0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: Text("Save Measurements", style: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionedInput(String label, String key, double top, double left, {bool alignLeft = true}) {
    return Positioned(
      top: top,
      left: left,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF4A80F0).withOpacity(0.3), width: 1),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
            child: TextField(
              controller: _getGoalController("body-$key", bodyMeasurements[key]?.toString() ?? ""),
              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
              style: GoogleFonts.workSans(fontSize: 10, fontWeight: FontWeight.w400, color: const Color(0xFF1A1A1A)),
              decoration: InputDecoration(
                isDense: true, 
                border: InputBorder.none, 
                contentPadding: alignLeft ? const EdgeInsets.only(left: 6) : EdgeInsets.zero, 
                hintText: "0", 
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 10)
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) {
                 bodyMeasurements[key] = val;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitToggle() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ["cm", "inch"].map((u) {
          bool isSel = measurementUnit == u;
          return GestureDetector(
            onTap: () => setState(() => measurementUnit = u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: isSel ? const Color(0xFF4A80F0) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Text(u, style: GoogleFonts.workSans(fontSize: 10, color: isSel ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGenderToggle() {
    return Row(
      children: [
        _buildGenderButton("Male", true, Icons.male),
        const SizedBox(width: 10),
        _buildGenderButton("Female", false, Icons.female),
      ],
    );
  }

  Widget _buildGenderButton(String label, bool isMale, IconData icon) {
    bool isSel = isMaleFigure == isMale;
    return GestureDetector(
      onTap: () => setState(() => isMaleFigure = isMale),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF4A80F0).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? const Color(0xFF4A80F0) : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSel ? const Color(0xFF4A80F0) : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.workSans(fontSize: 12, color: isSel ? const Color(0xFF4A80F0) : Colors.grey[600], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasureField(String label, String key) {
    final cKey = "body-$key";
    if (!_goalControllers.containsKey(cKey)) {
      _goalControllers[cKey] = TextEditingController(text: bodyMeasurements[key]?.toString() ?? "");
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.workSans(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Container(
            height: 35,
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            child: TextField(
              controller: _goalControllers[cKey],
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.workSans(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: InputBorder.none),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMeasurements({bool silent = false}) async {
    final Map<String, dynamic> payload = {
      "user_id": userId,
      "gender": isMaleFigure ? "male" : "female",
      "unit": measurementUnit,
    };
    
    // Add all measurement fields
    const fields = [
      "neck", "shoulder", "chest", "biceps_r", "biceps_l", 
      "forearms_r", "forearms_l", "waist", "hips", "thighs_r", 
      "thighs_l", "calves_r", "calves_l"
    ];
    
    for (var f in fields) {
      final val = double.tryParse(_goalControllers["body-$f"]?.text ?? "");
      if (val != null) payload[f] = val;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/update_measurements"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Measurements saved successfully!")));
          _fetchData(); // Refresh
        }
      } else {
        if (!silent) throw Exception("Failed to save measurements");
      }
    } catch (e) {
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
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
                  style: GoogleFonts.workSans(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Goal: ${(targets['cal'] ?? 2000).round()} cal",
                  style: GoogleFonts.workSans(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (dailyScore / 10).toStringAsFixed(1),
              style: GoogleFonts.workSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFFB800),
              ),
            ),
            const SizedBox(width: 6),
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
                          style: GoogleFonts.workSans(
                            color: isSelected ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          day.day.toString(),
                          style: GoogleFonts.workSans(
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
                        style: GoogleFonts.workSans(fontSize: 22, fontWeight: FontWeight.w600)),
                    Text(" / ${(targets['cal'] ?? 0).round()}", 
                        style: GoogleFonts.workSans(fontSize: 14, color: Colors.grey)),
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
            Text(label, style: GoogleFonts.workSans(fontSize: 11, color: Color.fromARGB(255, 0, 0, 0), fontWeight: FontWeight.w600)),
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
                  style: GoogleFonts.workSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: (target * 1.1 - taken) > 0 ? Colors.black : Colors.red, // Changed to black
                  ),
                ),
                TextSpan(
                  text: " / ${((target - taken) > 0 ? (target - taken).toInt() : 0)}g left",
                  style: GoogleFonts.workSans(
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
  String formattedGoal = "${goalInLiters.toStringAsFixed(1)} Ltr";
  double currentLogLiters = (totals['water'] ?? 0.0) / 1000;

  return Column(
    children: [
      // UPDATED ROW: Label on left, Goal on right
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Water",
              style: GoogleFonts.workSans(
                  color: waterColor, fontSize: 8, fontWeight: FontWeight.w600)),
          Text(formattedGoal, // Displays "2.00 Ltr"
              style: GoogleFonts.workSans(
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
                  style: GoogleFonts.workSans(
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


  Widget _buildStatusRectangles() {
    // Current date for comparison
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentSelectedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isToday = currentSelectedDate.isAtSameMomentAs(today);
    final isPast = currentSelectedDate.isBefore(today);

    final itemsList = [
      {"label": "Sleep", "icon": "P1_sleep.svg"},
      {"label": "Calory", "icon": "P2_food.svg"},
      {"label": "Water", "icon": "P3_water.svg"},
      {"label": "Walksteps", "icon": "P4_walk.svg"},
      {"label": "Workout", "icon": "P5_workout.svg"},
      {"label": "Measurement", "icon": "P6_measure.svg"},
      {"label": "Progress Photo", "icon": "P7_photo.svg"},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(itemsList.length, (index) {
        final item = itemsList[index];
        final label = item["label"]!;
        final iconName = item["icon"]!;
        
        String statusSvg = "PS_part.svg"; // Default for unimplemented or today
        String? scheduledDayText;

        // Map label to goal key
        String goalKey = label;
        if (label == "Calory") goalKey = "Calorie Intake";
        else if (label == "Water") goalKey = "Water Intake";
        else if (label == "Walksteps") goalKey = "Walk Steps";

        bool isScheduled = true; // Default to true if not found or no schedule
        final goalData = goals[goalKey];
        if (goalData != null && goalData['days'] != null) {
          int currentDayIndex = (currentSelectedDate.weekday % 7); // Dart: 1(Mon)-7(Sun)
          // Our array: index 0=Sat, 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri
          // Dart Mon=1 -> index 2. Sun=7 -> index 1. Sat=6 -> index 0.
          int mapIndex = (currentSelectedDate.weekday + 1) % 7;
          isScheduled = goalData['days'][mapIndex] == true;
        }

        if (!isScheduled) {
          statusSvg = "PS_scheduled.svg";
          // Find next scheduled day
          if (goalData != null && goalData['days'] != null) {
             List<dynamic> days = goalData['days'];
             List<String> weekDays = ["SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"];
             int currentDayIndex = (currentSelectedDate.weekday + 1) % 7;
             for (int i = 1; i <= 7; i++) {
                 int nextIndex = (currentDayIndex + i) % 7;
                 if (days[nextIndex] == true) {
                     scheduledDayText = weekDays[nextIndex];
                     break;
                 }
             }
          }
        } else if (!isToday && !isPast) {
          // Future / Scheduled normally
          statusSvg = "PS_scheduled.svg";
          scheduledDayText = DateFormat('E').format(currentSelectedDate).toUpperCase();
        } else {
          // Logic for implemented data: Calory and Water and Habits
          double? ratio;
          if (label == "Calory") {
            double currentCal = (totals['cal'] ?? 0.0).toDouble();
            double targetCal = (targets['cal'] ?? 2000.0).toDouble();
            if (targetCal > 0) ratio = currentCal / targetCal;
          } else if (label == "Water") {
            double currentWater = (totals['water'] ?? 0.0).toDouble();
            double targetWater = (targets['water'] ?? 2000.0).toDouble();
            if (targetWater > 0) ratio = currentWater / targetWater;
          } else if (label == "Sleep") {
            double currentSleep = totals['sleep'] ?? 0.0;
            double targetSleep = 8.0; // Default
            if (goalData != null) {
              var exactVal = double.tryParse(goalData['value']?.toString() ?? "");
              var minVal = double.tryParse(goalData['min']?.toString() ?? "");
              targetSleep = exactVal ?? minVal ?? 8.0;
            }
            if (targetSleep > 0) ratio = currentSleep / targetSleep;
          } else if (label == "Walksteps") {
            double currentSteps = totals['steps'] ?? 0.0;
            double targetSteps = 10000.0; // Default
            if (goalData != null) {
              var exactVal = double.tryParse(goalData['value']?.toString() ?? "");
              var minVal = double.tryParse(goalData['min']?.toString() ?? "");
              targetSteps = exactVal ?? minVal ?? 10000.0;
            }
            if (targetSteps > 0) ratio = currentSteps / targetSteps;
          }

          if (ratio != null) {
            // >= 90% is done, no upper limit for water/calories being "not done"
            if (ratio >= 0.9) {
              statusSvg = "PS_done.svg";
            } else {
              statusSvg = isPast ? "PS_not.svg" : "PS_part.svg";
            }
          } else {
            // Placeholder logic for others (Sleep, Walksteps, etc.)
            statusSvg = isPast ? "PS_not.svg" : "PS_part.svg";
          }
        }

        return Container(
          width: 38,
          height: 65,
          margin: EdgeInsets.only(left: index == 0 ? 0 : 9),
          decoration: BoxDecoration(
            color: const Color(0xFFD8D4C7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Status Icon (PS_done, PS_not, etc.) - NOW ON TOP
              Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/$statusSvg',
                    width: 24,
                    height: 24,
                  ),
                  if (statusSvg == "PS_scheduled.svg" && scheduledDayText != null)
                    Text(
                      scheduledDayText,
                      style: GoogleFonts.workSans(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF7D7969),
                      ),
                    ),
                ],
              ),
              // Main Icon (e.g., P1_sleep.svg) - NOW BELOW
              SvgPicture.asset(
                'assets/icons/$iconName',
                width: 22,
                height: 22,
              ),
            ],
          ),
        );
      }),
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
                Text(title, style: GoogleFonts.workSans(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.workSans(color: Colors.grey[500], fontSize: 13)),
                Text("$cal • $details", style: GoogleFonts.workSans(color: Colors.grey[400], fontSize: 11)),
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
          _buildFabMenuItem(Icons.bedtime, "Sleep", Colors.indigo, _showSleepDialog),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.restaurant, "Meal (AI)", Colors.purple, _showMealDialog),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.water_drop, "Water Intake", Colors.blue, _showWaterDialog),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.directions_walk, "Steps", Colors.orange, _showStepsDialog),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.straighten, "Measurement", Colors.teal, () {
            setState(() {
              _currentIndex = 1; // Plan Page
              isEditingGoals = true;
              isMenuOpen = false;
            });
          }),
          const SizedBox(height: 12),
          _buildFabMenuItem(Icons.add_a_photo, "Progress Photo", Colors.pink, _showUploadPhotosDialog),
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
                Text(label, style: GoogleFonts.workSans(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1A1A1A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showUploadPhotosDialog() {
     final controllers = {
       'front': TextEditingController(),
       'side': TextEditingController(),
       'back': TextEditingController(),
     };
     bool isUploading = false;

     showDialog<void>(
       context: context,
       builder: (ctx) => StatefulBuilder(builder: (context, setS) {
         return AlertDialog(
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
           title: Text("Upload Progress Photos", style: GoogleFonts.workSans(fontWeight: FontWeight.bold)),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               Text("Enter image URLs for each side:", style: GoogleFonts.workSans(fontSize: 13, color: Colors.grey[600])),
               const SizedBox(height: 16),
               _buildUrlField(controllers['front']!, "Front View"),
               const SizedBox(height: 10),
               _buildUrlField(controllers['side']!, "Side View"),
               const SizedBox(height: 10),
               _buildUrlField(controllers['back']!, "Back View"),
               if (isUploading) ...[
                 const SizedBox(height: 20),
                 const CircularProgressIndicator(),
               ]
             ],
           ),
           actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
             ElevatedButton(
               onPressed: isUploading ? null : () async {
                 setS(() => isUploading = true);
                 try {
                   for (var entry in controllers.entries) {
                     if (entry.value.text.isNotEmpty) {
                        await _uploadPhoto(entry.value.text, entry.key);
                     }
                   }
                   await _fetchProgressPhotos();
                   if (mounted) Navigator.pop(ctx);
                 } finally {
                   setS(() => isUploading = false);
                 }
               },
               style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A80F0)),
               child: const Text("Upload All"),
             ),
           ],
         );
       }),
     );
  }

  Widget _buildUrlField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: "https://example.com/photo.jpg",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Future<void> _uploadPhoto(String url, String side) async {
    final res = await http.post(
      Uri.parse("$baseUrl/upload_progress_photo"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"user_id": userId, "photo_url": url, "side": side}),
    );
    if (res.statusCode != 200) {
      debugPrint("Upload failed for $side: ${res.body}");
    }
  }

  Widget _buildMenuOverlay() {
    return GestureDetector(
      onTap: () => setState(() => isMenuOpen = false),
      child: Container(color: Colors.black.withOpacity(0.4)),
    );
  }

  Widget _buildProgressPhotoSection() {
    final sidePhotos = progressPhotos.where((p) => p['side'].toString().toLowerCase() == selectedPhotoSide.toLowerCase()).toList();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Progress Photo", style: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 16),
          _buildComparisonControls(sidePhotos),
          const SizedBox(height: 20),
          _buildComparisonSlider(sidePhotos),
        ],
      ),
    );
  }

  Widget _buildComparisonControls(List<dynamic> sidePhotos) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildDropdown("Date 1", leftPhotoId, sidePhotos, (v) => setState(() => leftPhotoId = v)),
          const SizedBox(width: 8),
          _buildDropdown("Side", selectedPhotoSide, ["Front", "Side", "Back"], (v) {
             setState(() {
               selectedPhotoSide = v!;
               // Auto-reset dates for new side
               final filtered = progressPhotos.where((p) => p['side'].toString().toLowerCase() == v.toLowerCase()).toList();
               if (filtered.length >= 2) {
                 leftPhotoId = filtered[1]['id'].toString();
                 rightPhotoId = filtered[0]['id'].toString();
               } else {
                 leftPhotoId = null;
                 rightPhotoId = filtered.isNotEmpty ? filtered[0]['id'].toString() : null;
               }
             });
          }),
          const SizedBox(width: 8),
          _buildDropdown("Date 2", rightPhotoId, sidePhotos, (v) => setState(() => rightPhotoId = v)),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String? currentId, dynamic items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF5F9FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentId,
          hint: Text(label, style: GoogleFonts.workSans(fontSize: 11)),
          style: GoogleFonts.workSans(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
          items: items is List<String> 
            ? items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList()
            : items.map<DropdownMenuItem<String>>((p) => DropdownMenuItem(value: p['id'].toString(), child: Text(DateFormat('MMM dd').format(DateTime.parse(p['created_at']))))).toList(),
          onChanged: (v) => onChanged(v),
        ),
      ),
    );
  }

  Widget _buildComparisonSlider(List<dynamic> sidePhotos) {
    if (sidePhotos.isEmpty) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text("No photos uploaded yet.", style: GoogleFonts.workSans(color: Colors.grey[400])),
          ],
        ),
      );
    }

    final leftPhoto = sidePhotos.firstWhere((p) => p['id'].toString() == leftPhotoId, orElse: () => sidePhotos.first);
    final rightPhoto = sidePhotos.firstWhere((p) => p['id'].toString() == rightPhotoId, orElse: () => sidePhotos.length > 1 ? sidePhotos[1] : sidePhotos.first);

    return LayoutBuilder(builder: (context, constraints) {
        double width = constraints.maxWidth;
        double height = width * 1.0; // Square-ish comparison

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: height,
            width: width,
            child: Stack(
              children: [
                // Right photo (background)
                Positioned.fill(child: Image.network(rightPhoto['photo_url'], fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey[200], child: const Icon(Icons.error)))),
                
                // Left photo (foreground with clipper)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: AlwaysStoppedAnimation(comparisonValue),
                    builder: (context, _) {
                      return ClipRect(
                        clipper: _SliderClipper(comparisonValue),
                        child: Image.network(leftPhoto['photo_url'], fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey[100], child: const Icon(Icons.error))),
                      );
                    },
                  ),
                ),
                
                // Slider Handle
                Positioned(
                  left: width * comparisonValue - 15,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        comparisonValue = (comparisonValue + details.primaryDelta! / width).clamp(0.0, 1.0);
                      });
                    },
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(color: Color(0xFF4A80F0), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                        child: const Icon(Icons.compare_arrows, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
                
                // Separator Line
                Positioned(
                  left: width * comparisonValue - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        );
      });
  }

  void _showWaterDialog() {
    int amount = 250;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Log Water Intake", style: GoogleFonts.workSans(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(builder: (c, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${amount}ml", style: GoogleFonts.workSans(fontSize: 32, fontWeight: FontWeight.w900, color: const Color(0xFF4A80F0))),
              const SizedBox(height: 20),
              Slider(
                value: amount.toDouble(),
                min: 0,
                max: 1000,
                divisions: 20,
                onChanged: (double v) => setS(() => amount = v.toInt()),
              ),
              Text("Drag to adjust", style: GoogleFonts.workSans(fontSize: 12, color: Colors.grey)),
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

  void _showSleepDialog() {
    double hours = 8.0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Log Sleep (Hours)", style: GoogleFonts.workSans(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(builder: (c, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${hours.toStringAsFixed(1)} h", style: GoogleFonts.workSans(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.indigo)),
              const SizedBox(height: 20),
              Slider(
                value: hours,
                min: 0,
                max: 16,
                divisions: 32,
                onChanged: (double v) => setS(() => hours = v),
              ),
              Text("Drag to adjust", style: GoogleFonts.workSans(fontSize: 12, color: Colors.grey)),
            ],
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              _logSleep(hours);
              Navigator.pop(ctx);
            },
            child: const Text("Log Sleep"),
          ),
        ],
      ),
    );
  }

  void _showStepsDialog() {
    int steps = 5000;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Log Walk Steps", style: GoogleFonts.workSans(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(builder: (c, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$steps", style: GoogleFonts.workSans(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.orange)),
              const SizedBox(height: 20),
              Slider(
                value: steps.toDouble(),
                min: 0,
                max: 30000,
                divisions: 60,
                onChanged: (double v) => setS(() => steps = v.toInt()),
              ),
              Text("Drag to adjust", style: GoogleFonts.workSans(fontSize: 12, color: Colors.grey)),
            ],
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              _logSteps(steps);
              Navigator.pop(ctx);
            },
            child: const Text("Log Steps"),
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
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("AI Meal Analysis", style: GoogleFonts.workSans(fontWeight: FontWeight.bold)),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
              children: [
                StatefulBuilder(builder: (context, setDialogState) {
                  return DropdownButton<String>(
                    value: selectedMealType,
                    isExpanded: true,
                    items: mealTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) => setDialogState(() => selectedMealType = val!),
                  );
                }),
                const SizedBox(height: 15),
                TextField(
                  controller: queryC, 
                  autofocus: true,
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
      "Breakfast": const Color(0xFFE67E22), 
      "Lunch": const Color(0xFF4A80F0),     
      "Dinner": const Color(0xFF2C3E50),    
      "Snack": const Color(0xFF27AE60),     
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text("Diary", style: GoogleFonts.workSans(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
          leading: const Icon(Icons.menu_book, color: Color(0xFF4A80F0)),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: existingTypes.map((type) {
            final mealItems = grouped[type]!;
            final color = mealColors[type] ?? Colors.grey;
            double totalCal = 0, totalP = 0, totalC = 0, totalF = 0;
            for (var i in mealItems) {
              totalCal += (i['calories'] ?? 0).toDouble();
              totalP += (i['protein'] ?? 0).toDouble();
              totalC += (i['carbs'] ?? 0).toDouble();
              totalF += (i['fat'] ?? 0).toDouble();
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.1))),
              child: ExpansionTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: SvgPicture.asset('assets/icons/$type.svg', width: 24, height: 24,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => Icon(Icons.restaurant, color: color)),
                ),
                title: Text(type, style: GoogleFonts.workSans(fontWeight: FontWeight.w600, fontSize: 17, color: color)),
                subtitle: RichText(
                  text: TextSpan(
                    style: GoogleFonts.workSans(fontSize: 11, color: Colors.grey[500]),
                    children: [
                      TextSpan(text: "${totalCal.round()} cal • ", style: GoogleFonts.workSans(color: const Color(0xFF4A80F0), fontWeight: FontWeight.w500)),
                      TextSpan(text: "P ${totalP.round()}g  ", style: GoogleFonts.workSans(color: const Color(0xFFF39C12), fontWeight: FontWeight.w500)),
                      TextSpan(text: "C ${totalC.round()}g  ", style: GoogleFonts.workSans(color: const Color(0xFF4AC2A4), fontWeight: FontWeight.w500)),
                      TextSpan(text: "F ${totalF.round()}g", style: GoogleFonts.workSans(color: const Color(0xFF8E44AD), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                children: mealItems.map((item) {
                  String foodName = (item['food_name'] ?? "").toString().replaceAll("\n", " ").trim();
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    visualDensity: const VisualDensity(vertical: -4),
                    title: Text(foodName, style: GoogleFonts.workSans(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text("${item['calories']} cal • P ${item['protein']}g C ${item['carbs']}g F ${item['fat']}g", style: GoogleFonts.workSans(fontSize: 11, color: Colors.grey)),
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
                        const SizedBox(width: 1),
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
            );
          }).toList(),
        ),
      ),
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
          Text(label, style: GoogleFonts.workSans(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: labelColor)),
        ],
      ),
    );
  }

  Widget _buildStatsScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Statistics", style: GoogleFonts.workSans(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                _buildStatsToggle(),
              ],
            ),
            const SizedBox(height: 20),
            _buildChartCard("Sleep", sleepStatsData, double.tryParse(goals['Sleep']?['min']?.toString() ?? "") ?? 8.0, Colors.indigo),
            const SizedBox(height: 20),
            _buildChartCard("Calorie Intake", calStatsData, targets['cal'] ?? 2000, const Color(0xFF4A80F0)),
            const SizedBox(height: 20),
            _buildChartCard("Water Intake", waterStatsData, (targets['water'] ?? 2000).toDouble(), const Color(0xFF4AC2A4)),
            const SizedBox(height: 20),
            _buildChartCard("Walk Steps", stepsStatsData, double.tryParse(goals['Walk Steps']?['min']?.toString() ?? "") ?? 10000.0, Colors.orange),
            const SizedBox(height: 100), // Extra space for FAB
          ],
        ),
      ),
    );
  }

  Widget _buildStatsToggle() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ["Week", "Month"].map((view) {
          bool isSelected = _statsView == view;
          return GestureDetector(
            onTap: () {
              setState(() {
                _statsView = view;
                calStatsData = [];
                waterStatsData = [];
                sleepStatsData = [];
                stepsStatsData = [];
              });
              _fetchStats();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4A80F0) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(view, style: GoogleFonts.workSans(fontSize: 10, color: isSelected ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChartCard(String title, List<dynamic> data, double target, Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.workSans(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10), // تعديل الهامش الجانبي للشارت هنا
              child: LineChart(
                LineChartData(
                clipData: FlClipData(top: false, bottom: true, left: true, right: true), // Allow peaks to breathe
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32, // Fixed height for labels area
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        const style = TextStyle(color: Colors.grey, fontSize: 10);
                        int idx = val.toInt();
                        if (val != idx.toDouble()) return const Text(""); // Prevent duplicate labels due to buffers
                        if (data.isEmpty || idx < 0 || idx >= data.length) return const Text("");
                        
                        try {
                          final date = DateTime.parse(data[idx]['date']);
                          String text = _statsView == "Week" ? DateFormat('E').format(date) : (idx % 7 == 0 ? DateFormat('Md').format(date) : "");
                          if (text.isEmpty) return const Text("");
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            space: 12, // Consistent gap from chart to text
                            child: Text(text, style: style),
                          );
                        } catch (e) {}
                        return const Text("");
                      },
                    ),
                  ),
                ),
                minX: -0.2, // Small buffer at start
                maxX: data.isEmpty 
                  ? (_statsView == "Week" ? 7 : 30).toDouble() 
                  : (data.length - 1 + (_statsView == "Month" ? 6 : 1)).toDouble() + 0.2, // Small buffer at end
                minY: 0,
                maxY: target * 1.4, // Increased headspace (25%) to prevent peak clipping
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _getSpots(data, target, true), 
                    isCurved: true,
                    color: themeColor,
                    barWidth: 2.5, // Thinner lines
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: themeColor.withOpacity(0.1)),
                  ),
                  if (data.isNotEmpty) LineChartBarData(
                    spots: _getForecastSpots(data, target),
                    isCurved: true,
                    color: themeColor.withOpacity(0.4),
                    barWidth: 2, // Thinner lines
                    dashArray: [5, 5],
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: _getSpots(data, target, false), 
                    isCurved: false,
                    color: Colors.grey[300],
                    barWidth: 1.5, // Thinner lines
                    dashArray: [5, 5],
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
              swapAnimationDuration: Duration.zero, // Disable animation to prevent "stretching" glitch
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.workSans(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  List<FlSpot> _getSpots(List<dynamic> data, double target, bool isAchieved) {
    int count = _statsView == "Week" ? 7 : 30;
    return List.generate(count, (i) {
      if (!isAchieved) return FlSpot(i.toDouble(), target);
      if (i < data.length) return FlSpot(i.toDouble(), (data[i]['value'] ?? 0.0).toDouble());
      return FlSpot(i.toDouble(), 0);
    });
  }

  List<FlSpot> _getForecastSpots(List<dynamic> data, double target) {
    if (data.isEmpty) return [];
    int lastIdx = data.length - 1;
    double lastVal = (data[lastIdx]['value'] ?? 0.0).toDouble();
    double sum = 0; int divisor = 0;
    for (var d in data) {
      double v = (d['value'] ?? 0).toDouble();
      if (v > 0) { sum += v; divisor++; }
    }
    double avg = (divisor > 0) ? sum / divisor : target;
    
    int forecastDays = _statsView == "Month" ? 6 : 1;
    List<FlSpot> spots = [FlSpot(lastIdx.toDouble(), lastVal)];
    for (int i = 1; i <= forecastDays; i++) {
      spots.add(FlSpot((lastIdx + i).toDouble(), avg));
    }
    return spots;
  } // End of _getForecastSpots
} // End of _DashboardScreenState

class DashedDivider extends StatelessWidget {
  const DashedDivider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: DashboardDashedLinePainter(),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class DashboardDashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 3.0;
    const dashSpace = 3.0;
    double currentX = 0;

    // Dashed line
    while (currentX < size.width) {
      canvas.drawLine(Offset(currentX, 0), Offset(currentX + dashWidth, 0), paint);
      currentX += dashWidth + dashSpace;
    }

    // Tiny Triangles at ends
    final trianglePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Left triangle
    Path leftPath = Path();
    leftPath.moveTo(-2, 0);
    leftPath.lineTo(2, -2.5);
    leftPath.lineTo(2, 2.5);
    leftPath.close();
    canvas.drawPath(leftPath, trianglePaint);

    // Right triangle
    Path rightPath = Path();
    rightPath.moveTo(size.width + 2, 0);
    rightPath.lineTo(size.width - 2, -2.5);
    rightPath.lineTo(size.width - 2, 2.5);
    rightPath.close();
    canvas.drawPath(rightPath, trianglePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

int val(int i) => (i * 137 + 42);

class _SliderClipper extends CustomClipper<Rect> {
  final double value;
  _SliderClipper(this.value);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * value, size.height);
  }

  @override
  bool shouldReclip(_SliderClipper oldClipper) => oldClipper.value != value;
}