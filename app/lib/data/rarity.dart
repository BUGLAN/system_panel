import 'package:flutter/material.dart';

/// 稀有度阶梯 —— 真源：prototype/opus-v2-dir/js/content.js L14-23。
/// 颜色只出现在稀有度本身上，不做氛围。
class Rarity {
  const Rarity({
    required this.rank,
    required this.i,
    required this.color,
    required this.exp,
    required this.coin,
    required this.pt,
    required this.min,
  });

  final String rank;
  final int i;
  final Color color;
  final int exp;
  final int coin;
  final int pt;

  /// 该难度的建议时限（分钟）
  final int min;

  static const List<String> ranks = <String>['F', 'E', 'D', 'C', 'B', 'A', 'S'];

  static const Map<String, Rarity> table = <String, Rarity>{
    'F': Rarity(
      rank: 'F',
      i: 0,
      color: Color(0xFF9AA3B2),
      exp: 12,
      coin: 6,
      pt: 1,
      min: 10,
    ),
    'E': Rarity(
      rank: 'E',
      i: 1,
      color: Color(0xFF4ADE80),
      exp: 20,
      coin: 10,
      pt: 1,
      min: 15,
    ),
    'D': Rarity(
      rank: 'D',
      i: 2,
      color: Color(0xFF38BDF8),
      exp: 32,
      coin: 15,
      pt: 2,
      min: 20,
    ),
    'C': Rarity(
      rank: 'C',
      i: 3,
      color: Color(0xFFA78BFA),
      exp: 50,
      coin: 24,
      pt: 2,
      min: 30,
    ),
    'B': Rarity(
      rank: 'B',
      i: 4,
      color: Color(0xFFFBBF24),
      exp: 78,
      coin: 38,
      pt: 3,
      min: 40,
    ),
    'A': Rarity(
      rank: 'A',
      i: 5,
      color: Color(0xFFFB923C),
      exp: 120,
      coin: 60,
      pt: 4,
      min: 60,
    ),
    'S': Rarity(
      rank: 'S',
      i: 6,
      color: Color(0xFFFF4D5E),
      exp: 200,
      coin: 100,
      pt: 6,
      min: 90,
    ),
  };

  static Rarity of(String rank) => table[rank] ?? table['F']!;
}
