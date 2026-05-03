// Mirrors `lib/sports.ts` from the Next.js SPA.

const List<String> usStreamSports = [
  'General',
  'NFL',
  'NBA',
  'MLB',
  'NHL',
  'UFC',
  'MLS',
  'NCAA Football',
  'NCAA Basketball',
  'NASCAR',
  'Formula 1',
  'IndyCar',
  'WNBA',
  'PGA Tour',
  'LPGA',
  'Tennis',
  'Boxing',
  'Olympics',
  'Esports',
  'Other',
];

const String defaultStreamSport = 'General';
const String sportFilterAll = 'all';
const String sportFilterUnspecified = '__unspecified__';

String streamSportLabel(String? sport) {
  if (sport == null || sport.trim().isEmpty) return 'Not specified';
  return sport.trim();
}
