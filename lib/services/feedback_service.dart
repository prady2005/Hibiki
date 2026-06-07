import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String feedbackApiUrl = String.fromEnvironment('FEEDBACK_API_URL');


class FeedbackSubmission {
  const FeedbackSubmission({
    required this.id,
    required this.rating,
    required this.category,
    required this.message,
    required this.createdAt,
  });

  factory FeedbackSubmission.fromJson(Map<String, dynamic> json) {
    return FeedbackSubmission(
      id: json['id']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? 'Other',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  final String id;
  final int rating;
  final String category;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'rating': rating,
      'category': category,
      'message': message,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

Future<bool> submitFeedback(FeedbackSubmission submission) async {
  try {
    await Supabase.instance.client
        .from('feedback')
        .insert({
          'id': submission.id,
          'rating': submission.rating,
          'category': submission.category,
          'message': submission.message,
          'created_at':
              submission.createdAt.toUtc().toIso8601String(),
        });

    return true;
  } catch (e) {
    debugPrint('Feedback upload failed: $e');
    return false;
  }
}
