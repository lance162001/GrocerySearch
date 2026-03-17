import 'package:flutter_front_end/models/grocery_models.dart';

List<Product> sortProductsByRecommendation(
  List<Product> products,
  String searchTerm,
) {
  final normalizedSearch = _normalize(searchTerm);
  if (normalizedSearch.isEmpty || products.length < 2) {
    return List<Product>.from(products);
  }

  final ranked = products
      .asMap()
      .entries
      .map(
        (entry) => _RankedProduct(
          product: entry.value,
          originalIndex: entry.key,
          vector: _buildSortVector(entry.value, normalizedSearch),
        ),
      )
      .toList(growable: false);

  ranked.sort((a, b) {
    final sharedLength =
        a.vector.length < b.vector.length ? a.vector.length : b.vector.length;
    for (var index = 0; index < sharedLength; index++) {
      final comparison = a.vector[index].compareTo(b.vector[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return a.originalIndex.compareTo(b.originalIndex);
  });

  return ranked.map((entry) => entry.product).toList(growable: false);
}

List<int> _buildSortVector(Product product, String normalizedSearch) {
  final normalizedName = _normalize(product.name);
  final matchIndex = normalizedName.indexOf(normalizedSearch);
  final exactMatchRank = normalizedName == normalizedSearch ? 0 : 1;
  final wordStartRank = _wordStartRank(normalizedName, matchIndex);
  final leadingWordCount = _leadingWordCount(normalizedName, matchIndex);
  final wordCount = _wordCount(normalizedName);
  final searchWordCount = _wordCount(normalizedSearch);
  final descriptorCount =
      wordCount > searchWordCount ? wordCount - searchWordCount : 0;

  final stapleProfile = _stapleProfileForSearch(normalizedSearch);
  if (stapleProfile != null) {
    final staplePriority = stapleProfile.priorityFor(normalizedName);
    return <int>[
      exactMatchRank,
      staplePriority.familyRank,
      staplePriority.variantRank,
      staplePriority.specialtyPenalty,
      wordStartRank,
      leadingWordCount,
      descriptorCount,
      wordCount,
    ];
  }

  return <int>[
    exactMatchRank,
    wordStartRank,
    leadingWordCount,
    _genericSpecialtyPenalty(normalizedName),
    descriptorCount,
    wordCount,
  ];
}

int _wordStartRank(String normalizedName, int matchIndex) {
  if (matchIndex < 0) {
    return 3;
  }
  if (matchIndex == 0) {
    return 0;
  }
  return normalizedName[matchIndex - 1] == ' ' ? 1 : 2;
}

int _leadingWordCount(String normalizedName, int matchIndex) {
  if (matchIndex <= 0) {
    return matchIndex == 0 ? 0 : 99;
  }
  return _wordCount(normalizedName.substring(0, matchIndex));
}

int _wordCount(String value) {
  if (value.isEmpty) {
    return 0;
  }
  return value.split(' ').where((token) => token.isNotEmpty).length;
}

int _genericSpecialtyPenalty(String normalizedName) {
  return _patternPenalty(normalizedName, _genericSpecialtyPatterns);
}

_StapleProfile? _stapleProfileForSearch(String normalizedSearch) {
  for (final profile in _stapleProfiles) {
    if (profile.handles(normalizedSearch)) {
      return profile;
    }
  }
  return null;
}

bool _matchesAny(String normalizedName, Iterable<RegExp> patterns) {
  for (final pattern in patterns) {
    if (pattern.hasMatch(normalizedName)) {
      return true;
    }
  }
  return false;
}

int _patternPenalty(String normalizedName, Iterable<RegExp> patterns) {
  final matches = <String>{};
  for (final pattern in patterns) {
    if (pattern.hasMatch(normalizedName)) {
      matches.add(pattern.pattern);
    }
  }
  return matches.length;
}

List<RegExp> _compilePatterns(List<String> sources) {
  return sources.map((source) => RegExp(source)).toList(growable: false);
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9%]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final List<RegExp> _genericSpecialtyPatterns = <RegExp>[
  RegExp(r'\borganic\b'),
  RegExp(r'\bprotein\b'),
  RegExp(r'\bgluten free\b|\bglutenfree\b'),
  RegExp(r'\blactose free\b|\blactosefree\b'),
  RegExp(r'\bflavored\b|\bflavour\b'),
  RegExp(r'\bunsweetened\b|\bsweetened\b'),
  RegExp(r'\bpremium\b|\bartisan\b|\bgourmet\b'),
  RegExp(r'\bketo\b|\bpaleo\b|\blow carb\b|\blowcarb\b'),
  RegExp(r'\bvegan\b|\bplant based\b|\bplantbased\b'),
  RegExp(r'\bdairy free\b|\bdairyfree\b'),
];

final List<_StapleProfile> _stapleProfiles = <_StapleProfile>[
  _StapleProfile(
    aliases: <String>{'milk'},
    variantPatterns: _compilePatterns(<String>[
      r'\bwhole\b|\bvitamin d\b|\bfull cream\b|\bfresh\b|\bpasteurized\b',
      r'\b2%\b|\b2 percent\b|\breduced fat\b|\breducedfat\b',
      r'\b1%\b|\b1 percent\b|\blow fat\b|\blowfat\b',
      r'\bskim\b|\bnonfat\b|\bnon fat\b|\bfat free\b|\bfatfree\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\borganic\b|\blactose free\b|\blactosefree\b|\bultra filtered\b|\bultrafiltered\b|\bprotein\b|\ba2\b|\bgrass fed\b|\bgrassfed\b|\bpasture\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bchocolate\b|\bvanilla\b|\bstrawberry\b|\bbanana\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\balmond\b|\boat\b|\bsoy\b|\bcoconut\b|\bcashew\b|\bmacadamia\b|\brice\b|\bhemp\b|\bpea\b|\bflax\b|\bwalnut\b|\bgoat\b|\bsheep\b|\bcamel\b|\bbuffalo\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bcondensed\b|\bevaporated\b|\bpowder\b|\bpowdered\b|\bdry\b|\bformula\b|\binfant\b|\btoddler\b|\bcreamer\b|\bbuttermilk\b|\bkefir\b|\bshake\b|\bsmoothie\b|\bmalt\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'egg', 'eggs'},
    variantPatterns: _compilePatterns(<String>[
      r'\blarge\b|\bgrade a\b|\bfresh\b|\bconventional\b',
      r'\bextra large\b|\bx large\b',
      r'\bjumbo\b',
      r'\bmedium\b',
      r'\bbrown\b',
      r'\bwhites\b|\bliquid\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bcage free\b|\bcagefree\b|\bfree range\b|\bfreerange\b|\bpasture raised\b|\bpastureraised\b|\bomega 3\b|\bomega3\b|\bvegetarian fed\b|\bfarm fresh\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bplant based\b|\bplantbased\b|\bvegan\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bwhites\b|\bliquid\b|\bsubstitute\b|\bbeaters\b|\bbites\b|\bsandwich\b|\bsalad\b|\bhard boiled\b|\bhardboiled\b|\bdeviled\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'bread'},
    variantPatterns: _compilePatterns(<String>[
      r'\bwhite\b|\bsandwich\b|\bclassic\b|\bplain\b|\bfresh\b|\bsliced\b',
      r'\bwhole wheat\b|\bwholegrain\b|\bwhole grain\b|\bwheat\b',
      r'\bsourdough\b',
      r'\bmultigrain\b|\bmultiseed\b',
      r'\brye\b',
      r'\bbrioche\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bartisan\b|\bbakery\b|\brustic\b|\bseeded\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bgarlic\b|\bcinnamon\b|\bbanana\b|\bpumpkin\b|\bcheese\b|\bherb\b|\braisin\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bgluten free\b|\bglutenfree\b|\bketo\b|\bcauliflower\b|\bcloud\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bbreadcrumbs\b|\bbread crumbs\b|\bcroutons\b|\bbreadsticks\b|\bstuffing\b|\bbuns\b|\brolls\b|\bbagels\b|\bnaan\b|\btortilla\b|\bpita\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'rice'},
    variantPatterns: _compilePatterns(<String>[
      r'\bwhite\b|\blong grain\b|\benriched\b',
      r'\bjasmine\b',
      r'\bbasmati\b',
      r'\bbrown\b',
      r'\bwild\b',
      r'\barborio\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bsprouted\b|\bgerminated\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bseasoned\b|\bpilaf\b|\bspanish\b|\bcilantro lime\b|\bfried rice\b|\bsaffron\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bcauliflower\b|\bbroccoli\b|\bquinoa\b|\blentil\b|\bchickpea\b|\bkonjac\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bcakes\b|\bpudding\b|\bcereal\b|\bready\b|\bmicrowave\b|\bpacket\b|\bcup\b|\bbowl\b|\bnoodles\b|\bramen\b|\bmilk\b|\bcrackers\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'pasta'},
    variantPatterns: _compilePatterns(<String>[
      r'\bspaghetti\b|\bdry\b|\bsemolina\b|\bdurum\b',
      r'\bpenne\b',
      r'\bmacaroni\b|\belbow\b',
      r'\brotini\b',
      r'\blinguine\b',
      r'\bfettuccine\b',
      r'\bshells\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bbronze cut\b|\bimported\b|\bartisan\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bspinach\b|\btomato\b|\bbasil\b|\bgarlic\b|\bherb\b|\btruffle\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bchickpea\b|\blentil\b|\bquinoa\b|\bcauliflower\b|\bzucchini\b|\bhearts of palm\b|\bgluten free\b|\bglutenfree\b|\brice\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bravioli\b|\btortellini\b|\bgnocchi\b|\blasagna\b|\bmac and cheese\b|\bmacaroni and cheese\b|\bramen\b|\bcup\b|\bbowl\b|\bmeal\b|\bdinner\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'flour'},
    variantPatterns: _compilePatterns(<String>[
      r'\ball purpose\b|\bplain flour\b',
      r'\bbread flour\b',
      r'\bwhole wheat\b|\bwholemeal\b',
      r'\bself rising\b|\bself raising\b',
      r'\bcake\b|\bpastry\b',
      r'\bsemolina\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bunbleached\b|\bstone ground\b|\bheirloom\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\balmond\b|\bcoconut\b|\bgluten free\b|\bglutenfree\b|\boat\b|\brice\b|\bcassava\b|\btapioca\b|\bchickpea\b|\bspelt\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bpancake mix\b|\bbiscuit mix\b|\bwaffle mix\b|\bbaking mix\b|\bcornbread mix\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'sugar'},
    variantPatterns: _compilePatterns(<String>[
      r'\bgranulated\b|\bwhite sugar\b|\bcane sugar\b',
      r'\blight brown\b',
      r'\bdark brown\b',
      r'\bcaster\b|\bsuperfine\b',
      r'\bbrown sugar\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\braw\b|\bturbinado\b|\bdemerara\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bvanilla\b|\bcinnamon\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bpowdered\b|\bconfectioners\b|\bicing\b|\bcubes\b|\bsyrup\b|\bmonk fruit\b|\bstevia\b|\berythritol\b|\bcoconut sugar\b|\bagave\b|\ballulose\b|\bxylitol\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'salt'},
    variantPatterns: _compilePatterns(<String>[
      r'\btable\b|\biodized\b|\bfine\b',
      r'\bkosher\b',
      r'\bsea\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bhimalayan\b|\bpink\b|\bfleur de sel\b|\bcoarse\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bgarlic\b|\bonion\b|\bsmoked\b|\bseasoned\b|\bcelery\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bsubstitute\b|\bsodium free\b|\blite\b|\blow sodium\b|\blowsodium\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'butter'},
    variantPatterns: _compilePatterns(<String>[
      r'\bsalted\b|\bfresh\b|\bcreamery\b',
      r'\bunsalted\b',
      r'\bsweet cream\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bcultured\b|\beuropean\b|\bgrass fed\b|\bgrassfed\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bgarlic\b|\bhoney\b|\bcinnamon\b|\bherb\b|\bmaple\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bplant\b|\bvegan\b|\bdairy free\b|\bdairyfree\b|\bmargarine\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bghee\b|\bclarified\b|\bwhipped\b|\bspray\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'cheese'},
    variantPatterns: _compilePatterns(<String>[
      r'\bcheddar\b',
      r'\bmozzarella\b',
      r'\bmonterey jack\b|\bjack\b',
      r'\bswiss\b',
      r'\bprovolone\b',
      r'\bcolby jack\b|\bcolby\b',
      r'\bamerican\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\baged\b|\breserve\b|\bartisanal\b|\bcave aged\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bpepper jack\b|\bsmoked\b|\bgarlic\b|\bherb\b|\bchipotle\b|\bjalapeno\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bvegan\b|\bplant based\b|\bplantbased\b|\bdairy free\b|\bdairyfree\b|\bnut based\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bdip\b|\bsauce\b|\bsnack\b|\bstring\b|\bpopcorn\b|\bpuff\b|\bspread\b|\bcream cheese\b|\bcottage cheese\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'yogurt', 'yoghurt'},
    variantPatterns: _compilePatterns(<String>[
      r'\bplain\b',
      r'\bvanilla\b',
      r'\bgreek\b',
      r'\bwhole milk\b',
      r'\blow fat\b|\blowfat\b|\blight\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bprobiotic\b|\bskyr\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bstrawberry\b|\bblueberry\b|\bpeach\b|\bcherry\b|\bhoney\b|\bmixed berry\b',
    ]),
    alternativePatterns: _compilePatterns(<String>[
      r'\bdairy free\b|\bdairyfree\b|\balmond\b|\bcoconut\b|\boat\b|\bsoy\b|\bcashew\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bdrink\b|\bsmoothie\b|\btube\b|\bfrozen\b|\bpops\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'oil', 'cooking oil'},
    variantPatterns: _compilePatterns(<String>[
      r'\bvegetable\b',
      r'\bcanola\b',
      r'\bolive\b',
      r'\bavocado\b',
      r'\bcoconut\b',
      r'\bsesame\b',
      r'\bpeanut\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bcold pressed\b|\bexpeller\b|\bunrefined\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bgarlic\b|\bchili\b|\btruffle\b|\bherb\b|\blemon\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bspray\b|\bdressing\b|\bmarinade\b|\bshortening\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'olive oil'},
    variantPatterns: _compilePatterns(<String>[
      r'\bextra virgin\b',
      r'\bvirgin\b',
      r'\bpure\b',
      r'\blight\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\bcold pressed\b|\bunfiltered\b',
    ]),
    flavorPatterns: _compilePatterns(<String>[
      r'\bgarlic\b|\bchili\b|\blemon\b|\bbasil\b|\brosemary\b|\btruffle\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bspray\b|\bdressing\b|\bmarinade\b',
    ]),
  ),
  _StapleProfile(
    aliases: <String>{'lime', 'limes'},
    variantPatterns: _compilePatterns(<String>[
      // Standard grocery-store lime (Persian/regular) — includes plain size and
      // freshness descriptors so "Large Fresh Limes" is treated as the staple
      // rather than a specialty variant when it is the only lime a store carries.
      r'\bpersian\b|\bfresh\b|\blarge\b|\bsmall\b|\bseedless\b',
      r'\bkey\b|\bmexican\b',
      r'\bkaffir\b|\bmakrut\b',
    ]),
    specialtyPatterns: _compilePatterns(<String>[
      r'\borganic\b',
    ]),
    otherFormPatterns: _compilePatterns(<String>[
      r'\bjuice\b|\bzest\b|\bextract\b|\bpickled\b|\bpreserved\b|\bdried\b|\bpowder\b',
    ]),
  ),
];

class _RankedProduct {
  const _RankedProduct({
    required this.product,
    required this.originalIndex,
    required this.vector,
  });

  final Product product;
  final int originalIndex;
  final List<int> vector;
}

class _StapleProfile {
  _StapleProfile({
    required this.aliases,
    required this.variantPatterns,
    this.specialtyPatterns = const <RegExp>[],
    this.flavorPatterns = const <RegExp>[],
    this.alternativePatterns = const <RegExp>[],
    this.otherFormPatterns = const <RegExp>[],
  });

  final Set<String> aliases;
  final List<RegExp> variantPatterns;
  final List<RegExp> specialtyPatterns;
  final List<RegExp> flavorPatterns;
  final List<RegExp> alternativePatterns;
  final List<RegExp> otherFormPatterns;

  bool handles(String normalizedSearch) {
    return aliases.contains(normalizedSearch);
  }

  _StaplePriority priorityFor(String normalizedName) {
    return _StaplePriority(
      familyRank: _familyRank(normalizedName),
      variantRank: _variantRank(normalizedName),
      specialtyPenalty: _patternPenalty(
        normalizedName,
        <RegExp>[
          ..._genericSpecialtyPatterns,
          ...specialtyPatterns,
          ...flavorPatterns,
          ...alternativePatterns,
          ...otherFormPatterns,
        ],
      ),
    );
  }

  int _familyRank(String normalizedName) {
    if (_matchesAny(normalizedName, otherFormPatterns)) {
      return 4;
    }
    if (_matchesAny(normalizedName, alternativePatterns)) {
      return 3;
    }
    if (_matchesAny(normalizedName, flavorPatterns)) {
      return 2;
    }
    if (_matchesAny(normalizedName, specialtyPatterns)) {
      return 1;
    }
    return 0;
  }

  int _variantRank(String normalizedName) {
    for (var index = 0; index < variantPatterns.length; index++) {
      if (variantPatterns[index].hasMatch(normalizedName)) {
        return index;
      }
    }
    return variantPatterns.length;
  }
}

class _StaplePriority {
  const _StaplePriority({
    required this.familyRank,
    required this.variantRank,
    required this.specialtyPenalty,
  });

  final int familyRank;
  final int variantRank;
  final int specialtyPenalty;
}
