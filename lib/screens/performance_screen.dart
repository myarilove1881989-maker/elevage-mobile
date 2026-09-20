import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

class PerformanceScreen extends StatefulWidget {
  final ApiService apiService;

  const PerformanceScreen({super.key, required this.apiService});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  List data = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final res = await widget.apiService.getPerformanceLots();

    setState(() {
      data = res;
      isLoading = false;
    });
  }

  Color getColor(double r) {
    if (r >= 80) return Colors.green;
    if (r >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('performance'))),
      body: ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, index) {
          final lot = data[index];
          final r = (lot["rentabilite"] ?? 0).toDouble();

          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: getColor(r),
                child: Text(
                  "#${index + 1}",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(lot["nom"]),
              subtitle: Text("${context.tr('margin')}: ${lot["marge"]}"),
              trailing: Text(
                "${r.toStringAsFixed(1)} %",
                style: TextStyle(
                  color: getColor(r),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
