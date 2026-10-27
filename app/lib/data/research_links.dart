import 'package:sj_core/sj_core.dart';

/// A place to read more, with what you will find there.
class ResearchLink {
  const ResearchLink(this.title, this.description, this.url);
  final String title;
  final String description;
  final String url;
}

/// TripSit factsheet addresses for the compounds whose slug is not simply their name.
const _tripsitSlugs = {
  'psilocybin_mushrooms': 'mushrooms',
  'alcohol': 'alcohol',
  'nicotine': 'nicotine',
  'cannabis': 'cannabis',
  'lsd': 'lsd',
  'dmt': 'dmt',
  'mdma': 'mdma',
  '2c-b': '2c-b',
  'ketamine': 'ketamine',
};

const psychonautWikiIndex = ResearchLink(
  'PsychonautWiki: psychoactive substance index',
  'Every substance on the wiki, with dose, duration, effects and interaction pages.',
  'https://psychonautwiki.org/wiki/Psychoactive_substance_index',
);

/// Links to read before taking something, for one compound. Everything here is a reputable
/// harm-reduction or reference site; the app copies none of their text beyond what is credited.
List<ResearchLink> researchLinksFor(Substance s) {
  final name = Uri.encodeQueryComponent(s.name);
  final slug = _tripsitSlugs[s.key];
  return [
    if (s.wikiUrl != null)
      ResearchLink('PsychonautWiki: ${s.name}', 'Full profile: effects, doses, durations, interactions and harm-reduction notes.', s.wikiUrl!),
    ResearchLink('Erowid: ${s.name}', 'Search the vaults for dose charts, effects, legal notes and first-hand experience reports.', 'https://www.erowid.org/search.php?q=$name'),
    if (slug != null)
      ResearchLink('TripSit factsheet: ${s.name}', 'A short, plain-language summary with dosage, effects and combination advice.', 'https://tripsit.me/factsheets/$slug')
    else
      const ResearchLink('TripSit factsheets', 'Find this compound in TripSit\'s list of factsheets, if they have one.', 'https://tripsit.me/factsheets'),
    const ResearchLink('TripSit combination chart', 'Pick two substances to see how risky they are together.', 'https://tripsit.me/combo'),
    ResearchLink('Wikipedia: ${s.name}', 'Background, chemistry, pharmacology and legal history.', 'https://en.wikipedia.org/wiki/Special:Search?search=$name'),
  ];
}

/// The wider reading list for the Research page.
const researchHub = <(String, List<ResearchLink>)>[
  (
    'Look up a substance',
    [
      psychonautWikiIndex,
      ResearchLink('PsychonautWiki: Subjective Effect Index', 'Every effect described and illustrated, to learn what to expect and the words for it.', 'https://psychonautwiki.org/wiki/Subjective_Effect_Index'),
      ResearchLink('Erowid', 'The long-running library of drug vaults, dose charts, effects, legal status and experience reports.', 'https://www.erowid.org/'),
      ResearchLink('TripSit factsheets', 'Quick, readable summaries of hundreds of substances with dose and combination advice.', 'https://tripsit.me/factsheets'),
      ResearchLink('Drugs and Me', 'Plain explanations of how substances work in the body, plus an interactions table for mixing.', 'https://www.drugsand.me/'),
    ],
  ),
  (
    'Check before you mix',
    [
      ResearchLink('TripSit combination chart', 'The interaction chart this app uses for its warnings. Always check it directly before mixing.', 'https://tripsit.me/combo'),
      ResearchLink('TripSit wiki', 'Harm-reduction guides: dosing, safer-use basics, sitting, and what to do in an emergency.', 'https://wiki.tripsit.me/'),
    ],
  ),
  (
    'Testing and support',
    [
      ResearchLink('DanceSafe', 'Drug-checking kits and guidance on how to test, and what tests can and cannot tell you.', 'https://dancesafe.org/'),
      ResearchLink('Harm Reduction Coalition', 'Resources on safer use, overdose response and support services.', 'https://harmreduction.org/'),
      ResearchLink('Never Use Alone (US)', 'A hotline where someone stays on the line while you use, and sends help if you stop responding.', 'https://neverusealone.com/'),
    ],
  ),
];
