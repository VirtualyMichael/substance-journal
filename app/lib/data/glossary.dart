/// Plain-language definitions of the words used across the app. Kept short and conservative: where a
/// term varies by person or substance the entry says so.
class GlossaryEntry {
  const GlossaryEntry(this.term, this.group, this.definition, {this.also = const []});

  final String term;
  final String group;
  final String definition;

  /// Other names people use for it, so a search finds it.
  final List<String> also;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return term.toLowerCase().contains(q) || also.any((a) => a.toLowerCase().contains(q)) || definition.toLowerCase().contains(q);
  }
}

const glossaryGroups = ['Timing', 'Doses', 'Tolerance and dependence', 'Safety', 'Testing', 'Substance types', 'In this app'];

const glossary = <GlossaryEntry>[
  // ---- timing ----
  GlossaryEntry('Onset', 'Timing', 'How long after taking it before you first notice anything. Taking it on a full stomach, or by a slower route, usually makes it later.'),
  GlossaryEntry('Come-up', 'Timing', 'The stretch after onset while the effects build toward their strongest. It can be gentle or sharp, and can feel unsettling the first time.', also: ['comeup']),
  GlossaryEntry('Peak', 'Timing', 'The part of the experience where effects are strongest. Some substances have a single high point, others stay near it for a while.'),
  GlossaryEntry('Plateau', 'Timing', 'A stretch near the peak where the effects stay roughly steady instead of rising or falling.'),
  GlossaryEntry('Come-down', 'Timing', 'The fading from the peak back toward normal. Also called the offset. It often feels flatter or more tired than the rest.', also: ['offset', 'comedown']),
  GlossaryEntry('Afterglow', 'Timing', 'Milder effects that linger after the main experience ends, such as shifts in mood, energy or sleep. They can last hours or, for some substances, days.', also: ['after-effects', 'aftereffects']),
  GlossaryEntry('Duration', 'Timing', 'How long the main effects last, from taking it until they are over. It does not usually include the lingering after-effects.', also: ['total']),
  GlossaryEntry('Redosing', 'Timing', 'Taking more during the same session. Many substances take a long time to arrive in full, so feeling little early on is a common reason people take too much. Waiting for the full effect first matters.', also: ['redose', 'boosting']),
  GlossaryEntry('Set and setting', 'Timing', 'Your mindset going in (set) and the place and company around you (setting). Both strongly shape how an experience goes, especially with psychedelics.'),

  // ---- doses ----
  GlossaryEntry('Threshold dose', 'Doses', 'The smallest amount that produces any noticeable effect. It is the lowest rung of the dose scale, not a recommended amount.'),
  GlossaryEntry('Light, common, strong, heavy', 'Doses', 'Published bands that describe how much is in a dose relative to others. Common is the middle of the scale, not a safe limit. Heavy means a much higher chance of unpleasant or dangerous effects, and more is not better.', also: ['dose bands', 'light dose', 'common dose', 'strong dose', 'heavy dose']),
  GlossaryEntry('Route of administration', 'Doses', 'How a substance gets into the body: oral (swallowed), sublingual (under the tongue), buccal (in the cheek), insufflated (snorted), smoked, vaporized, rectal, intramuscular, intravenous or transdermal. Faster routes generally mean quicker, shorter and more intense effects.', also: ['route', 'roa', 'insufflated', 'sublingual', 'buccal']),
  GlossaryEntry('Bioavailability', 'Doses', 'The share of a dose that actually reaches the bloodstream. It differs a lot between routes: smoking or injecting usually delivers more of a dose than swallowing it.'),
  GlossaryEntry('Half-life', 'Doses', 'How long it takes for the amount of a substance in the body to fall by half. After several half-lives most of it has gone, but its effects or after-effects can outlast it.'),
  GlossaryEntry('Standard drink', 'Doses', 'A unit for comparing alcoholic drinks: about 14 g of pure alcohol (roughly a 12 oz beer at 5%, 5 oz of wine at 12%, or 1.5 oz of 40% spirits). Other countries define it differently.'),
  GlossaryEntry('BAC', 'Doses', 'Blood alcohol concentration, the share of alcohol in the blood. The app shows an estimate from your drinks, body details and time. Real BAC varies with food, health and more, so an estimate is never a basis for deciding you are fit to drive.', also: ['blood alcohol']),

  // ---- tolerance and dependence ----
  GlossaryEntry('Tolerance', 'Tolerance and dependence', 'Needing more of a substance for the same effect after repeated use. It builds at different speeds and fades at different speeds, so this app tracks it per substance.'),
  GlossaryEntry('Cross-tolerance', 'Tolerance and dependence', 'Tolerance to one substance that also reduces the effect of related ones, such as different psychedelics sharing a tolerance group. The app counts them together.'),
  GlossaryEntry('Baseline', 'Tolerance and dependence', 'Your tolerance back at its starting level, as if you had not used the substance recently. The tolerance page estimates when you will get there.'),
  GlossaryEntry('Physical dependence', 'Tolerance and dependence', 'When the body adapts so that stopping causes withdrawal. Stopping some substances (alcohol, benzodiazepines and opioids, among others) can be dangerous without medical help.'),
  GlossaryEntry('Withdrawal', 'Tolerance and dependence', 'Unpleasant or dangerous symptoms when someone who is dependent stops or cuts down. If you might be dependent, talk to a clinician before stopping suddenly.'),
  GlossaryEntry('Addiction potential', 'Tolerance and dependence', 'How likely a substance is to lead to compulsive use, as described by the reference sources. It is a general guide about the substance, not a prediction about you.', also: ['abuse potential']),

  // ---- safety ----
  GlossaryEntry('Harm reduction', 'Safety', 'Practical steps to make drug use less risky, whether or not someone plans to stop. This app is built on it: knowing doses, timing and risky mixes, and not using alone.'),
  GlossaryEntry('Potentiation', 'Safety', 'When one substance makes another stronger or longer lasting. It is a common cause of unexpectedly strong effects and accidental overdoses.'),
  GlossaryEntry('Synergy', 'Safety', 'Substances together having a bigger effect than expected from either alone. It can feel good and still be dangerous, for example with depressants.'),
  GlossaryEntry('Overdose', 'Safety', 'Taking enough of a substance to cause serious harm, such as stopped or slowed breathing, seizure or loss of consciousness. Call your local emergency number straight away and stay with the person.'),
  GlossaryEntry('Respiratory depression', 'Safety', 'Dangerously slow or shallow breathing. It is the main way depressants such as opioids, alcohol, benzodiazepines and GHB cause death, and mixing them multiplies the risk.'),
  GlossaryEntry('Serotonin syndrome', 'Safety', 'A potentially life-threatening reaction from too much serotonin activity, with agitation, sweating, fever, tremor and fast heartbeat. It can follow certain combinations, including some antidepressants with MDMA or other serotonergic drugs. It needs urgent medical care.'),
  GlossaryEntry('Recovery position', 'Safety', 'Lying someone who is unconscious but breathing on their side with the top knee bent, so their airway stays clear if they vomit. Stay with them and call for help.'),
  GlossaryEntry('Sitter', 'Safety', 'A sober person who stays with someone during an experience to keep them safe and help if things go badly. Recommended for strong psychedelic doses.', also: ['trip sitter']),
  GlossaryEntry('MAOI', 'Safety', 'A monoamine oxidase inhibitor: a medication (or a plant ingredient in some brews) that slows the breakdown of serotonin and related chemicals. It can make many substances dangerously stronger and is a common source of serious interactions.', also: ['monoamine oxidase inhibitor']),

  // ---- testing ----
  GlossaryEntry('Adulterant', 'Testing', 'Something else mixed into a substance, often cheaper or more potent, that the buyer does not expect. Fentanyl in other drugs is a well-known and dangerous example.', also: ['cut']),
  GlossaryEntry('Reagent test', 'Testing', 'A kit that drops a chemical onto a tiny sample and watches for a colour change. It can hint at what a sample contains but cannot show purity, dose or everything else in it, and colours are judged by eye.', also: ['marquis', 'mecke', 'mandelin', 'ehrlich', 'simon', 'colour test', 'color test']),
  GlossaryEntry('Test strip', 'Testing', 'An immunoassay strip that looks for one substance or class, such as fentanyl or benzodiazepines. A positive means it was detected. A negative only means this strip did not detect it.', also: ['fentanyl strip', 'fentanyl test strip']),
  GlossaryEntry('Presumptive result', 'Testing', 'A result that suggests but does not confirm what something is. Reagent and strip tests are presumptive. Only a laboratory can confirm.'),

  // ---- substance types ----
  GlossaryEntry('Depressant', 'Substance types', 'Slows the nervous system: alcohol, opioids, benzodiazepines, GHB and similar. Mixing depressants is a leading cause of fatal overdose.', also: ['downer', 'sedative']),
  GlossaryEntry('Stimulant', 'Substance types', 'Speeds up the nervous system, raising heart rate, alertness and body temperature: caffeine, nicotine, amphetamines and cocaine. Strong doses strain the heart.', also: ['upper']),
  GlossaryEntry('Psychedelic', 'Substance types', 'Substances such as LSD and psilocybin that change perception, thought and mood, often through serotonin receptors. Effects depend heavily on set and setting.', also: ['hallucinogen']),
  GlossaryEntry('Dissociative', 'Substance types', 'Substances such as ketamine and DXM that produce a sense of detachment from body or surroundings. Higher doses can cause loss of coordination and awareness of danger.'),
  GlossaryEntry('Empathogen', 'Substance types', 'Substances such as MDMA that increase feelings of emotional closeness and openness.', also: ['entactogen']),
  GlossaryEntry('Cannabinoid', 'Substance types', 'A compound that acts on the body\'s cannabinoid system. THC is the main one that causes the high, and CBD is a non-intoxicating one.', also: ['thc', 'cbd']),

  // ---- in this app ----
  GlossaryEntry('Experience', 'In this app', 'A session in your journal: one or more doses taken around the same time, with notes and ratings.'),
  GlossaryEntry('Ingestion', 'In this app', 'One logged dose: what, how much, how it was taken and when.', also: ['dose', 'entry']),
  GlossaryEntry('Shulgin rating scale', 'In this app', 'A scale for how strong an experience felt: minus (no effect), plus-minus (threshold), then + through ++++ (light to overwhelming). It is how you rate an experience in this app.', also: ['shulgin', 'rating']),
  GlossaryEntry('Cross-checked', 'In this app', 'A compound whose dose bands from PsychonautWiki also appear within 50% in TripSit\'s data. It is two sources agreeing, not a full audit. Audited compounds were checked by hand against several sources.', also: ['audited']),
  GlossaryEntry('Estimate', 'In this app', 'Timings, curves, BAC and tolerance in the app are modelled from published ranges. They are guides for planning and reflection, never measurements and never a clearance to drive or use machinery.'),
];
