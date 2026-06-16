import Foundation

/// High-frequency language words that should never become learned vocabulary. Memory vocabulary is
/// for distinctive names, product terms and domain language, not normal function words.
enum MemoryCommonWords {
  static let germanTopWords: Set<String> = normalizedSet([
    "ab", "aber", "alle", "allein", "allem", "allen", "aller", "alles", "als", "also",
    "am", "an", "andere", "anderem", "anderen", "anderer", "anderes", "auch", "auf", "aus",
    "bei", "beide", "beiden", "beim", "bin", "bis", "bist", "da", "dabei", "dadurch",
    "dafuer", "dagegen", "daher", "damit", "danach", "dann", "darauf", "daraus", "darin",
    "darueber", "darum", "das", "dass", "dein", "deine", "deinem", "deinen", "deiner",
    "deines", "dem", "den", "denn", "der", "des", "deshalb", "dessen", "deutsch", "dich",
    "die", "dies", "diese", "diesem", "diesen", "dieser", "dieses", "dir", "doch", "dort",
    "du", "durch", "eher", "ein", "eine", "einem", "einen", "einer", "eines", "einige",
    "einigem", "einigen", "einiger", "einiges", "einmal", "er", "es", "etwa", "etwas",
    "euch", "euer", "eure", "eurem", "euren", "eurer", "eures", "fuer", "ganz", "gar",
    "gegen", "gewesen", "gibt", "gut", "habe", "haben", "hat", "hatte", "hatten", "hier",
    "hin", "hinter", "ich", "ihm", "ihn", "ihnen", "ihr", "ihre", "ihrem", "ihren", "ihrer",
    "ihres", "im", "immer", "in", "indem", "ins", "ist", "ja", "jede", "jedem", "jeden",
    "jeder", "jedes", "jedoch", "jetzt", "kann", "kannst", "kein", "keine", "keinem",
    "keinen", "keiner", "keines", "koennen", "koennt", "konnte", "konnten", "kurz", "lang",
    "lassen", "leicht", "machen", "man", "manche", "manchem", "manchen", "mancher",
    "manches", "mehr", "mein", "meine", "meinem", "meinen", "meiner", "meines", "mich",
    "mir", "mit", "muss", "musst", "muessen", "musste", "mussten", "nach", "nachdem",
    "naemlich", "nah", "neben", "nein", "nicht", "nichts", "noch", "nun", "nur", "ob",
    "obwohl", "oder", "oft", "ohne", "sehr", "sein", "seine", "seinem", "seinen", "seiner",
    "seines", "seit", "sich", "sie", "sind", "so", "sobald", "solche", "solchem",
    "solchen", "solcher", "solches", "soll", "sollen", "sollte", "sollten", "sondern",
    "sonst", "spaeter", "ueber", "um", "und", "uns", "unser", "unsere", "unserem",
    "unseren", "unserer", "unseres", "unter", "viel", "viele", "vielem", "vielen", "vieler",
    "vieles", "vielleicht", "vom", "von", "vor", "waere", "waeren", "wann", "war", "waren",
    "warum", "was", "weil", "weiter", "welche", "welchem", "welchen", "welcher", "welches",
    "wem", "wen", "wenig", "wenn", "wer", "werde", "werden", "werdet", "weshalb", "wessen",
    "wie", "wieder", "wir", "wird", "wirklich", "wo", "wollen", "wollte", "wollten",
    "worden", "wurde", "wurden", "zu", "zuerst", "zum", "zur", "zwar", "zwischen",
  ])

  static let englishTopWords: Set<String> = normalizedSet([
    "a", "about", "above", "after", "again", "against", "ago", "all", "almost", "alone",
    "along", "already", "also", "although", "always", "am", "among", "an", "and", "another",
    "any", "anything", "are", "around", "as", "ask", "at", "away", "back", "be", "became",
    "because", "become", "been", "before", "began", "being", "below", "between", "big",
    "both", "but", "by", "call", "came", "can", "cannot", "case", "change", "child", "come",
    "consider", "could", "day", "did", "different", "do", "does", "done", "down", "during",
    "each", "early", "end", "enough", "even", "ever", "every", "example", "fact", "far",
    "few", "find", "first", "follow", "for", "form", "found", "from", "gave", "general",
    "get", "give", "go", "good", "got", "great", "group", "had", "hand", "hard", "has",
    "have", "he", "head", "help", "her", "here", "high", "him", "his", "home", "house",
    "how", "however", "i", "if", "in", "interest", "into", "is", "it", "its", "just", "keep",
    "kind", "know", "large", "last", "late", "lead", "left", "less", "let", "life", "like",
    "little", "long", "look", "made", "make", "man", "many", "may", "me", "mean", "might",
    "more", "most", "much", "must", "my", "need", "never", "new", "next", "no", "not",
    "nothing", "now", "of", "off", "often", "old", "on", "once", "one", "only", "open",
    "or", "order", "other", "our", "out", "over", "own", "part", "people", "person", "place",
    "plan", "possible", "present", "problem", "public", "put", "rather", "right", "said",
    "same", "saw", "say", "school", "see", "seem", "set", "she", "should", "show", "since",
    "small", "so", "some", "something", "state", "still", "such", "system", "take", "tell",
    "than", "that", "the", "their", "them", "then", "there", "these", "they", "thing", "think",
    "this", "those", "though", "three", "through", "time", "to", "today", "together", "too",
    "took", "toward", "try", "under", "until", "up", "us", "use", "used", "very", "want",
    "was", "way", "we", "well", "went", "were", "what", "when", "where", "whether", "which",
    "while", "who", "why", "will", "with", "within", "without", "word", "work", "world",
    "would", "write", "year", "yes", "yet", "you", "your",
  ])

  static let domainNoiseWords: Set<String> = normalizedSet([
    "antwort", "arbeit", "aufgabe", "bereich", "beispiel", "bitte", "danke", "datum",
    "dienstag", "donnerstag", "ende", "freitag", "frage", "heute", "jahr", "kunde", "kunden",
    "mail", "meeting", "mittwoch", "montag", "morgen", "nachricht", "projekt", "punkt",
    "sache", "termin", "text", "thema", "uhr", "woche", "zeit",
    "client", "customer", "date", "email", "message", "project", "question", "task", "text",
    "tomorrow",
  ])

  static let all = germanTopWords.union(englishTopWords).union(domainNoiseWords)

  static func contains(_ term: String) -> Bool {
    all.contains(normalized(term))
  }

  static func normalized(_ term: String) -> String {
    term
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "ä", with: "ae")
      .replacingOccurrences(of: "ö", with: "oe")
      .replacingOccurrences(of: "ü", with: "ue")
      .replacingOccurrences(of: "ß", with: "ss")
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
  }

  private static func normalizedSet(_ words: [String]) -> Set<String> {
    Set(words.map(normalized).filter { !$0.isEmpty })
  }
}
