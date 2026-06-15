import "server-only";
import type { Locale } from "@/lib/site";

/* ------------------------------------------------------------------ *
 * rede content — German is the source of truth (rede-voice: lowercase,
 * young, honest). English mirrors it. Eigennamen (OpenAI, Whisper,
 * macOS, GGUF, ⌘) keep their casing.
 * ------------------------------------------------------------------ */

const de = {
  nav: {
    features: "was es kann",
    how: "so läufts",
    privacy: "privat",
    docs: "doku",
    download: "laden",
  },
  hero: {
    eyebrow: "macos menüleisten-app",
    titleLead: "einfach reden.",
    titleAccent: "der rest passiert.",
    sub: "rede sitzt in deiner menüleiste. hotkey drücken, sprechen, loslassen — und dein text steht da. sauberer formuliert, ruhiger im ton, oder einfach roh getippt. du entscheidest.",
    ctaPrimary: "rede laden",
    ctaSecondary: "auf github ansehen",
    smallprint:
      "für macOS. lokal mit Whisper + llama.cpp oder online mit deinem eigenen OpenAI-key. kein konto, kein hosted backend, keine telemetrie.",
    badgeLive: "ich hör zu",
  },
  modes: {
    heading: "ein modus pro aufgabe.",
    sub: "jeder modus hat seinen eigenen hotkey und sein eigenes modell — von rohem diktat bis zur sendefertigen mail. nimm nur, was du brauchst.",
    items: [
      {
        key: "diktat",
        accent: "var(--color-mode-diktat)",
        name: "Diktat",
        tagline: "sprache rein. text raus.",
        desc: "schnelle, präzise transkription über OpenAI. lange gedanken landen direkt als sauberer text.",
      },
      {
        key: "lokal",
        accent: "var(--color-mode-lokal)",
        name: "Diktat lokal",
        tagline: "nur lokal. kein server.",
        desc: "transkription on-device mit Whisper. kein audio verlässt deinen mac — für alles sensible.",
      },
      {
        key: "email",
        accent: "var(--color-mode-text)",
        name: "E-Mail",
        tagline: "diktiert, fertig formuliert.",
        desc: "sag grob, was rein soll — rede macht eine klar strukturierte, sendefertige mail draus, erkennt Sie/Du und nutzt den kontext aus dem feld.",
      },
      {
        key: "prompt",
        accent: "var(--color-mode-dampf)",
        name: "Prompt",
        tagline: "gesprochen, sauber geprompted.",
        desc: "diktier deine task — rede formt daraus einen präzisen prompt für KI-coding-agents wie Claude Code oder Codex. erfindet nichts dazu.",
      },
      {
        key: "social",
        accent: "var(--color-mode-emoji)",
        name: "Social",
        tagline: "text rein. emojis dazu.",
        desc: "dein gesprochener text wird zum social-post mit passenden emojis — dichte von wenig bis viel einstellbar.",
      },
    ],
  },
  how: {
    heading: "so läufts",
    sub: "drei schritte, dann gehört es zur muskelerinnerung.",
    steps: [
      {
        n: "01",
        title: "hotkey drücken",
        desc: "egal in welcher app — der globale kürzel startet rede sofort. halten oder umschalten, wie du magst.",
      },
      {
        n: "02",
        title: "einfach reden",
        desc: "die schwebende pille zeigt dir live, dass zugehört wird. lass los, wenn du fertig bist.",
      },
      {
        n: "03",
        title: "text ist da",
        desc: "rede schreibt direkt ins aktive feld oder legt den text in die zwischenablage. fertig.",
      },
    ],
  },
  privacy: {
    heading: "ehrlich, was wohin geht",
    sub: "datenschutz ist kein marketing-feature. hier die nüchterne wahrheit:",
    columns: [
      {
        key: "local",
        tone: "lime",
        label: "lokal",
        title: "bleibt auf deinem mac",
        points: [
          "lokale transkription läuft mit Whisper (CoreML) komplett on-device",
          "lokales umschreiben + embeddings über ein gebündeltes llama.cpp auf 127.0.0.1",
          "kein hosted rede-backend, kein konto, keine telemetrie",
          "temporäre audiodateien werden nach der verarbeitung gelöscht",
        ],
      },
      {
        key: "online",
        tone: "violet",
        label: "online",
        title: "geht direkt zu OpenAI",
        points: [
          "online-modi schicken audio und text direkt an OpenAI — mit deinem eigenen key",
          "der key liegt nur in der macOS-keychain, nie auf einem server von uns",
          "kein proxy, kein zwischenspeicher auf unserer seite",
          "für sensibles: nutz die lokalen modi oder prüf vorher, was du sendest",
        ],
      },
    ],
  },
  shots: {
    heading: "ein blick rein",
    sub: "echte screenshots, keine mockups.",
    items: [
      {
        src: "/screenshots/menubar.png",
        caption: "die menüleisten-pille im einsatz",
      },
      {
        src: "/screenshots/modes.png",
        caption: "modi konfigurieren — name, kürzel, modell",
      },
      {
        src: "/screenshots/local-models.png",
        caption: "lokale modelle an einem ort verwalten",
      },
    ],
  },
  download: {
    heading: "lass uns reden.",
    sub: "lade rede, gib ihm den hotkey deiner wahl und sprich los.",
    requirement:
      "für macOS · signiert & notarisiert · auto-update über Sparkle",
    cta: "rede laden",
    secondary: "quellcode auf github",
    note: "open source unter MIT-lizenz. experimentell — schau vor sensibler nutzung selbst drüber.",
  },
  footer: {
    tagline: "voice-first. lokal-first. ehrlich.",
    builtWith: "eine native macOS-menüleisten-app.",
    cols: {
      product: "produkt",
      resources: "ressourcen",
      legal: "rechtliches",
    },
    links: {
      features: "was es kann",
      download: "laden",
      docs: "doku",
      github: "github",
      changelog: "changelog",
      privacy: "datenschutz",
      imprint: "impressum",
    },
    rights: "kein konto. kein backend. nur dein mac und deine stimme.",
  },
  docs: {
    title: "doku",
    sub: "kurz und konkret. alles, was du fürs erste einrichten brauchst.",
    tocLabel: "themen",
    nav: {
      index: "übersicht",
      setup: "einrichten",
      hotkeys: "tastenkürzel",
      openai: "OpenAI-key",
      local: "lokale modelle",
    },
    backToDocs: "zurück zur doku",
    pages: {
      index: {
        title: "loslegen mit rede",
        intro:
          "rede ist eine menüleisten-app für macOS. du brauchst keinen account — nur die app, die nötigen rechte und entweder einen OpenAI-key oder lokale modelle. starte mit dem einrichten.",
        cards: [
          {
            to: "setup",
            title: "einrichten",
            desc: "installation, rechte und der erste durchlauf.",
          },
          {
            to: "hotkeys",
            title: "tastenkürzel",
            desc: "globale kürzel pro modus, halten vs. umschalten.",
          },
          {
            to: "openai",
            title: "OpenAI-key",
            desc: "warum ein eigener key, und wo du ihn herbekommst.",
          },
          {
            to: "local",
            title: "lokale modelle",
            desc: "Whisper + llama.cpp komplett offline nutzen.",
          },
        ],
      },
      setup: {
        title: "einrichten",
        blocks: [
          {
            h: "1 · installieren",
            p: "lade die .dmg, zieh rede in den programme-ordner und starte es. beim ersten start landet es als symbol in der menüleiste — kein dock-fenster.",
          },
          {
            h: "2 · rechte geben",
            p: "rede braucht das mikrofon (zum aufnehmen) und die bedienungshilfen (für globale hotkeys und das einfügen in andere apps). der onboarding-assistent führt dich da durch.",
          },
          {
            h: "3 · verarbeitung wählen",
            p: "entscheide dich pro modus für online (OpenAI) oder lokal (Whisper / llama.cpp). du kannst beides mischen — z. b. lokal diktieren, online umschreiben.",
          },
          {
            h: "4 · erster test",
            p: "der assistent hat einen sicheren test-schritt: sprich kurz rein, ohne dass irgendwo automatisch eingefügt wird. wenn der text erscheint, sitzt alles.",
          },
        ],
      },
      hotkeys: {
        title: "tastenkürzel",
        blocks: [
          {
            h: "ein kürzel pro modus",
            p: "jeder der fünf modi hat seinen eigenen globalen hotkey. du legst ihn im modi-tab über den recorder fest: feld antippen, kombination drücken, übernehmen.",
          },
          {
            h: "halten oder umschalten",
            p: "halten = aufnahme läuft, solange du die taste drückst. umschalten = einmal drücken startet, nochmal drücken stoppt. die entscheidung triffst du global im onboarding oder system-tab.",
          },
          {
            h: "abbrechen",
            p: "esc bricht eine laufende aufnahme jederzeit ab — es wird nichts transkribiert und nichts eingefügt.",
          },
        ],
      },
      openai: {
        title: "OpenAI-key",
        blocks: [
          {
            h: "warum dein eigener key",
            p: "rede hat kein hosted backend. die online-modi sprechen direkt mit OpenAI — abgerechnet über deinen eigenen key. ein ChatGPT-abo reicht dafür nicht, du brauchst einen platform-key.",
          },
          {
            h: "wo du ihn herbekommst",
            p: "auf platform.openai.com einloggen, unter „API keys“ einen neuen schlüssel erstellen und kopieren. in rede fügst du ihn im modelle-tab ein — er landet nur in der macOS-keychain.",
          },
          {
            h: "kosten",
            p: "du zahlst nutzungsbasiert direkt an OpenAI. transkription und umschreiben sind günstig pro nutzung, aber nicht kostenlos. die genauen preise stehen auf der OpenAI-preisseite.",
          },
        ],
      },
      local: {
        title: "lokale modelle",
        blocks: [
          {
            h: "transkription mit Whisper",
            p: "im modelle-tab lädst du ein Whisper-modell (CoreML). danach läuft die lokale transkription komplett on-device — kein audio verlässt den mac.",
          },
          {
            h: "umschreiben mit llama.cpp",
            p: "für lokales umschreiben und embeddings bringt rede einen llama.cpp-server mit, der nur auf 127.0.0.1 lauscht. das GGUF-modell wählst du ebenfalls im modelle-tab.",
          },
          {
            h: "alles an einem ort",
            p: "das fenster „lokale modelle“ verwaltet transkription, umschreiben und embedding gemeinsam: laden, neu laden, löschen — pro modelltyp identisch.",
          },
        ],
      },
    },
  },
  legal: {
    privacy: {
      title: "datenschutz",
      updated: "stand: juni 2026",
      intro:
        "rede ist eine lokale macOS-app ohne hosted backend. diese erklärung beschreibt, welche daten die app verarbeitet und wohin sie — wenn überhaupt — gehen.",
      sections: [
        {
          h: "keine erhebung durch uns",
          p: "wir betreiben keinen server für rede. die app sendet keine telemetrie, keine nutzungsdaten und keine absturzberichte an uns. es gibt kein konto und keine registrierung.",
        },
        {
          h: "lokale verarbeitung",
          p: "bei lokalen modi bleiben audio und text auf deinem mac. die transkription läuft mit Whisper on-device, umschreiben und embeddings über ein gebündeltes llama.cpp, das nur lokal (127.0.0.1) erreichbar ist. temporäre audiodateien werden nach der verarbeitung gelöscht.",
        },
        {
          h: "online-modi (OpenAI)",
          p: "wenn du einen online-modus nutzt, werden audio bzw. text direkt an OpenAI übermittelt und dort gemäß den bedingungen von OpenAI verarbeitet. die übertragung erfolgt mit deinem eigenen api-key. wir sind an dieser übertragung technisch nicht beteiligt. bitte beachte die datenschutzhinweise von OpenAI.",
        },
        {
          h: "schlüssel & einstellungen",
          p: "dein OpenAI-key wird ausschließlich in der macOS-keychain gespeichert. einstellungen und optionaler verlauf/memory liegen lokal in deinem benutzerverzeichnis und verlassen den mac nicht.",
        },
        {
          h: "diese website",
          p: "die website wird statisch ausgeliefert. der hosting-anbieter kann technisch notwendige server-logs (z. b. ip-adresse, zeitpunkt) verarbeiten. details dazu im impressum bzw. beim jeweiligen anbieter.",
        },
      ],
    },
    imprint: {
      title: "impressum",
      intro: "angaben gemäß § 5 DDG (digitale-dienste-gesetz).",
      sections: [
        {
          h: "anbieter",
          p: "[name / firma]\n[straße & hausnummer]\n[plz & ort]\n[land]",
        },
        { h: "kontakt", p: "e-mail: [deine-adresse@example.com]" },
        {
          h: "verantwortlich für den inhalt",
          p: "[name], anschrift wie oben.",
        },
        {
          h: "haftungsausschluss",
          p: "rede ist experimentelle open-source-software, bereitgestellt „wie besehen“ ohne gewähr. die nutzung erfolgt auf eigene verantwortung. für inhalte externer links wird keine haftung übernommen.",
        },
      ],
      placeholder:
        "platzhalter — bitte vor dem öffentlichen launch mit deinen echten angaben ersetzen.",
    },
  },
  meta: {
    title: "rede — einfach reden, der rest passiert",
    description:
      "rede ist eine native macOS-menüleisten-app fürs diktieren, transkribieren und umschreiben — lokal mit Whisper + llama.cpp oder online mit deinem eigenen OpenAI-key.",
  },
} as const;

const en = {
  nav: {
    features: "what it does",
    how: "how it works",
    privacy: "private",
    docs: "docs",
    download: "download",
  },
  hero: {
    eyebrow: "macos menu bar app",
    titleLead: "just talk.",
    titleAccent: "the rest just happens.",
    sub: "rede lives in your menu bar. hit a hotkey, talk, let go — and your text is there. cleaner, calmer, or just as you said it. your call.",
    ctaPrimary: "download rede",
    ctaSecondary: "view on github",
    smallprint:
      "for macOS. local with Whisper + llama.cpp, or online with your own OpenAI key. no account, no hosted backend, no telemetry.",
    badgeLive: "listening",
  },
  modes: {
    heading: "one mode per job.",
    sub: "each mode has its own hotkey and its own model — from raw dictation to a ready-to-send email. take only what you need.",
    items: [
      {
        key: "diktat",
        accent: "var(--color-mode-diktat)",
        name: "Dictate",
        tagline: "voice in. text out.",
        desc: "fast, precise transcription via OpenAI. long thoughts land straight as clean text.",
      },
      {
        key: "lokal",
        accent: "var(--color-mode-lokal)",
        name: "Dictate local",
        tagline: "local only. no server.",
        desc: "on-device transcription with Whisper. no audio leaves your mac — for anything sensitive.",
      },
      {
        key: "email",
        accent: "var(--color-mode-text)",
        name: "Email",
        tagline: "dictated, fully drafted.",
        desc: "say roughly what it should cover — rede turns it into a clearly structured, ready-to-send email, reads formal/informal and uses the field's context.",
      },
      {
        key: "prompt",
        accent: "var(--color-mode-dampf)",
        name: "Prompt",
        tagline: "spoken, cleanly prompted.",
        desc: "dictate your task — rede shapes it into a precise prompt for AI coding agents like Claude Code or Codex. invents nothing.",
      },
      {
        key: "social",
        accent: "var(--color-mode-emoji)",
        name: "Social",
        tagline: "text in. emoji on top.",
        desc: "your spoken text becomes a social post with fitting emoji — density adjustable from light to heavy.",
      },
    ],
  },
  how: {
    heading: "how it works",
    sub: "three steps, then it's muscle memory.",
    steps: [
      {
        n: "01",
        title: "press the hotkey",
        desc: "in any app — the global shortcut fires rede instantly. hold or toggle, whatever suits you.",
      },
      {
        n: "02",
        title: "just talk",
        desc: "the floating pill shows you it's listening, live. let go when you're done.",
      },
      {
        n: "03",
        title: "text is there",
        desc: "rede types straight into the active field or drops the text on your clipboard. done.",
      },
    ],
  },
  privacy: {
    heading: "honest about what goes where",
    sub: "privacy isn't a marketing feature. here's the plain truth:",
    columns: [
      {
        key: "local",
        tone: "lime",
        label: "local",
        title: "stays on your mac",
        points: [
          "local transcription runs fully on-device with Whisper (CoreML)",
          "local rewriting + embeddings via a bundled llama.cpp on 127.0.0.1",
          "no hosted rede backend, no account, no telemetry",
          "temporary audio files are deleted after processing",
        ],
      },
      {
        key: "online",
        tone: "violet",
        label: "online",
        title: "goes straight to OpenAI",
        points: [
          "online modes send audio and text directly to OpenAI — with your own key",
          "the key lives only in the macOS keychain, never on a server of ours",
          "no proxy, no caching on our side",
          "for sensitive work: use the local modes or review what you send first",
        ],
      },
    ],
  },
  shots: {
    heading: "a look inside",
    sub: "real screenshots, no mockups.",
    items: [
      {
        src: "/screenshots/menubar.png",
        caption: "the menu bar pill in action",
      },
      {
        src: "/screenshots/modes.png",
        caption: "configure modes — name, shortcut, model",
      },
      {
        src: "/screenshots/local-models.png",
        caption: "manage local models in one place",
      },
    ],
  },
  download: {
    heading: "let's talk.",
    sub: "download rede, give it the hotkey of your choice, and start speaking.",
    requirement: "for macOS · signed & notarized · auto-update via Sparkle",
    cta: "download rede",
    secondary: "source on github",
    note: "open source under the MIT license. experimental — review it yourself before sensitive use.",
  },
  footer: {
    tagline: "voice-first. local-first. honest.",
    builtWith: "a native macOS menu bar app.",
    cols: {
      product: "product",
      resources: "resources",
      legal: "legal",
    },
    links: {
      features: "what it does",
      download: "download",
      docs: "docs",
      github: "github",
      changelog: "changelog",
      privacy: "privacy",
      imprint: "imprint",
    },
    rights: "no account. no backend. just your mac and your voice.",
  },
  docs: {
    title: "docs",
    sub: "short and concrete. everything you need for the first setup.",
    tocLabel: "topics",
    nav: {
      index: "overview",
      setup: "setup",
      hotkeys: "hotkeys",
      openai: "OpenAI key",
      local: "local models",
    },
    backToDocs: "back to docs",
    pages: {
      index: {
        title: "getting started with rede",
        intro:
          "rede is a menu bar app for macOS. no account needed — just the app, the required permissions, and either an OpenAI key or local models. start with setup.",
        cards: [
          {
            to: "setup",
            title: "setup",
            desc: "install, permissions and the first run.",
          },
          {
            to: "hotkeys",
            title: "hotkeys",
            desc: "per-mode global shortcuts, hold vs. toggle.",
          },
          {
            to: "openai",
            title: "OpenAI key",
            desc: "why your own key, and where to get it.",
          },
          {
            to: "local",
            title: "local models",
            desc: "use Whisper + llama.cpp fully offline.",
          },
        ],
      },
      setup: {
        title: "setup",
        blocks: [
          {
            h: "1 · install",
            p: "download the .dmg, drag rede into your applications folder and launch it. on first start it appears as a menu bar icon — no dock window.",
          },
          {
            h: "2 · grant permissions",
            p: "rede needs the microphone (to record) and accessibility (for global hotkeys and pasting into other apps). the onboarding wizard walks you through it.",
          },
          {
            h: "3 · choose processing",
            p: "pick online (OpenAI) or local (Whisper / llama.cpp) per mode. you can mix both — e.g. dictate locally, rewrite online.",
          },
          {
            h: "4 · first test",
            p: "the wizard has a safe test step: speak briefly without anything being auto-pasted. if the text shows up, you're set.",
          },
        ],
      },
      hotkeys: {
        title: "hotkeys",
        blocks: [
          {
            h: "one shortcut per mode",
            p: "each of the five modes has its own global hotkey. set it in the modes tab via the recorder: tap the field, press the combo, apply.",
          },
          {
            h: "hold or toggle",
            p: "hold = recording runs while you press the key. toggle = press once to start, again to stop. you make this choice globally in onboarding or the system tab.",
          },
          {
            h: "cancel",
            p: "esc cancels a running recording at any time — nothing is transcribed and nothing is pasted.",
          },
        ],
      },
      openai: {
        title: "OpenAI key",
        blocks: [
          {
            h: "why your own key",
            p: "rede has no hosted backend. online modes talk to OpenAI directly — billed via your own key. a ChatGPT subscription isn't enough; you need a platform key.",
          },
          {
            h: "where to get it",
            p: "log in at platform.openai.com, create a new key under “API keys” and copy it. paste it into rede's models tab — it only ever lands in the macOS keychain.",
          },
          {
            h: "cost",
            p: "you pay usage-based directly to OpenAI. transcription and rewriting are cheap per use, but not free. exact prices are on the OpenAI pricing page.",
          },
        ],
      },
      local: {
        title: "local models",
        blocks: [
          {
            h: "transcription with Whisper",
            p: "in the models tab you download a Whisper model (CoreML). after that local transcription runs fully on-device — no audio leaves the mac.",
          },
          {
            h: "rewriting with llama.cpp",
            p: "for local rewriting and embeddings rede bundles a llama.cpp server that only listens on 127.0.0.1. you pick the GGUF model in the models tab too.",
          },
          {
            h: "all in one place",
            p: "the “local models” window manages transcription, rewriting and embedding together: load, reload, delete — identical per model type.",
          },
        ],
      },
    },
  },
  legal: {
    privacy: {
      title: "privacy",
      updated: "last updated: june 2026",
      intro:
        "rede is a local macOS app with no hosted backend. this notice describes what data the app processes and where it goes — if anywhere.",
      sections: [
        {
          h: "no collection by us",
          p: "we run no server for rede. the app sends no telemetry, usage data or crash reports to us. there is no account and no registration.",
        },
        {
          h: "local processing",
          p: "in local modes, audio and text stay on your mac. transcription runs on-device with Whisper, rewriting and embeddings via a bundled llama.cpp reachable only locally (127.0.0.1). temporary audio files are deleted after processing.",
        },
        {
          h: "online modes (OpenAI)",
          p: "when you use an online mode, audio or text is sent directly to OpenAI and processed there under OpenAI's terms. the transfer uses your own api key. we are not technically involved in this transfer. please review OpenAI's privacy information.",
        },
        {
          h: "key & settings",
          p: "your OpenAI key is stored solely in the macOS keychain. settings and optional history/memory live locally in your user directory and never leave the mac.",
        },
        {
          h: "this website",
          p: "the website is served statically. the hosting provider may process technically necessary server logs (e.g. ip address, timestamp). see the imprint or the respective provider for details.",
        },
      ],
    },
    imprint: {
      title: "imprint",
      intro: "information pursuant to § 5 DDG (german digital services act).",
      sections: [
        {
          h: "provider",
          p: "[name / company]\n[street & number]\n[zip & city]\n[country]",
        },
        { h: "contact", p: "email: [your-address@example.com]" },
        {
          h: "responsible for content",
          p: "[name], address as above.",
        },
        {
          h: "disclaimer",
          p: "rede is experimental open-source software, provided “as is” without warranty. use is at your own risk. no liability is assumed for the content of external links.",
        },
      ],
      placeholder:
        "placeholder — please replace with your real details before going public.",
    },
  },
  meta: {
    title: "rede — just talk, the rest just happens",
    description:
      "rede is a native macOS menu bar app for dictation, transcription and rewriting — local with Whisper + llama.cpp or online with your own OpenAI key.",
  },
} as const;

export type Dictionary = typeof de;

const dictionaries: Record<Locale, Dictionary> = {
  de,
  // structural mirror of `de`; cast keeps literal types aligned
  en: en as unknown as Dictionary,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale];
}
