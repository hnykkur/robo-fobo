/// Disco melodies as `(Hz, durationUnits)`. `0` Hz = rest.
/// Duration unit is an **eighth note** at disco BPM, except [DiscoSong.axelF]
/// which uses **sixteenth notes** (see player).
enum DiscoSong {
  funkyTown('Funky Town'),
  tetris('Tetris'),
  starWarsDisco('Star Wars Disco'),
  weAreTheRobots('We Are the Robots'),
  happyBirthday('Happy Birthday'),
  axelF('Axel F');

  const DiscoSong(this.label);
  final String label;

  /// Notes for this song at the shared disco tempo.
  List<(int, int)> get melody => switch (this) {
        DiscoSong.funkyTown => _funkyTown,
        DiscoSong.tetris => _tetris,
        DiscoSong.starWarsDisco => _starWarsDisco,
        DiscoSong.weAreTheRobots => _weAreTheRobots,
        DiscoSong.happyBirthday => _happyBirthday,
        DiscoSong.axelF => _axelF,
      };

  /// Beat subdivisions per duration unit (2 = eighths, 4 = sixteenths).
  int get durationDivisor => this == DiscoSong.axelF ? 4 : 2;
}

/// Funky Town hook + groove + descending synth.
const _funkyTown = <(int, int)>[
  (523, 1), (523, 1), (440, 1), (523, 1),
  (0, 1), (392, 1), (0, 1), (392, 1),
  (523, 1), (698, 1), (659, 1), (523, 1),
  (0, 2),
  (523, 1), (523, 1), (440, 1), (523, 1),
  (0, 1), (392, 1), (0, 1), (392, 1),
  (523, 1), (698, 1), (659, 1), (523, 1),
  (0, 2),
  (262, 1), (262, 1), (262, 1), (262, 1),
  (330, 2), (330, 1), (330, 1),
  (392, 1), (392, 2),
  (659, 2), (587, 1), (523, 2),
  (523, 1), (523, 1), (440, 1), (523, 1),
  (0, 1), (392, 1), (0, 1), (392, 1),
  (523, 1), (698, 1), (659, 1), (523, 1),
  (0, 2),
  (523, 1), (523, 1), (466, 1), (466, 1),
  (415, 1), (415, 1), (392, 1), (392, 1),
  (349, 1), (349, 1), (311, 1), (311, 1),
  (262, 4), (0, 2),
];

/// Korobeiniki (Tetris theme).
const _tetris = <(int, int)>[
  (659, 2), (494, 1), (523, 1), (587, 2), (523, 1), (494, 1),
  (440, 2), (440, 1), (523, 1), (659, 2), (587, 1), (523, 1),
  (494, 2), (494, 1), (523, 1), (587, 2), (659, 2),
  (523, 2), (440, 2), (440, 2), (0, 2),
  (587, 2), (698, 1), (880, 2), (784, 1), (698, 1),
  (659, 2), (523, 1), (659, 2), (587, 1), (523, 1),
  (494, 2), (494, 1), (523, 1), (587, 2), (659, 2),
  (523, 2), (440, 2), (440, 2), (0, 2),
];

/// Star Wars Main Title opening (Luke’s theme fanfare).
const _starWarsDisco = <(int, int)>[
  // F F F | Bb—— | F5—— |
  (349, 1), (349, 1), (349, 1), (466, 6), (698, 6),
  // Eb D C | Bb5—— | F5— |
  (622, 1), (587, 1), (523, 1), (932, 6), (698, 3),
  // Eb D C | Bb5—— | F5— |
  (622, 1), (587, 1), (523, 1), (932, 6), (698, 3),
  // Eb D Eb | C—— |
  (622, 1), (587, 1), (622, 1), (523, 6),
  (0, 2),
  // Repeat opening for a fuller loop
  (349, 1), (349, 1), (349, 1), (466, 6), (698, 6),
  (622, 1), (587, 1), (523, 1), (932, 6), (698, 3),
  (622, 1), (587, 1), (622, 1), (523, 6),
  (0, 4),
];

/// Kraftwerk “The Robots” — Dm arp, descending hook, chorus, “Ja tvoi sluga”.
const _weAreTheRobots = <(int, int)>[
  // Dm intro arpeggio
  (294, 1), (349, 1), (440, 1), (587, 1),
  (294, 1), (349, 1), (440, 1), (587, 1),
  (294, 1), (349, 1), (440, 1), (587, 1),
  (294, 1), (349, 1), (440, 1), (587, 1),
  // Descending robot lead (Dm)
  (587, 1), (587, 1), (587, 1), (523, 1),
  (466, 1), (466, 1), (466, 1), (440, 1),
  (392, 1), (392, 1), (392, 1), (349, 1),
  (294, 4), (0, 2),
  // “We are the robots” (Bbm then Gm)
  (349, 1), (349, 1), (349, 1), (349, 1), (311, 2), (277, 2),
  (349, 1), (349, 1), (349, 1), (349, 1), (311, 2), (277, 2),
  (294, 1), (294, 1), (294, 1), (294, 1), (262, 2), (233, 2),
  (294, 1), (294, 1), (294, 1), (294, 1), (262, 2), (233, 2),
  (0, 2),
  // “Ja tvoi sluga / ja tvoi rabotnik”
  (440, 2), (440, 2), (523, 2), (494, 1), (440, 1),
  (392, 2), (392, 2), (494, 2), (440, 1), (392, 1),
  (440, 2), (440, 2), (523, 2), (494, 1), (440, 1),
  (392, 4), (0, 2),
];

/// Happy Birthday (C major).
const _happyBirthday = <(int, int)>[
  (262, 1), (262, 1), (294, 2), (262, 2), (349, 2), (330, 4),
  (262, 1), (262, 1), (294, 2), (262, 2), (392, 2), (349, 4),
  (262, 1), (262, 1), (523, 2), (440, 2), (349, 2), (330, 2), (294, 4),
  (466, 1), (466, 1), (440, 2), (349, 2), (392, 2), (349, 4),
  (0, 2),
];

/// Axel F (RTTTL-style lead) — durations are **sixteenths** (see [DiscoSong.durationDivisor]).
const _axelF = <(int, int)>[
  // F Ab | F . F | Bb F F
  (349, 2), (415, 2), (349, 1), (0, 1), (349, 1), (466, 2), (349, 2), (349, 1),
  // Eb D Db C | Bb
  (622, 2), (587, 1), (554, 1), (523, 2), (466, 2),
  // F Ab | F | Bb3 F
  (349, 1), (415, 1), (349, 2), (233, 2), (349, 4),
  (0, 2),
  // Second pass
  (349, 2), (415, 2), (349, 1), (0, 1), (349, 1), (466, 2), (349, 2), (349, 1),
  (622, 2), (587, 1), (554, 1), (523, 2), (466, 2),
  (349, 1), (415, 1), (349, 2), (233, 2), (349, 4),
  (0, 4),
];
