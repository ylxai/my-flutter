/// Schedule type for automated tasks
enum ScheduleType { once, hourly, daily, weekly, custom }

/// Scheduled task for automatic copy operations
class ScheduledTask {
  String id;
  String name;
  String profileName;
  bool isEnabled;
  ScheduleType scheduleType;
  Duration executionTime;
  int intervalHours;
  List<int> selectedDays; // Day of week (1=Mon, 7=Sun)
  DateTime? lastRun;
  DateTime? nextRun;
  int successCount;
  int failureCount;

  ScheduledTask({
    String? id,
    this.name = '',
    this.profileName = '',
    this.isEnabled = true,
    this.scheduleType = ScheduleType.daily,
    this.executionTime = const Duration(hours: 2),
    this.intervalHours = 24,
    this.selectedDays = const [],
    this.lastRun,
    this.nextRun,
    this.successCount = 0,
    this.failureCount = 0,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profileName': profileName,
        'isEnabled': isEnabled,
        'scheduleType': scheduleType.name,
        'executionTime': executionTime.inSeconds,
        'intervalHours': intervalHours,
        'selectedDays': selectedDays,
        'lastRun': lastRun?.toIso8601String(),
        'nextRun': nextRun?.toIso8601String(),
        'successCount': successCount,
        'failureCount': failureCount,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    return ScheduledTask(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      profileName: json['profileName'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      scheduleType: ScheduleType.values.firstWhere(
        (e) => e.name == json['scheduleType'],
        orElse: () => ScheduleType.daily,
      ),
      executionTime:
          Duration(seconds: json['executionTime'] as int? ?? 7200),
      intervalHours: json['intervalHours'] as int? ?? 24,
      selectedDays: (json['selectedDays'] as List<dynamic>?)
              ?.cast<int>() ??
          [],
      lastRun: json['lastRun'] != null
          ? DateTime.parse(json['lastRun'] as String)
          : null,
      nextRun: json['nextRun'] != null
          ? DateTime.parse(json['nextRun'] as String)
          : null,
      successCount: json['successCount'] as int? ?? 0,
      failureCount: json['failureCount'] as int? ?? 0,
    );
  }
}
