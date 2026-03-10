import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

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
        // استخدام الخط الافتراضي كـ fallback إذا فشل GoogleFonts
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
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
  bool isCalendarExpanded = false;
  DateTime selectedDate = DateTime.now();
  final int dailyScore = 85;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildProfileHeader(),
              const SizedBox(height: 25),
              _buildTodayBar(),
              const SizedBox(height: 15),
              _buildCollapsibleCalendar(),
              const SizedBox(height: 25),
              _buildCaloriesCard(),
              const SizedBox(height: 20),
              _buildMacrosSection(),
              const SizedBox(height: 30),
              _buildDiaryHeader(),
              const SizedBox(height: 15),
              _buildDiaryItem("Breakfast", "Oatmeal and 2 more", "430 cal", "C 52%  F 26%  P 22%", Icons.coffee),
              _buildDiaryItem("Lunch", "Chicken Cobb Salad and 3 more", "546 cal", "C 50%  F 33%  P 17%", Icons.lunch_dining),
              _buildDiaryItem("Dinner", "Grilled Salmon", "600 cal", "C 20%  F 40%  P 40%", Icons.dinner_dining),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF4A80F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildProfileHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFF4A80F0).withOpacity(0.1),
          // استبدال صورة الشبكة بأيقونة لتجنب خطأ Failed to fetch
          child: const Icon(Icons.person, color: Color(0xFF4A80F0), size: 30),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Emad Alshamsi",
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            Text(
              "Ready to crush it today? 🔥",
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTodayBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              "Today",
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 32),
          ],
        ),
        Row(
          children: [
            Text(
              "${(dailyScore / 10).toStringAsFixed(1)} ",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.bolt, color: Colors.orange, size: 28),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsibleCalendar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isCalendarExpanded ? 300 : 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
             onTap: () => setState(() => isCalendarExpanded = !isCalendarExpanded),
            child: ListTile(
              dense: true,
              title: Text(
                DateFormat('MMMM yyyy').format(selectedDate),
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
              trailing: Icon(isCalendarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            ),
          ),
          if (!isCalendarExpanded)
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemBuilder: (context, index) {
                  final day = DateTime.now().add(Duration(days: index - 3));
                  bool isSelected = day.day == selectedDate.day;
                  return GestureDetector(
                    onTap: () => setState(() => selectedDate = day),
                    child: Container(
                      width: 45,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF4A80F0) : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('E').format(day)[0],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.white, size: 16)
                          else
                            Container(
                              height: 16,
                              width: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (isCalendarExpanded)
            const Expanded(
              child: Center(child: Text("Full Calendar View")),
            ),
        ],
      ),
    );
  }

  Widget _buildCaloriesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Calories", style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text("976 cal", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900)),
              Text(" / 2,074", style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[400])),
              const Spacer(),
              Text("1,098 left", style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: 0.47,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0F4FF),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4A80F0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacrosSection() {
    return Row(
      children: [
        _buildMacroCard("Carbs", "125 g", 0.4, const Color(0xFF4AC2A4)),
        const SizedBox(width: 12),
        _buildMacroCard("Fat", "32 g", 0.5, const Color(0xFF8E44AD)),
        const SizedBox(width: 12),
        _buildMacroCard("Protein", "47 g", 0.3, const Color(0xFFF39C12)),
      ],
    );
  }

  Widget _buildMacroCard(String label, String value, double progress, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
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
        Row(
           children: [
             Text("Diary", style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
           ]
        ),
        Text("View all", style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildDiaryItem(String title, String subtitle, String cal, String details, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: const Color(0xFF4A80F0)),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 13)),
                const SizedBox(height: 4),
                Text("$cal • $details", style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text("Log", style: GoogleFonts.inter(color: const Color(0xFF4A80F0), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      child: SizedBox(
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, "Today", true),
            _buildNavItem(Icons.calendar_month, "Plan", false),
            const SizedBox(width: 40),
            _buildNavItem(Icons.bar_chart, "Progress", false),
            _buildNavItem(Icons.more_horiz, "More", false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[400]),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[400])),
      ],
    );
  }
}
