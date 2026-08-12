import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/route_recommendation_reason.dart';

class RouteRecommendationReasonCard extends StatelessWidget {
  const RouteRecommendationReasonCard({
    super.key,
    required this.reason,
    required this.isRecommended,
  });

  final RouteRecommendationReason reason;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7F9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 18,
              color: AppColors.brand,
            ),
            const SizedBox(width: 7),
            Text(
              isRecommended ? '이 경로가 추천된 이유' : '이 경로의 특징',
              key: const ValueKey('route-reason-title'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          reason.text,
          key: const ValueKey('route-reason-text'),
          style: const TextStyle(
            height: 1.55,
            fontSize: 13,
            color: AppColors.secondary,
          ),
        ),
      ],
    ),
  );
}
