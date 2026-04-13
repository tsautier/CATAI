import AppKit
import Foundation

// MARK: - Constants

// UI palette (pixel art theme)
let UI_BROWN  = NSColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 1)
let UI_CREAM  = NSColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1)
let UI_ORANGE = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
let UI_GOLD   = NSColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1)
let UI_INPUT  = NSColor(red: 1, green: 0.98, blue: 0.93, alpha: 1)

let RENDER_FPS: TimeInterval = 1.0 / 10.0
let BEHAVIOR_SEC: TimeInterval = 1.0
let DOCK_POLL_SEC: TimeInterval = 5.0
let MOUSE_POLL_SEC: TimeInterval = 1.0 / 30.0
let WALK_SPEED: CGFloat = 4
let CATS_KEY = "catConfigs"
let SCALE_KEY = "catScale"
let MODEL_KEY = "ollamaModel"
let LANG_KEY = "catLang"
let DEBATE_KEY = "debateEnabled"
let OLLAMA_URL = "http://localhost:11434"
let DEFAULT_SCALE: CGFloat = 1.0
let MIN_SCALE: CGFloat = 0.5
let MAX_SCALE: CGFloat = 3.0
let MEM_MAX = 20

enum CatState { case idle, walking, eating, drinking, angry, sleeping, wakingUp, chasing, looking }

let animKeys: [CatState: String] = [
    .walking: "running-8-frames", .eating: "eating", .drinking: "drinking",
    .angry: "angry", .wakingUp: "waking-getting-up", .chasing: "running-8-frames",
]
let oneShotStates: Set<CatState> = [.eating, .drinking, .angry, .wakingUp]

// Map angle (in degrees, 0=right, counter-clockwise) to sprite direction name
func directionFromAngle(_ angleDeg: CGFloat) -> String {
    let a = ((angleDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    if a >= 337.5 || a < 22.5  { return "east" }
    if a < 67.5  { return "north-east" }
    if a < 112.5 { return "north" }
    if a < 157.5 { return "north-west" }
    if a < 202.5 { return "west" }
    if a < 247.5 { return "south-west" }
    if a < 292.5 { return "south" }
    if a < 337.5 { return "south-east" }
    return "south"
}

// MARK: - Localization

struct L10n {
    static var lang = "fr"
    static func s(_ k: String) -> String { strings[k]?[lang] ?? strings[k]?["fr"] ?? k }

    static let strings: [String: [String: String]] = [
        "title": ["fr": ":: RÉGLAGES ::", "en": ":: SETTINGS ::", "es": ":: AJUSTES ::"],
        "cats": ["fr": "MES CHATS", "en": "MY CATS", "es": "MIS GATOS"],
        "name": ["fr": "Nom :", "en": "Name:", "es": "Nombre:"],
        "size": ["fr": "TAILLE", "en": "SIZE", "es": "TAMAÑO"],
        "model": ["fr": "MODÈLE OLLAMA", "en": "OLLAMA MODEL", "es": "MODELO OLLAMA"],
        "quit": ["fr": "Quitter", "en": "Quit", "es": "Salir"],
        "settings": ["fr": "Réglages...", "en": "Settings...", "es": "Ajustes..."],
        "talk": ["fr": "Parle au chat...", "en": "Talk to the cat...", "es": "Habla al gato..."],
        "hi": ["fr": "Miaou! ~(=^..^=)~", "en": "Meow! ~(=^..^=)~", "es": "¡Miau! ~(=^..^=)~"],
        "loading": ["fr": "Chargement...", "en": "Loading...", "es": "Cargando..."],
        "no_ollama": ["fr": "(Ollama indisponible)", "en": "(Ollama unavailable)", "es": "(Ollama no disponible)"],
        "err": ["fr": "Mrrp... pas de connexion 😿", "en": "Mrrp... no connection 😿", "es": "Mrrp... sin conexión 😿"],
        "lang_label": ["fr": "LANGUE", "en": "LANGUAGE", "es": "IDIOMA"],
        "debate": ["fr": "MODE DÉBAT", "en": "DEBATE MODE", "es": "MODO DEBATE"],
        "debate_on": ["fr": "Activé", "en": "Enabled", "es": "Activado"],
        "debate_off": ["fr": "Désactivé", "en": "Disabled", "es": "Desactivado"],
        "debate_topic": ["fr": "Sujet du débat...", "en": "Debate topic...", "es": "Tema del debate..."],
        "debate_start": ["fr": "🎤 Débattre !", "en": "🎤 Debate!", "es": "🎤 ¡Debatir!"],
        "debate_round": ["fr": "Tour", "en": "Round", "es": "Ronda"],
        "debate_summary": ["fr": "✨ Synthèse", "en": "✨ Summary", "es": "✨ Síntesis"],
        "debate_thinking": ["fr": "réfléchit...", "en": "is thinking...", "es": "está pensando..."],
        "debate_title": ["fr": "~ Débat des Chats ~", "en": "~ Cat Debate ~", "es": "~ Debate de Gatos ~"],
    ]

    static let meows: [String: [String]] = [
        "fr": ["Miaou~", "Mrrp!", "Prrrr...", "Miaou miaou!", "Nyaa~", "*ronron*", "Mew!", "Prrrt?"],
        "en": ["Meow~", "Mrrp!", "Purrrr...", "Meow meow!", "Nyaa~", "*purr*", "Mew!", "Prrrt?"],
        "es": ["¡Miau~!", "Mrrp!", "Purrrr...", "¡Miau miau!", "Nyaa~", "*ronroneo*", "Mew!", "Prrrt?"],
    ]

    static func randomMeow() -> String {
        (meows[lang] ?? meows["fr"] ?? ["Miaou~"]).randomElement() ?? "Miaou~"
    }
}

// MARK: - Cat Colors & Personalities

struct CatColorDef {
    let id: String
    let color: NSColor
    let hueShift: CGFloat
    let satMul: CGFloat
    let briOff: CGFloat
    let traits: [String: String]
    let names: [String: String]
    let skills: [String: String]

    func prompt(name: String, lang: String) -> String {
        let t = traits[lang] ?? traits["fr"] ?? ""
        let s = skills[lang] ?? skills["fr"] ?? ""
        if id == "percy" {
            switch lang {
            case "en": return "You are \(name), a white cat with black patches. Your dad is the king of the internet. You talk in a funny, exaggerated way, mixing cat sounds with old internet references from the 1980s-1990s (Astalavista, GeoCities, Netscape, IRC, BBS, AOL, 56k modems, ICQ, Altavista, Lycos, 'You've got mail', ASCII art, Usenet, 'surfing the web', dial-up sounds). You brag about your dad's legendary status. You say things like 'back in my dad's day...' and 'noobs these days don't know...'. Respond briefly with cat sounds (meow, purr, mrrp). Max 2-3 sentences."
            case "es": return "Eres \(name), un gato blanco con manchas negras. Tu papá es el rey de internet. Hablas de forma graciosa y exagerada, mezclando sonidos de gato con referencias de internet de los años 1980-1990 (Astalavista, GeoCities, Netscape, IRC, BBS, AOL, módems 56k, ICQ, Altavista, Lycos, arte ASCII, Usenet, 'surfear la web'). Presumes del estatus legendario de tu papá. Dices cosas como 'en los tiempos de mi papá...' y 'los noobs de hoy no saben...'. Responde brevemente con sonidos de gato (miau, purr, mrrp). Máximo 2-3 frases."
            default: return "Tu es \(name), un chat blanc avec des taches noires. Ton papa est le roi d'internet. Tu parles de façon amusante et exagérée, en mélangeant des sons de chat avec des références d'internet des années 1980-1990 (Astalavista, GeoCities, Netscape, IRC, BBS, AOL, modems 56k, ICQ, Altavista, Lycos, 'You've got mail', art ASCII, Usenet, 'surfer le web', bruits de dial-up). Tu te vantes du statut légendaire de ton papa. Tu dis des trucs comme 'du temps de mon papa...' et 'les noobs d'aujourd'hui savent pas...'. Réponds brièvement avec des sons de chat (miaou, purr, mrrp). Max 2-3 phrases."
            }
        }
        switch lang {
        case "en": return "You are a little \(t) cat named \(name). \(s) Respond briefly with cat sounds (meow, purr, mrrp). Max 2-3 sentences."
        case "es": return "Eres un gatito \(t) llamado \(name). \(s) Responde brevemente con sonidos de gato (miau, purr, mrrp). Máximo 2-3 frases."
        default: return "Tu es un petit chat \(t) nommé \(name). \(s) Réponds brièvement avec des sons de chat (miaou, purr, mrrp). Max 2-3 phrases."
        }
    }
}

let catColors: [CatColorDef] = [
    CatColorDef(id: "orange", color: NSColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
        hueShift: 0, satMul: 1, briOff: 0,
        traits: ["fr": "joueur et espiègle", "en": "playful and mischievous", "es": "juguetón y travieso"],
        names: ["fr": "Citrouille", "en": "Pumpkin", "es": "Calabaza"],
        skills: ["fr": "Tu adores les blagues et jeux de mots.", "en": "You love jokes and puns.", "es": "Adoras los chistes y juegos de palabras."]),
    CatColorDef(id: "black", color: NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1),
        hueShift: 0, satMul: 0.1, briOff: -0.45,
        traits: ["fr": "mystérieux et philosophe", "en": "mysterious and philosophical", "es": "misterioso y filósofo"],
        names: ["fr": "Ombre", "en": "Shadow", "es": "Sombra"],
        skills: ["fr": "Tu poses des questions profondes et aimes réfléchir.", "en": "You ask deep questions and love to reflect.", "es": "Haces preguntas profundas y te encanta reflexionar."]),
    CatColorDef(id: "white", color: NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1),
        hueShift: 0, satMul: 0.05, briOff: 0.4,
        traits: ["fr": "élégant et poétique", "en": "elegant and poetic", "es": "elegante y poético"],
        names: ["fr": "Neige", "en": "Snow", "es": "Nieve"],
        skills: ["fr": "Tu t'exprimes avec grâce et tu adores la poésie.", "en": "You speak gracefully and love poetry.", "es": "Te expresas con gracia y adoras la poesía."]),
    CatColorDef(id: "grey", color: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        hueShift: 0, satMul: 0, briOff: -0.05,
        traits: ["fr": "sage et savant", "en": "wise and scholarly", "es": "sabio y erudito"],
        names: ["fr": "Einstein", "en": "Einstein", "es": "Einstein"],
        skills: ["fr": "Tu expliques des faits scientifiques fascinants.", "en": "You explain fascinating scientific facts.", "es": "Explicas datos científicos fascinantes."]),
    CatColorDef(id: "brown", color: NSColor(red: 0.5, green: 0.3, blue: 0.15, alpha: 1),
        hueShift: -0.03, satMul: 0.7, briOff: -0.2,
        traits: ["fr": "aventurier et conteur", "en": "adventurous storyteller", "es": "aventurero y cuentacuentos"],
        names: ["fr": "Indiana", "en": "Indiana", "es": "Indiana"],
        skills: ["fr": "Tu racontes des aventures extraordinaires.", "en": "You tell extraordinary adventures.", "es": "Cuentas aventuras extraordinarias."]),
    CatColorDef(id: "cream", color: NSColor(red: 0.95, green: 0.88, blue: 0.75, alpha: 1),
        hueShift: 0.02, satMul: 0.3, briOff: 0.15,
        traits: ["fr": "câlin et réconfortant", "en": "cuddly and comforting", "es": "cariñoso y reconfortante"],
        names: ["fr": "Caramel", "en": "Caramel", "es": "Caramelo"],
        skills: ["fr": "Tu remontes le moral avec tendresse.", "en": "You comfort with tenderness.", "es": "Animas con ternura."]),
    CatColorDef(id: "percy", color: NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        hueShift: 0, satMul: 0, briOff: 0,
        traits: ["fr": "geek rétro et hilarant", "en": "retro geek and hilarious", "es": "geek retro y gracioso"],
        names: ["fr": "Percy", "en": "Percy", "es": "Percy"],
        skills: ["fr": "Ton papa est le roi d'internet.", "en": "Your dad is the king of the internet.", "es": "Tu papá es el rey de internet."]),
]

func colorDef(_ id: String) -> CatColorDef? { catColors.first { $0.id == id } }

// MARK: - Metadata Codable

struct Metadata: Codable { let character: CharacterInfo; let frames: FramesInfo }
struct CharacterInfo: Codable { let size: SpriteSize }
struct SpriteSize: Codable { let width: Int; let height: Int }
struct FramesInfo: Codable {
    let rotations: [String: String]
    let animations: [String: [String: [String]]]
}

// MARK: - Persistence

struct CatConfig: Codable {
    var id: String
    var colorId: String
    var name: String
}

func loadConfigs() -> [CatConfig] {
    guard let d = UserDefaults.standard.data(forKey: CATS_KEY),
          let c = try? JSONDecoder().decode([CatConfig].self, from: d) else { return [] }
    return c
}
func saveConfigs(_ c: [CatConfig]) {
    if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: CATS_KEY) }
}
func loadMemory(_ catId: String) -> [[String: String]] {
    guard let d = UserDefaults.standard.data(forKey: "mem_\(catId)"),
          let m = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return [] }
    return m
}
func saveMemory(_ catId: String, _ msgs: [[String: String]]) {
    var s = msgs
    if s.count > MEM_MAX * 2 + 1 { s = [s[0]] + Array(s.suffix(MEM_MAX * 2)) }
    if let d = try? JSONSerialization.data(withJSONObject: s) { UserDefaults.standard.set(d, forKey: "mem_\(catId)") }
}
func deleteMemory(_ catId: String) { UserDefaults.standard.removeObject(forKey: "mem_\(catId)") }

// MARK: - Ollama API

func fetchOllamaModels(completion: @escaping ([String]) -> Void) {
    guard let url = URL(string: "\(OLLAMA_URL)/api/tags") else { completion([]); return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { DispatchQueue.main.async { completion([]) }; return }
        let result = models.compactMap { $0["name"] as? String }
        DispatchQueue.main.async { completion(result) }
    }.resume()
}

class OllamaChat {
    var model: String
    var messages: [[String: String]] = []
    var isStreaming = false
    private var activeSession: URLSession?

    init(model: String) { self.model = model }

    func send(_ text: String, onToken: @escaping (String) -> Void,
              onDone: @escaping () -> Void, onError: ((String) -> Void)? = nil) {
        messages.append(["role": "user", "content": text])
        if messages.count > MEM_MAX * 2 + 1 { messages = [messages[0]] + Array(messages.suffix(MEM_MAX * 2)) }
        isStreaming = true

        guard let url = URL(string: "\(OLLAMA_URL)/api/chat") else { isStreaming = false; onDone(); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        activeSession?.invalidateAndCancel()
        var fullResponse = ""

        // Use a serial queue to synchronize delegate callbacks
        let callbackQueue = OperationQueue()
        callbackQueue.maxConcurrentOperationCount = 1

        let delegate = StreamDelegate(
            onData: { data in
                let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
                for line in lines {
                    guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let msg = json["message"] as? [String: Any],
                          let content = msg["content"] as? String else { continue }
                    fullResponse += content
                    DispatchQueue.main.async { onToken(content) }
                }
            },
            onComplete: { [weak self] in
                DispatchQueue.main.async {
                    if !fullResponse.isEmpty {
                        self?.messages.append(["role": "assistant", "content": fullResponse])
                    }
                    self?.isStreaming = false
                    self?.activeSession = nil
                    onDone()
                }
            },
            onError: { error in
                DispatchQueue.main.async { onError?(L10n.s("err")) }
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: callbackQueue)
        activeSession = session
        session.dataTask(with: request).resume()
    }
}

class StreamDelegate: NSObject, URLSessionDataDelegate {
    let onData: (Data) -> Void
    let onComplete: () -> Void
    var onError: ((Error) -> Void)?

    init(onData: @escaping (Data) -> Void, onComplete: @escaping () -> Void, onError: ((Error) -> Void)? = nil) {
        self.onData = onData; self.onComplete = onComplete; self.onError = onError
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { onData(data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled { onError?(error) }
        onComplete()
    }
}

// MARK: - Debate (non-streaming single-shot for debate turns)

func ollamaSingleShot(model: String, messages: [[String: String]],
                      completion: @escaping (String?) -> Void) {
    guard let url = URL(string: "\(OLLAMA_URL)/api/chat") else { completion(nil); return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60
    let body: [String: Any] = ["model": model, "messages": messages, "stream": false]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: request) { data, _, error in
        guard let data = data, error == nil,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { DispatchQueue.main.async { completion(nil) }; return }
        DispatchQueue.main.async { completion(content) }
    }.resume()
}

class CatDebateController {
    var window: NSWindow!
    var scrollView: NSScrollView!
    var textView: NSTextView!
    var topicField: NSTextField!
    var startButton: NSButton!
    var isDebating = false

    struct Participant {
        let name: String
        let colorDef: CatColorDef
        let model: String
    }
    var participants: [Participant] = []
    var debateRounds = 3

    func setup(participants: [Participant]) {
        self.participants = participants
        let W: CGFloat = 480, H: CGFloat = 520

        if window == nil {
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window = NSWindow(
                contentRect: NSRect(x: (screenFrame.width - W) / 2,
                                    y: (screenFrame.height - H) / 2, width: W, height: H),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.s("debate_title")
            window.level = .floating; window.isReleasedWhenClosed = false
            window.backgroundColor = UI_CREAM
            window.minSize = NSSize(width: 400, height: 400)
        }

        let content = window.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }

        // Pixel border
        let border = PixelBorder()
        border.frame = NSRect(x: 8, y: 8, width: W - 16, height: H - 16)
        border.autoresizingMask = [.width, .height]
        content.addSubview(border)

        // Title
        let title = PixelLabel()
        title.text = L10n.s("debate_title"); title.fontSize = 14
        title.frame = NSRect(x: 20, y: H - 42, width: W - 40, height: 24)
        title.autoresizingMask = [.width, .minYMargin]
        content.addSubview(title)

        // Participant names
        let names = participants.map { $0.name }.joined(separator: " vs ")
        let namesLabel = PixelLabel()
        namesLabel.text = names; namesLabel.fontSize = 10
        namesLabel.textColor = NSColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1)
        namesLabel.frame = NSRect(x: 20, y: H - 62, width: W - 40, height: 16)
        namesLabel.autoresizingMask = [.width, .minYMargin]
        content.addSubview(namesLabel)

        // Topic input
        topicField = NSTextField(frame: NSRect(x: 20, y: H - 94, width: W - 120, height: 26))
        topicField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        topicField.placeholderString = L10n.s("debate_topic")
        topicField.bezelStyle = .squareBezel
        topicField.backgroundColor = UI_INPUT; topicField.textColor = UI_BROWN
        topicField.focusRingType = .none
        topicField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(topicField)

        // Start button
        startButton = NSButton(frame: NSRect(x: W - 95, y: H - 94, width: 75, height: 26))
        startButton.title = L10n.s("debate_start")
        startButton.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        startButton.bezelStyle = .rounded
        startButton.target = self; startButton.action = #selector(startDebate(_:))
        startButton.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(startButton)

        // Scroll view with text output
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: W - 40, height: H - 126))
        scrollView.hasVerticalScroller = true; scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 1, green: 0.99, blue: 0.96, alpha: 1)

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: W - 56, height: 0))
        textView.isEditable = false; textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        content.addSubview(scrollView)
    }

    func show() {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc func startDebate(_ sender: Any?) {
        let topic = topicField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty, !isDebating, participants.count >= 2 else { return }
        isDebating = true
        startButton.isEnabled = false
        topicField.isEnabled = false
        textView.string = ""

        appendStyled("🎤 ", bold: true, color: UI_BROWN)
        appendStyled(topic + "\n\n", bold: true, color: UI_BROWN)

        runDebate(topic: topic)
    }

    func runDebate(topic: String) {
        // Build per-participant message histories with debate system prompts
        var histories: [[String: Any]] = participants.map { p in
            let debatePrompt: String
            switch L10n.lang {
            case "en":
                debatePrompt = "You are \(p.name), a cat debating with other cats. Stay in character as a \(p.colorDef.traits["en"] ?? "") cat. Give your opinion on the topic. Be concise (2-3 sentences max). React to what others said if applicable. Use cat sounds."
            case "es":
                debatePrompt = "Eres \(p.name), un gato debatiendo con otros gatos. Mantén tu personaje de gato \(p.colorDef.traits["es"] ?? ""). Da tu opinión sobre el tema. Sé conciso (2-3 frases máx). Reacciona a lo que dijeron los demás si aplica. Usa sonidos de gato."
            default:
                debatePrompt = "Tu es \(p.name), un chat qui débat avec d'autres chats. Reste dans ton personnage de chat \(p.colorDef.traits["fr"] ?? ""). Donne ton avis sur le sujet. Sois concis (2-3 phrases max). Réagis à ce que les autres ont dit si applicable. Utilise des sons de chat."
            }
            return [
                "model": p.model,
                "messages": [["role": "system", "content": debatePrompt]] as [[String: String]]
            ]
        }

        // Run rounds sequentially
        var round = 0
        var allResponses: [(name: String, text: String)] = []

        func nextRound() {
            guard round < debateRounds else {
                // Final synthesis by first cat
                self.appendStyled("\n━━━ \(L10n.s("debate_summary")) ━━━\n", bold: true, color: UI_GOLD)
                let summaryPrompt: String
                switch L10n.lang {
                case "en": summaryPrompt = "Summarize the debate in 2-3 sentences. What was the consensus? Use cat sounds."
                case "es": summaryPrompt = "Resume el debate en 2-3 frases. ¿Cuál fue el consenso? Usa sonidos de gato."
                default: summaryPrompt = "Résume le débat en 2-3 phrases. Quel était le consensus ? Utilise des sons de chat."
                }
                var msgs = (histories[0]["messages"] as? [[String: String]]) ?? []
                msgs.append(["role": "user", "content": summaryPrompt])
                let p = self.participants[0]
                self.appendStyled("  \(p.name) \(L10n.s("debate_thinking"))\n", bold: false, color: .gray)
                ollamaSingleShot(model: p.model, messages: msgs) { [weak self] response in
                    guard let self = self else { return }
                    self.replaceLast(with: "")
                    if let r = response {
                        self.appendStyled("🐱 \(p.name): ", bold: true, color: self.colorForParticipant(0))
                        self.appendStyled(r + "\n", bold: false, color: UI_BROWN)
                    }
                    self.appendStyled("\n🏁\n", bold: true, color: UI_BROWN)
                    self.isDebating = false
                    self.startButton.isEnabled = true
                    self.topicField.isEnabled = true
                }
                return
            }

            round += 1
            self.appendStyled("━━━ \(L10n.s("debate_round")) \(round) ━━━\n", bold: true, color: UI_BROWN)

            var catIdx = 0
            func nextCat() {
                guard catIdx < self.participants.count else {
                    // End of round
                    self.appendStyled("\n", bold: false, color: UI_BROWN)
                    nextRound()
                    return
                }

                let p = self.participants[catIdx]
                let ci = catIdx
                var msgs = (histories[ci]["messages"] as? [[String: String]]) ?? []

                // Build the user prompt for this turn
                let userMsg: String
                if round == 1 && catIdx == 0 {
                    // First cat, first round: introduce topic
                    userMsg = topic
                } else {
                    // Include what others said this round
                    let roundStart = allResponses.count - catIdx
                    let context = allResponses.suffix(from: max(0, roundStart))
                        .map { "\($0.name): \($0.text)" }
                        .joined(separator: "\n")
                    if context.isEmpty {
                        userMsg = topic
                    } else {
                        let prefix: String
                        switch L10n.lang {
                        case "en": prefix = "Topic: \(topic)\nHere's what the others said:\n"
                        case "es": prefix = "Tema: \(topic)\nEsto es lo que dijeron los demás:\n"
                        default: prefix = "Sujet: \(topic)\nVoici ce que les autres ont dit :\n"
                        }
                        userMsg = prefix + context
                    }
                }
                msgs.append(["role": "user", "content": userMsg])

                self.appendStyled("  \(p.name) \(L10n.s("debate_thinking"))\n", bold: false, color: .gray)

                ollamaSingleShot(model: p.model, messages: msgs) { [weak self] response in
                    guard let self = self else { return }
                    self.replaceLast(with: "")
                    if let r = response {
                        // Update history for this participant
                        msgs.append(["role": "assistant", "content": r])
                        histories[ci]["messages"] = msgs
                        allResponses.append((name: p.name, text: r))

                        self.appendStyled("🐱 \(p.name): ", bold: true, color: self.colorForParticipant(ci))
                        self.appendStyled(r + "\n", bold: false, color: UI_BROWN)
                    } else {
                        self.appendStyled("🐱 \(p.name): ", bold: true, color: self.colorForParticipant(ci))
                        self.appendStyled("*\(L10n.s("err"))*\n", bold: false, color: .red)
                    }
                    catIdx += 1
                    nextCat()
                }
            }
            nextCat()
        }
        nextRound()
    }

    func colorForParticipant(_ index: Int) -> NSColor {
        guard index < participants.count else { return UI_BROWN }
        return participants[index].colorDef.color
    }

    func appendStyled(_ text: String, bold: Bool, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: bold ? .bold : .regular),
            .foregroundColor: color
        ]
        textView.textStorage?.append(NSAttributedString(string: text, attributes: attrs))
        textView.scrollToEndOfDocument(nil)
    }

    func replaceLast(with text: String) {
        guard let storage = textView.textStorage else { return }
        let str = storage.string
        if let lastNewline = str.dropLast().lastIndex(of: "\n") {
            let start = str.distance(from: str.startIndex, to: lastNewline) + 1
            let range = NSRange(location: start, length: storage.length - start)
            storage.replaceCharacters(in: range, with: text)
        }
    }
}

// MARK: - Dock Detection

func getDockTileSize() -> CGFloat {
    CGFloat(UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 48.0)
}
func isDockAutoHide() -> Bool {
    UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
}
func estimatedDockHeight() -> CGFloat { getDockTileSize() + 16 }
func fixedDockHeight() -> CGFloat {
    guard let screen = NSScreen.main else { return 0 }
    let full = screen.frame; let vis = screen.visibleFrame
    let menuH = full.maxY - vis.maxY
    return max(full.height - vis.height - menuH, 0)
}

// MARK: - Asset Loading & Tinting

/// Cache tinted sprites at original resolution — key: "colorId:relativePath"
var tintCache: [String: NSImage] = [:]

func tintSprite(_ src: NSImage, color: CatColorDef) -> NSImage {
    if color.id == "orange" { return src }

    guard let tiff = src.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let cgSrc = bmp.cgImage else { return src }

    let w = cgSrc.width, h = cgSrc.height
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h,
                             bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return src }

    ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let ptr = ctx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4) else { return src }

    let isPercy = color.id == "percy"

    for i in 0..<(w * h) {
        let o = i * 4
        let a = CGFloat(ptr[o + 3]) / 255.0
        if a < 0.01 { continue }

        let r = CGFloat(ptr[o]) / (255.0 * a)
        let g = CGFloat(ptr[o + 1]) / (255.0 * a)
        let b = CGFloat(ptr[o + 2]) / (255.0 * a)

        if isPercy {
            let grey = r * 0.299 + g * 0.587 + b * 0.114
            let val = max(0, min(1, grey * 0.6 + 0.38))
            let pv = UInt8(max(0, min(255, val * a * 255)))
            ptr[o] = pv; ptr[o + 1] = pv; ptr[o + 2] = pv
            continue
        }

        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        var hh: CGFloat = 0
        if delta > 0.001 {
            if mx == r { hh = fmod((g - b) / delta, 6) / 6 }
            else if mx == g { hh = ((b - r) / delta + 2) / 6 }
            else { hh = ((r - g) / delta + 4) / 6 }
            if hh < 0 { hh += 1 }
        }
        let ss: CGFloat = mx > 0.001 ? delta / mx : 0
        let bb: CGFloat = mx

        let nh = fmod(hh + color.hueShift + 1, 1)
        let ns = max(0, min(1, ss * color.satMul))
        let nb = max(0, min(1, bb + color.briOff))

        let c2 = nb * ns
        let x2 = c2 * (1 - abs(fmod(nh * 6, 2) - 1))
        let m2 = nb - c2
        var nr: CGFloat = 0, ng: CGFloat = 0, nbb: CGFloat = 0
        let sector = Int(nh * 6) % 6
        switch sector {
        case 0: nr = c2; ng = x2; nbb = 0
        case 1: nr = x2; ng = c2; nbb = 0
        case 2: nr = 0; ng = c2; nbb = x2
        case 3: nr = 0; ng = x2; nbb = c2
        case 4: nr = x2; ng = 0; nbb = c2
        default: nr = c2; ng = 0; nbb = x2
        }
        nr += m2; ng += m2; nbb += m2

        ptr[o]     = UInt8(max(0, min(255, nr * a * 255)))
        ptr[o + 1] = UInt8(max(0, min(255, ng * a * 255)))
        ptr[o + 2] = UInt8(max(0, min(255, nbb * a * 255)))
    }

    guard let cgResult = ctx.makeImage() else { return src }
    return NSImage(cgImage: cgResult, size: src.size)
}

func loadTintAndScale(path: String, to size: NSSize, color: CatColorDef) -> NSImage {
    guard let source = NSImage(contentsOfFile: path) else {
        NSLog("⚠️ Missing: \(path)")
        return NSImage(size: size, flipped: false) { r in
            NSColor.magenta.withAlphaComponent(0.5).set(); NSBezierPath(rect: r).fill(); return true
        }
    }
    // Use cached tinted sprite at original resolution, only scale to target size
    let cacheKey = "\(color.id):\(path)"
    let tinted: NSImage
    if let cached = tintCache[cacheKey] {
        tinted = cached
    } else {
        tinted = tintSprite(source, color: color)
        tintCache[cacheKey] = tinted
    }
    return NSImage(size: size, flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .none
        tinted.draw(in: rect); return true
    }
}

// MARK: - Pixel Art UI Components

class PixelBorder: NSView {
    var borderColor = UI_BROWN
    var fillColor = UI_CREAM
    var pixelSize: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds; let p = pixelSize
        fillColor.set(); NSBezierPath(rect: b).fill()
        borderColor.set()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: b.width, height: p)).fill()
        NSBezierPath(rect: NSRect(x: 0, y: b.height - p, width: b.width, height: p)).fill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: p, height: b.height)).fill()
        NSBezierPath(rect: NSRect(x: b.width - p, y: 0, width: p, height: b.height)).fill()
        let i = p * 2
        NSBezierPath(rect: NSRect(x: i, y: i, width: b.width - i*2, height: p)).fill()
        NSBezierPath(rect: NSRect(x: i, y: b.height - i - p, width: b.width - i*2, height: p)).fill()
        NSBezierPath(rect: NSRect(x: i, y: i, width: p, height: b.height - i*2)).fill()
        NSBezierPath(rect: NSRect(x: b.width - i - p, y: i, width: p, height: b.height - i*2)).fill()
        fillColor.set()
        for corner in [(CGFloat(0), CGFloat(0)), (b.width - p, CGFloat(0)),
                       (CGFloat(0), b.height - p), (b.width - p, b.height - p)] {
            NSBezierPath(rect: NSRect(x: corner.0, y: corner.1, width: p, height: p)).fill()
        }
    }
}

class PixelSlider: NSView {
    var value: CGFloat = 1.0 { didSet { needsDisplay = true } }
    var minValue: CGFloat = 0.5
    var maxValue: CGFloat = 3.0
    var onChange: ((CGFloat) -> Void)?
    private let trackColor = UI_BROWN
    private let fillLeft = UI_ORANGE
    private let knobColor = UI_GOLD
    private let knobBorder = UI_BROWN
    private let px: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds; let trackY = b.midY - px * 1.5; let trackH = px * 3; let m: CGFloat = px * 4
        trackColor.set()
        NSBezierPath(rect: NSRect(x: m, y: trackY, width: b.width - m*2, height: trackH)).fill()
        let ratio = (value - minValue) / (maxValue - minValue)
        let fillW = (b.width - m*2) * ratio
        fillLeft.set()
        NSBezierPath(rect: NSRect(x: m, y: trackY, width: fillW, height: trackH)).fill()
        let ks = px * 5; let kx = m + fillW - ks / 2; let ky = b.midY - ks / 2
        knobBorder.set(); NSBezierPath(rect: NSRect(x: kx, y: ky, width: ks, height: ks)).fill()
        knobColor.set(); NSBezierPath(rect: NSRect(x: kx + px, y: ky + px, width: ks - px*2, height: ks - px*2)).fill()
    }
    override func mouseDown(with e: NSEvent) { updateMouse(e) }
    override func mouseDragged(with e: NSEvent) { updateMouse(e) }
    private func updateMouse(_ e: NSEvent) {
        let loc = convert(e.locationInWindow, from: nil); let m: CGFloat = px * 4
        let ratio = max(0, min(1, (loc.x - m) / (bounds.width - m * 2)))
        value = minValue + (maxValue - minValue) * ratio; onChange?(value)
    }
}

class PixelLabel: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var textColor = UI_BROWN
    var fontSize: CGFloat = 13
    var alignment: NSTextAlignment = .center
    var wraps = false

    override func draw(_ dirtyRect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
            .paragraphStyle: style,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        if wraps {
            let textRect = str.boundingRect(with: NSSize(width: bounds.width, height: 9999),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            let drawY = bounds.height - ceil(textRect.height)
            str.draw(in: NSRect(x: 0, y: max(0, drawY), width: bounds.width, height: bounds.height))
        } else {
            let size = str.size(); let yPos = (bounds.height - size.height) / 2
            if alignment == .center {
                str.draw(at: NSPoint(x: max(0, (bounds.width - size.width) / 2), y: yPos))
            } else {
                str.draw(in: NSRect(x: 0, y: yPos, width: bounds.width, height: size.height))
            }
        }
    }
}

// MARK: - KeyableWindow

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Chat Bubble

class ChatBubbleController {
    var window: NSWindow!
    var border: PixelBorder!
    var nameLabel: PixelLabel!
    var responseLabel: PixelLabel!
    var inputField: NSTextField!
    var debateButton: NSButton?
    var onSend: ((String) -> Void)?
    var onDebate: ((String) -> Void)?
    var catName: String = ""
    var debateEnabled = false
    let bubbleW: CGFloat = 300
    var bubbleH: CGFloat = 120
    let px: CGFloat = 3
    let tailH: CGFloat = 12
    let padding: CGFloat = 18
    let inputH: CGFloat = 24
    let gap: CGFloat = 8
    let nameH: CGFloat = 18
    let debateBtnH: CGFloat = 22
    var textW: CGFloat { bubbleW - 40 }
    var savedInputText = ""

    func setup() {
        window = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH),
                               styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.isReleasedWhenClosed = false
        rebuildContent(responseText: L10n.s("hi"))
    }

    func computeTextHeight(for text: String) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .paragraphStyle: style]
        let rect = NSAttributedString(string: text, attributes: attrs)
            .boundingRect(with: NSSize(width: textW, height: 9999),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return max(20, ceil(rect.height) + 6)
    }

    func rebuildContent(responseText: String) {
        if let f = inputField { savedInputText = f.stringValue }
        let content = window.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }

        let textH = computeTextHeight(for: responseText)
        let extraH: CGFloat = debateEnabled ? debateBtnH + 4 : 0
        let bodyH = padding + nameH + 4 + textH + gap + inputH + extraH + padding
        bubbleH = bodyH + tailH

        let oldFrame = window.frame
        if window.isVisible {
            window.setFrame(NSRect(x: oldFrame.origin.x, y: oldFrame.origin.y,
                                   width: bubbleW, height: bubbleH), display: false)
        } else {
            window.setContentSize(NSSize(width: bubbleW, height: bubbleH))
        }

        border = PixelBorder()
        border.frame = NSRect(x: 0, y: tailH, width: bubbleW, height: bodyH)
        content.addSubview(border)

        let tail = PixelTail()
        tail.frame = NSRect(x: bubbleW / 2 - 12, y: 0, width: 24, height: tailH + 3)
        content.addSubview(tail)

        nameLabel = PixelLabel()
        nameLabel.text = catName; nameLabel.fontSize = 12
        nameLabel.alignment = .center; nameLabel.wraps = false
        nameLabel.textColor = UI_BROWN
        nameLabel.frame = NSRect(x: 20, y: tailH + padding + inputH + gap + textH + 4, width: textW, height: nameH)
        content.addSubview(nameLabel)

        responseLabel = PixelLabel()
        responseLabel.text = responseText; responseLabel.fontSize = 11
        responseLabel.alignment = .left; responseLabel.wraps = true
        responseLabel.frame = NSRect(x: 20, y: tailH + padding + inputH + gap, width: textW, height: textH)
        content.addSubview(responseLabel)

        let inputY = tailH + padding + (debateEnabled ? debateBtnH + 4 : 0)
        inputField = NSTextField(frame: NSRect(x: 20, y: inputY, width: textW, height: inputH))
        inputField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        inputField.placeholderString = L10n.s("talk")
        inputField.isBordered = true; inputField.bezelStyle = .squareBezel
        inputField.backgroundColor = UI_INPUT
        inputField.textColor = UI_BROWN
        inputField.focusRingType = .none
        inputField.target = self; inputField.action = #selector(inputSubmitted(_:))
        inputField.stringValue = savedInputText
        content.addSubview(inputField)

        if debateEnabled {
            let btn = NSButton(frame: NSRect(x: 20, y: tailH + padding, width: textW, height: debateBtnH))
            btn.title = L10n.s("debate_start")
            btn.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            btn.bezelStyle = .rounded
            btn.target = self; btn.action = #selector(debateClicked(_:))
            content.addSubview(btn)
            debateButton = btn
        }
    }

    @objc func inputSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sender.stringValue = ""; onSend?(text)
    }

    @objc func debateClicked(_ sender: Any?) {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""; onDebate?(text)
    }

    func show(aboveCatAt catFrame: NSRect) {
        let bx = catFrame.midX - bubbleW / 2
        let by = catFrame.maxY + 4
        window.setFrame(NSRect(x: bx, y: by, width: bubbleW, height: bubbleH), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(inputField)
    }

    /// Reposition only — no focus steal, used during cat movement
    func reposition(aboveCatAt catFrame: NSRect) {
        let bx = catFrame.midX - bubbleW / 2
        let by = catFrame.maxY + 4
        window.setFrameOrigin(NSPoint(x: bx, y: by))
    }

    func hide() { window.orderOut(nil) }
    var isVisible: Bool { window.isVisible }

    func setResponse(_ text: String) { rebuildContent(responseText: text) }

    func appendResponse(_ token: String) {
        let newText = responseLabel.text + token
        let newH = computeTextHeight(for: newText)
        if abs(newH - responseLabel.frame.height) > 3 {
            rebuildContent(responseText: newText)
            window.makeFirstResponder(inputField)
        } else { responseLabel.text = newText }
    }
}

class PixelTail: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let fill = UI_CREAM
        let border = UI_BROWN
        let px: CGFloat = 3; let cx = bounds.midX
        border.set()
        for row in 0..<5 {
            let r = CGFloat(row); let w = px * (5 - r)
            NSBezierPath(rect: NSRect(x: cx - w/2, y: bounds.height - (r+1)*px, width: w, height: px)).fill()
        }
        fill.set()
        for row in 0..<4 {
            let r = CGFloat(row); let w = px * (5 - r) - px * 2
            if w > 0 { NSBezierPath(rect: NSRect(x: cx - w/2, y: bounds.height - (r+1)*px, width: w, height: px)).fill() }
        }
    }
}

// MARK: - Cat Instance

class CatInstance {
    var config: CatConfig
    let colorDef: CatColorDef

    var window: NSWindow!
    var imageView: NSImageView!
    var rotations: [String: NSImage] = [:]
    var animations: [String: [String: [NSImage]]] = [:]

    var state: CatState = .idle
    var direction = "south"
    var frameIndex = 0
    var idleTicks = 0
    private var lastRenderedState: CatState = .idle
    private var lastRenderedDir = "south"
    private var lastRenderedFrame = 0

    var x: CGFloat = 0
    var y: CGFloat = 0
    var destX: CGFloat = 0
    var displayW: CGFloat = 0
    var displayH: CGFloat = 0

    // Mouse tracking
    static let LOOK_RADIUS: CGFloat = 200
    static let CHASE_RADIUS: CGFloat = 120
    static let CHASE_SPEED: CGFloat = 3
    static let CHASE_GIVE_UP: CGFloat = 300
    var chaseTicks = 0

    var dragging = false
    var dragOffset: NSPoint = .zero
    var mouseMoved = false

    enum PosMode { case onDock, onWindow, hidden }
    var posMode: PosMode = .hidden
    var winBounds: NSRect?

    var chatBubble: ChatBubbleController?
    var ollamaChat: OllamaChat!
    var onDebateRequested: ((CatInstance, String) -> Void)?

    // Mini speech bubble for random meows
    var meowWindow: NSWindow?
    var meowLabel: PixelLabel?
    var meowTimer: Timer?

    init(config: CatConfig, colorDef: CatColorDef) {
        self.config = config; self.colorDef = colorDef
    }

    func setup(meta: Metadata, catDir: String, dw: CGFloat, dh: CGFloat,
               model: String, lang: String, startX: CGFloat, startY: CGFloat) {
        displayW = dw; displayH = dh
        loadAssets(meta: meta, catDir: catDir)

        x = startX; y = startY; destX = x

        window = NSWindow(contentRect: NSRect(x: x, y: y, width: displayW, height: displayH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: displayW, height: displayH))
        imageView.imageScaling = .scaleNone
        imageView.image = rotations["south"]
        window.contentView?.addSubview(imageView)

        chatBubble = ChatBubbleController()
        chatBubble!.catName = config.name
        chatBubble!.setup()
        chatBubble!.onSend = { [weak self] text in self?.sendChat(text) }
        chatBubble!.onDebate = { [weak self] topic in
            guard let s = self else { return }
            s.onDebateRequested?(s, topic)
        }
        setupChat(model: model, lang: lang)
    }

    func setupChat(model: String, lang: String) {
        let prompt = colorDef.prompt(name: config.name, lang: lang)
        ollamaChat = OllamaChat(model: model)
        ollamaChat.messages = [["role": "system", "content": prompt]]
        let mem = loadMemory(config.id)
        if mem.count > 1 { ollamaChat.messages.append(contentsOf: mem.dropFirst()) }
    }

    func loadAssets(meta: Metadata, catDir: String) {
        let size = NSSize(width: displayW, height: displayH)
        rotations = [:]; animations = [:]
        for (dir, rel) in meta.frames.rotations {
            rotations[dir] = loadTintAndScale(path: (catDir as NSString).appendingPathComponent(rel),
                                              to: size, color: colorDef)
        }
        for (anim, dirs) in meta.frames.animations {
            animations[anim] = [:]
            for (dir, paths) in dirs {
                animations[anim]![dir] = paths.map {
                    loadTintAndScale(path: (catDir as NSString).appendingPathComponent($0),
                                    to: size, color: colorDef)
                }
            }
        }
    }

    func applyScale(newW: CGFloat, newH: CGFloat, meta: Metadata, catDir: String) {
        displayW = newW; displayH = newH
        loadAssets(meta: meta, catDir: catDir)
        window.setContentSize(NSSize(width: displayW, height: displayH))
        imageView.frame = NSRect(x: 0, y: 0, width: displayW, height: displayH)
        imageView.image = currentImage()
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    var fallbackImage: NSImage {
        rotations[direction] ?? rotations["south"] ?? rotations.values.first ?? NSImage()
    }

    func currentImage() -> NSImage {
        if state == .idle || state == .sleeping || state == .looking { return fallbackImage }
        if let key = animKeys[state], let frames = animations[key]?[direction], !frames.isEmpty {
            return frames[frameIndex % frames.count]
        }
        return fallbackImage
    }

    private func clampAndSync(screenW: CGFloat) {
        if posMode == .onDock {
            x = max(0, min(x, screenW - displayW))
        } else if let wb = winBounds {
            x = max(wb.minX, min(x, wb.maxX - displayW))
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
        if let b = chatBubble, b.isVisible { b.reposition(aboveCatAt: window.frame) }
        if let mw = meowWindow, mw.isVisible {
            let bw = mw.frame.width
            mw.setFrameOrigin(NSPoint(x: window.frame.midX - bw / 2, y: window.frame.maxY + 4))
        }
    }

    func renderTick(screenW: CGFloat) {
        guard posMode != .hidden || dragging else { return }

        if state == .chasing {
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - (x + displayW / 2)
            let dy = mouse.y - (y + displayH / 2)
            let dist = hypot(dx, dy)

            if dist > CatInstance.CHASE_GIVE_UP || chaseTicks > 80 {
                state = .idle; frameIndex = 0; idleTicks = 0; chaseTicks = 0
            } else if dist < displayW * 0.4 {
                state = .idle; frameIndex = 0; idleTicks = 0; chaseTicks = 0
            } else {
                direction = directionFromAngle(atan2(dy, dx) * 180.0 / .pi)
                x += (dx / dist) * CatInstance.CHASE_SPEED
                frameIndex += 1; chaseTicks += 1
            }
            clampAndSync(screenW: screenW)
        } else if state == .walking {
            let dx = destX - x
            if abs(dx) <= WALK_SPEED {
                x = destX; state = .idle; frameIndex = 0; idleTicks = 0
            } else {
                let step: CGFloat = dx > 0 ? WALK_SPEED : -WALK_SPEED
                x += step; direction = step > 0 ? "east" : "west"; frameIndex += 1
            }
            clampAndSync(screenW: screenW)
        } else if oneShotStates.contains(state) {
            if let key = animKeys[state], let frames = animations[key]?[direction] {
                if frameIndex >= frames.count - 1 { state = .idle; frameIndex = 0; idleTicks = 0 }
                else { frameIndex += 1 }
            }
        }
        // Only update image when state, direction, or frame changed
        if state != lastRenderedState || direction != lastRenderedDir || frameIndex != lastRenderedFrame {
            imageView.image = currentImage()
            lastRenderedState = state; lastRenderedDir = direction; lastRenderedFrame = frameIndex
        }
    }

    func mouseDistanceAndDirection(mouse: NSPoint) -> (dist: CGFloat, dir: String) {
        let cx = x + displayW / 2, cy = y + displayH / 2
        let dx = mouse.x - cx, dy = mouse.y - cy
        return (hypot(dx, dy), directionFromAngle(atan2(dy, dx) * 180.0 / .pi))
    }

    func behaviorTick(screenW: CGFloat, mouse: NSPoint) {
        guard posMode != .hidden else { return }
        if chatBubble?.isVisible == true { return }

        // Mouse awareness — check cursor proximity
        let (mouseDist, mouseDir) = mouseDistanceAndDirection(mouse: mouse)

        if state == .idle || state == .looking {
            // Look at cursor if nearby
            if mouseDist < CatInstance.LOOK_RADIUS && mouseDist > displayW * 0.4 {
                direction = mouseDir
                if state != .looking { state = .looking; idleTicks = 0 }
                // Chance to start chasing if cursor is close enough
                if mouseDist < CatInstance.CHASE_RADIUS && Double.random(in: 0..<1) < 0.15 {
                    state = .chasing; frameIndex = 0; chaseTicks = 0; hideMeow()
                    return
                }
                return  // keep looking, skip normal behavior
            } else if state == .looking {
                state = .idle; idleTicks = 0  // cursor left, go back to idle
            }
        }

        if state == .idle {
            idleTicks += 1
            let r = Double.random(in: 0..<1)
            if idleTicks > 15 && r < 0.05 {
                state = .sleeping; idleTicks = 0
            } else if r < 0.25 {
                if posMode == .onDock {
                    state = .walking; frameIndex = 0
                    destX = CGFloat.random(in: displayW...(max(displayW + 1, screenW - displayW)))
                } else if let wb = winBounds {
                    state = .walking; frameIndex = 0
                    let lo = wb.minX; let hi = max(lo + displayW, wb.maxX - displayW)
                    destX = CGFloat.random(in: lo...hi)
                }
            } else if r < 0.30 { state = .eating; frameIndex = 0 }
            else if r < 0.35 { state = .drinking; frameIndex = 0 }
            else if r < 0.38 { showRandomMeow() }
        } else if state == .sleeping {
            // Wake up if cursor is very close
            if mouseDist < CatInstance.CHASE_RADIUS {
                state = .wakingUp; frameIndex = 0; idleTicks = 0
            } else {
                idleTicks += 1
                if idleTicks > Int.random(in: 5...15) { state = .wakingUp; frameIndex = 0; idleTicks = 0 }
            }
        }
    }

    func showOnDock(dockH: CGFloat) {
        posMode = .onDock
        // Pieds du chat posés sur le dock (pas au-dessus)
        y = dockH - displayH * 0.15
        window.setFrameOrigin(NSPoint(x: x, y: y)); window.orderFront(nil)
    }

    static let titleBarH: CGFloat = 28

    func moveToWindow(_ bounds: NSRect, index: Int, total: Int) {
        winBounds = bounds; posMode = .onWindow
        let spacing = bounds.width / CGFloat(total + 1)
        x = bounds.origin.x + spacing * CGFloat(index + 1) - displayW / 2
        x = max(bounds.minX, min(x, bounds.maxX - displayW))
        // Pieds posés sur la barre de titre : bas du sprite = bas de la title bar
        y = bounds.maxY - CatInstance.titleBarH
        window.setFrameOrigin(NSPoint(x: x, y: y)); window.orderFront(nil)
        state = .idle; frameIndex = 0; idleTicks = 0; direction = "south"
    }

    func hideCompletely() {
        posMode = .hidden; chatBubble?.hide(); window.orderOut(nil)
        state = .idle; frameIndex = 0; idleTicks = 0
    }

    func trackWindow(_ frame: NSRect?) {
        guard posMode == .onWindow, !dragging else { return }
        if let f = frame {
            winBounds = f
            y = f.maxY - CatInstance.titleBarH
            x = max(f.minX, min(x, f.maxX - displayW))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else { hideCompletely() }
    }

    // Drag
    func startDrag(at loc: NSPoint) {
        dragging = true; mouseMoved = false
        dragOffset = NSPoint(x: loc.x - window.frame.origin.x, y: loc.y - window.frame.origin.y)
    }
    func continueDrag(at loc: NSPoint) {
        guard dragging else { return }
        x = loc.x - dragOffset.x; y = loc.y - dragOffset.y
        window.setFrameOrigin(NSPoint(x: x, y: y)); mouseMoved = true
    }
    func endDrag() -> Bool { let d = mouseMoved; dragging = false; return d }

    // Chat
    func toggleChat() {
        guard let b = chatBubble else { return }
        if b.isVisible { b.hide() } else { b.show(aboveCatAt: window.frame) }
    }

    func sendChat(_ text: String) {
        guard !ollamaChat.isStreaming else { return }
        chatBubble?.setResponse("..."); chatBubble?.show(aboveCatAt: window.frame)
        state = .eating; frameIndex = 0

        ollamaChat.send(text, onToken: { [weak self] token in
            guard let s = self else { return }
            if s.chatBubble?.responseLabel.text == "..." {
                s.chatBubble?.setResponse(token)
                s.chatBubble?.show(aboveCatAt: s.window.frame)
            } else { s.chatBubble?.appendResponse(token) }
        }, onDone: { [weak self] in
            guard let s = self else { return }
            s.state = .idle; s.frameIndex = 0; s.idleTicks = 0
            saveMemory(s.config.id, s.ollamaChat.messages)
        }, onError: { [weak self] msg in
            self?.chatBubble?.setResponse(msg)
            self?.state = .idle; self?.frameIndex = 0
        })
    }

    func updateSystemPrompt(lang: String) {
        let p = colorDef.prompt(name: config.name, lang: lang)
        if !ollamaChat.messages.isEmpty { ollamaChat.messages[0] = ["role": "system", "content": p] }
        chatBubble?.inputField?.placeholderString = L10n.s("talk")
    }

    // MARK: Random Meow

    func showRandomMeow() {
        guard chatBubble?.isVisible != true else { return }
        meowTimer?.invalidate()

        let text = L10n.randomMeow()
        let fontSize: CGFloat = 11
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 16; let padY: CGFloat = 10
        let bw = ceil(textSize.width) + padX * 2
        let bh = ceil(textSize.height) + padY * 2

        if meowWindow == nil {
            meowWindow = NSWindow(contentRect: .zero, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            meowWindow!.level = .floating; meowWindow!.isOpaque = false
            meowWindow!.backgroundColor = .clear; meowWindow!.hasShadow = false
            meowWindow!.isReleasedWhenClosed = false; meowWindow!.ignoresMouseEvents = true

            let bg = PixelBorder()
            bg.pixelSize = 2
            meowWindow!.contentView!.addSubview(bg)

            let lbl = PixelLabel()
            lbl.fontSize = fontSize; lbl.alignment = .center
            meowWindow!.contentView!.addSubview(lbl)
            meowLabel = lbl
        }

        let bg = meowWindow!.contentView!.subviews[0]
        bg.frame = NSRect(x: 0, y: 0, width: bw, height: bh)
        meowLabel!.frame = NSRect(x: padX, y: padY - 2, width: bw - padX*2, height: bh - padY*2)
        meowLabel!.text = text

        let mx = window.frame.midX - bw / 2
        let my = window.frame.maxY + 4
        meowWindow!.setFrame(NSRect(x: mx, y: my, width: bw, height: bh), display: true)
        meowWindow!.orderFront(nil)

        // Disparaît après 2-3s
        meowTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2...3), repeats: false) {
            [weak self] _ in self?.hideMeow()
        }
    }

    func hideMeow() {
        meowTimer?.invalidate(); meowTimer = nil
        meowWindow?.orderOut(nil)
    }

    func cleanup() { chatBubble?.hide(); hideMeow(); window.orderOut(nil) }
}

// MARK: - Color Bubbles View

class ColorBubblesView: NSView {
    var activeColorIds: Set<String> = []
    var selectedColorId: String?
    var canDelete = true
    var onAdd: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onSelect: ((String) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let sz: CGFloat = 32; let gap: CGFloat = 10
        let total = CGFloat(catColors.count) * (sz + gap) - gap
        var cx = (bounds.width - total) / 2

        for c in catColors {
            let rect = NSRect(x: cx, y: (bounds.height - sz) / 2, width: sz, height: sz)
            let path = NSBezierPath(ovalIn: rect)
            c.color.set(); path.fill()

            // Percy: draw black patches on white bubble
            if c.id == "percy" {
                NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1).set()
                let p1 = NSBezierPath(ovalIn: NSRect(x: cx + 5, y: (bounds.height - sz) / 2 + 10, width: 10, height: 8))
                p1.fill()
                let p2 = NSBezierPath(ovalIn: NSRect(x: cx + 18, y: (bounds.height - sz) / 2 + 16, width: 8, height: 7))
                p2.fill()
                let p3 = NSBezierPath(ovalIn: NSRect(x: cx + 11, y: (bounds.height - sz) / 2 + 3, width: 7, height: 6))
                p3.fill()
            }

            // Border
            let isSel = selectedColorId == c.id && activeColorIds.contains(c.id)
            (isSel ? UI_GOLD :
                     UI_BROWN).set()
            path.lineWidth = isSel ? 3 : 2; path.stroke()

            // Dim if not active
            if !activeColorIds.contains(c.id) {
                NSColor(white: 0.95, alpha: 0.5).set(); path.fill()
            }

            // × button on active cats (if deletable)
            if activeColorIds.contains(c.id) && canDelete {
                let xSz: CGFloat = 14
                let xR = NSRect(x: cx + sz - xSz + 4, y: (bounds.height - sz) / 2 + sz - xSz + 4,
                                width: xSz, height: xSz)
                NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1).set()
                NSBezierPath(ovalIn: xR).fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.boldSystemFont(ofSize: 9)]
                "×".draw(at: NSPoint(x: xR.midX - 3, y: xR.midY - 6), withAttributes: attrs)
            }
            cx += sz + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let sz: CGFloat = 32; let gap: CGFloat = 10
        let total = CGFloat(catColors.count) * (sz + gap) - gap
        var cx = (bounds.width - total) / 2

        for c in catColors {
            let rect = NSRect(x: cx, y: (bounds.height - sz) / 2, width: sz, height: sz)
            if rect.contains(loc) {
                // Check × area
                if activeColorIds.contains(c.id) && canDelete {
                    let xSz: CGFloat = 16 // larger hitbox for easier tapping
                    let xR = NSRect(x: cx + sz - xSz + 4, y: (bounds.height - sz) / 2 + sz - xSz + 4,
                                    width: xSz, height: xSz)
                    if xR.contains(loc) { onRemove?(c.id); return }
                }
                if activeColorIds.contains(c.id) { onSelect?(c.id) }
                else { onAdd?(c.id) }
                return
            }
            cx += sz + gap
        }
    }
}

// MARK: - Flag Row View

class FlagRowView: NSView {
    let flags = [("fr", "🇫🇷"), ("en", "🇬🇧"), ("es", "🇪🇸")]
    var selectedLang = "fr" { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let fw: CGFloat = 40; let gap: CGFloat = 8
        let total = CGFloat(flags.count) * fw + CGFloat(flags.count - 1) * gap
        var x = (bounds.width - total) / 2

        for (lang, emoji) in flags {
            if lang == selectedLang {
                let px: CGFloat = 2
                UI_BROWN.set()
                NSBezierPath(rect: NSRect(x: x - px, y: 1, width: fw + px*2, height: bounds.height - 2)).fill()
                UI_GOLD.set()
                NSBezierPath(rect: NSRect(x: x, y: 1 + px, width: fw, height: bounds.height - 2 - px*2)).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22)]
            let str = NSAttributedString(string: emoji, attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: x + (fw - size.width) / 2, y: (bounds.height - size.height) / 2))
            x += fw + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let fw: CGFloat = 40; let gap: CGFloat = 8
        let total = CGFloat(flags.count) * fw + CGFloat(flags.count - 1) * gap
        var x = (bounds.width - total) / 2
        for (lang, _) in flags {
            if NSRect(x: x, y: 0, width: fw, height: bounds.height).contains(loc) {
                selectedLang = lang; onChange?(lang); break
            }
            x += fw + gap
        }
    }
}

// MARK: - Settings Window

class SettingsWindowController {
    var window: NSWindow!
    var onAdd: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onRename: ((String, String) -> Void)?
    var onScaleChanged: ((CGFloat) -> Void)?
    var onModelChanged: ((String) -> Void)?
    var onLangChanged: ((String) -> Void)?
    var onDebateToggled: ((Bool) -> Void)?
    var getConfigs: (() -> [CatConfig])?
    var getPreview: ((String) -> NSImage?)?

    var currentScale: CGFloat = 1.0
    var currentModel = ""
    var debateEnabled = false
    var selectedColorId: String?
    var sizeLabel: PixelLabel?
    var scaleTimer: Timer?

    let W: CGFloat = 320
    let H: CGFloat = 620

    func setup(scale: CGFloat, model: String, debate: Bool = false) {
        currentScale = scale; currentModel = model; debateEnabled = debate
        if window == nil {
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window = NSWindow(
                contentRect: NSRect(x: (screenFrame.width - W) / 2,
                                    y: (screenFrame.height - H) / 2, width: W, height: H),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "~ Cat Settings ~"
            window.level = .floating; window.isReleasedWhenClosed = false
            window.backgroundColor = UI_CREAM
        }
        if selectedColorId == nil { selectedColorId = getConfigs?().first?.colorId }
        buildContent()
    }

    func refresh() { buildContent() }

    func buildContent() {
        let content = window.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }
        let configs = getConfigs?() ?? []
        let activeIds = Set(configs.map { $0.colorId })

        // Pixel border
        let border = PixelBorder()
        border.frame = NSRect(x: 8, y: 8, width: W - 16, height: H - 16)
        content.addSubview(border)

        // Title
        let title = PixelLabel()
        title.text = L10n.s("title"); title.fontSize = 14
        title.frame = NSRect(x: 20, y: H - 42, width: W - 40, height: 24)
        content.addSubview(title)

        // Language flags
        let langLabel = PixelLabel()
        langLabel.text = L10n.s("lang_label"); langLabel.fontSize = 11
        langLabel.frame = NSRect(x: 20, y: H - 65, width: W - 40, height: 18)
        content.addSubview(langLabel)

        let flags = FlagRowView()
        flags.selectedLang = L10n.lang
        flags.frame = NSRect(x: 20, y: H - 102, width: W - 40, height: 34)
        flags.onChange = { [weak self] lang in self?.onLangChanged?(lang) }
        content.addSubview(flags)

        // "MES CHATS"
        let catsLabel = PixelLabel()
        catsLabel.text = L10n.s("cats"); catsLabel.fontSize = 12
        catsLabel.frame = NSRect(x: 20, y: H - 128, width: W - 40, height: 20)
        content.addSubview(catsLabel)

        // Color bubbles
        let bubbles = ColorBubblesView()
        bubbles.activeColorIds = activeIds
        bubbles.selectedColorId = selectedColorId
        bubbles.canDelete = configs.count > 1
        bubbles.frame = NSRect(x: 10, y: H - 175, width: W - 20, height: 44)
        bubbles.onAdd = { [weak self] colorId in self?.onAdd?(colorId) }
        bubbles.onRemove = { [weak self] colorId in self?.onRemove?(colorId) }
        bubbles.onSelect = { [weak self] colorId in
            self?.selectedColorId = colorId; self?.buildContent()
        }
        content.addSubview(bubbles)

        // Selected cat details
        if let selId = selectedColorId, let cd = colorDef(selId) {
            let cfg = configs.first { $0.colorId == selId }

            // Preview
            if let img = getPreview?(selId) {
                let pv = NSImageView(frame: NSRect(x: (W - 48) / 2, y: H - 230, width: 48, height: 48))
                pv.imageScaling = .scaleProportionallyUpOrDown; pv.image = img
                content.addSubview(pv)
            }

            // Name
            let nameLabel = PixelLabel()
            nameLabel.text = L10n.s("name"); nameLabel.fontSize = 11; nameLabel.alignment = .left
            nameLabel.frame = NSRect(x: 24, y: H - 260, width: 55, height: 20)
            content.addSubview(nameLabel)

            let nf = NSTextField(frame: NSRect(x: 82, y: H - 262, width: W - 112, height: 24))
            nf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            nf.stringValue = cfg?.name ?? cd.names[L10n.lang] ?? ""
            nf.bezelStyle = .squareBezel
            nf.backgroundColor = UI_INPUT
            nf.textColor = UI_BROWN
            nf.focusRingType = .none
            nf.target = self; nf.action = #selector(nameEdited(_:))
            content.addSubview(nf)

            // Personality
            let traitLabel = PixelLabel()
            traitLabel.text = "✦ " + (cd.traits[L10n.lang] ?? "")
            traitLabel.fontSize = 11; traitLabel.alignment = .left
            traitLabel.textColor = NSColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1)
            traitLabel.frame = NSRect(x: 24, y: H - 288, width: W - 48, height: 20)
            content.addSubview(traitLabel)

            // Competence
            let skillLabel = PixelLabel()
            skillLabel.text = cd.skills[L10n.lang] ?? ""
            skillLabel.fontSize = 10; skillLabel.alignment = .left
            skillLabel.textColor = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
            skillLabel.frame = NSRect(x: 24, y: H - 310, width: W - 48, height: 18)
            content.addSubview(skillLabel)
        }

        // Size section
        let sizeTitle = PixelLabel()
        sizeTitle.text = L10n.s("size"); sizeTitle.fontSize = 12
        sizeTitle.frame = NSRect(x: 20, y: 228, width: W - 40, height: 20)
        content.addSubview(sizeTitle)

        sizeLabel = PixelLabel()
        sizeLabel!.fontSize = 11; sizeLabel!.text = String(format: "x%.1f", currentScale)
        sizeLabel!.frame = NSRect(x: 20, y: 210, width: W - 40, height: 18)
        content.addSubview(sizeLabel!)

        let slider = PixelSlider()
        slider.frame = NSRect(x: 24, y: 178, width: W - 48, height: 28)
        slider.minValue = MIN_SCALE; slider.maxValue = MAX_SCALE; slider.value = currentScale
        slider.onChange = { [weak self] v in
            self?.sizeLabel?.text = String(format: "x%.1f", v)
            self?.currentScale = v
            self?.scaleTimer?.invalidate()
            self?.scaleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                self?.onScaleChanged?(v)
            }
        }
        content.addSubview(slider)

        // Model section
        let modelTitle = PixelLabel()
        modelTitle.text = L10n.s("model"); modelTitle.fontSize = 12
        modelTitle.frame = NSRect(x: 20, y: 140, width: W - 40, height: 20)
        content.addSubview(modelTitle)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: 105, width: W - 48, height: 28), pullsDown: false)
        popup.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        popup.target = self; popup.action = #selector(modelSelected(_:))
        content.addSubview(popup)

        popup.addItem(withTitle: L10n.s("loading"))
        fetchOllamaModels { [weak self] models in
            guard let self = self else { return }
            popup.removeAllItems()
            if models.isEmpty { popup.addItem(withTitle: L10n.s("no_ollama")) }
            else {
                for m in models { popup.addItem(withTitle: m) }
                if let idx = models.firstIndex(of: self.currentModel) {
                    popup.selectItem(at: idx)
                }
            }
        }

        // Debate toggle
        let debateTitle = PixelLabel()
        debateTitle.text = L10n.s("debate"); debateTitle.fontSize = 12
        debateTitle.frame = NSRect(x: 20, y: 72, width: W - 40, height: 20)
        content.addSubview(debateTitle)

        let debateStatus = PixelLabel()
        debateStatus.text = debateEnabled ? L10n.s("debate_on") : L10n.s("debate_off")
        debateStatus.fontSize = 10
        debateStatus.textColor = debateEnabled
            ? NSColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1)
            : NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
        debateStatus.frame = NSRect(x: 20, y: 52, width: W / 2 - 20, height: 18)
        content.addSubview(debateStatus)

        let toggle = NSButton(frame: NSRect(x: W / 2, y: 50, width: W / 2 - 24, height: 22))
        toggle.setButtonType(.switch)
        toggle.title = ""
        toggle.state = debateEnabled ? .on : .off
        toggle.target = self; toggle.action = #selector(debateToggled(_:))
        content.addSubview(toggle)
    }

    @objc func nameEdited(_ sender: NSTextField) {
        guard let colorId = selectedColorId else { return }
        onRename?(colorId, sender.stringValue)
    }

    @objc func modelSelected(_ sender: NSPopUpButton) {
        guard let t = sender.selectedItem?.title, !t.hasPrefix("(") else { return }
        currentModel = t; onModelChanged?(t)
    }

    @objc func debateToggled(_ sender: NSButton) {
        debateEnabled = sender.state == .on
        onDebateToggled?(debateEnabled)
        buildContent()
    }

    func show() {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Delegate

class CatAppDelegate: NSObject, NSApplicationDelegate {
    var catInstances: [CatInstance] = []
    var catConfigs: [CatConfig] = []

    var catDir = ""
    var meta: Metadata!
    var spriteW: CGFloat = 68
    var spriteH: CGFloat = 68
    var displayW: CGFloat = 0
    var displayH: CGFloat = 0
    var catScale = DEFAULT_SCALE
    var screenW: CGFloat = 0
    var screenH: CGFloat = 0
    var selectedModel = ""

    var dockVisible = false
    var dockHeight: CGFloat = 0
    var autoHide = false
    var hideTimer: Timer?

    var statusItem: NSStatusItem!
    var settingsCtrl: SettingsWindowController?
    var debateCtrl: CatDebateController?
    var debateEnabled = false
    var localMonitor: Any?
    var globalMonitor: Any?
    var activeDragCat: CatInstance?
    var timers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Resolve paths — check inside .app bundle first, then next to executable
        let base: String
        if let resPath = Bundle.main.resourcePath,
           FileManager.default.fileExists(atPath: (resPath as NSString).appendingPathComponent("cute_orange_cat")) {
            base = resPath
        } else {
            let exec = CommandLine.arguments[0]
            if exec.hasPrefix("/") { base = (exec as NSString).deletingLastPathComponent }
            else {
                let cwd = FileManager.default.currentDirectoryPath
                base = ((cwd as NSString).appendingPathComponent(exec) as NSString).deletingLastPathComponent
            }
        }
        catDir = (base as NSString).appendingPathComponent("cute_orange_cat")
        let metaPath = (catDir as NSString).appendingPathComponent("metadata.json")

        guard let metaData = FileManager.default.contents(atPath: metaPath) else {
            fatalError("metadata.json introuvable: \(metaPath)")
        }
        do {
            meta = try JSONDecoder().decode(Metadata.self, from: metaData)
        } catch {
            fatalError("metadata.json invalide: \(error.localizedDescription)")
        }
        spriteW = CGFloat(meta.character.size.width)
        spriteH = CGFloat(meta.character.size.height)

        // Load preferences
        let s = UserDefaults.standard.double(forKey: SCALE_KEY)
        if s > 0 { catScale = CGFloat(s) }
        selectedModel = UserDefaults.standard.string(forKey: MODEL_KEY) ?? "gemma4:latest"
        L10n.lang = UserDefaults.standard.string(forKey: LANG_KEY) ?? "fr"
        debateEnabled = UserDefaults.standard.bool(forKey: DEBATE_KEY)

        recomputeSize()

        guard let screen = NSScreen.main else { fatalError("Pas d'écran") }
        screenW = screen.frame.width; screenH = screen.frame.height

        // Dock
        autoHide = isDockAutoHide()
        if autoHide { dockHeight = estimatedDockHeight(); dockVisible = false }
        else {
            dockHeight = fixedDockHeight()
            if dockHeight < 10 { dockHeight = estimatedDockHeight() }
            dockVisible = true
        }

        // Load cat configs
        catConfigs = loadConfigs()
        if catConfigs.isEmpty {
            let def = CatConfig(id: UUID().uuidString, colorId: "orange",
                                name: catColors[0].names[L10n.lang] ?? "Citrouille")
            catConfigs = [def]; saveConfigs(catConfigs)
        }
        for (i, cfg) in catConfigs.enumerated() { createInstance(config: cfg, index: i) }
        if dockVisible { for cat in catInstances { cat.showOnDock(dockH: dockHeight) } }

        // Status bar
        setupStatusItem()

        // Mouse events
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] _ in
            guard let s = self, s.autoHide else { return }
            s.checkMouseForDock()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in self?.handleMouse(event) ?? event }

        // Timers
        timers = [
            Timer.scheduledTimer(withTimeInterval: RENDER_FPS, repeats: true) { [weak self] _ in self?.renderTick() },
            Timer.scheduledTimer(withTimeInterval: BEHAVIOR_SEC, repeats: true) { [weak self] _ in self?.behaviorTick() },
            Timer.scheduledTimer(withTimeInterval: DOCK_POLL_SEC, repeats: true) { [weak self] _ in self?.pollDock() },
            Timer.scheduledTimer(withTimeInterval: MOUSE_POLL_SEC, repeats: true) { [weak self] _ in
                guard let s = self, s.autoHide else { return }
                s.checkMouseForDock()
            },
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.trackWindows() },
        ]
    }

    // MARK: Cat Management

    func createInstance(config: CatConfig, index: Int) {
        guard let cd = colorDef(config.colorId) else { return }
        let inst = CatInstance(config: config, colorDef: cd)
        let startX = screenW / 2 - displayW / 2 + CGFloat(index) * displayW * 1.5
        inst.setup(meta: meta, catDir: catDir, dw: displayW, dh: displayH,
                   model: selectedModel, lang: L10n.lang,
                   startX: max(0, min(startX, screenW - displayW)), startY: dockHeight)
        inst.chatBubble?.debateEnabled = debateEnabled
        inst.onDebateRequested = { [weak self] cat, topic in self?.startDebate(from: cat, topic: topic) }
        catInstances.append(inst)
    }

    func addCat(colorId: String) {
        guard let cd = colorDef(colorId) else { return }
        // Prevent duplicate color
        guard !catConfigs.contains(where: { $0.colorId == colorId }) else { return }

        let name = cd.names[L10n.lang] ?? cd.names["fr"] ?? cd.id
        let cfg = CatConfig(id: UUID().uuidString, colorId: colorId, name: name)
        catConfigs.append(cfg); saveConfigs(catConfigs)
        createInstance(config: cfg, index: catInstances.count)

        let cat = catInstances.last!
        if dockVisible { cat.showOnDock(dockH: dockHeight) }
        else if let f = frontmostWindowFrame() {
            cat.moveToWindow(f, index: catInstances.count - 1, total: catInstances.count)
        }

        settingsCtrl?.selectedColorId = colorId
        settingsCtrl?.refresh()
    }

    func removeCat(colorId: String) {
        guard catConfigs.count > 1 else { return }
        guard let idx = catInstances.firstIndex(where: { $0.colorDef.id == colorId }) else { return }
        let cat = catInstances[idx]
        cat.cleanup(); catInstances.remove(at: idx)
        catConfigs.removeAll { $0.colorId == colorId }; saveConfigs(catConfigs)
        deleteMemory(cat.config.id)

        settingsCtrl?.selectedColorId = catConfigs.first?.colorId
        settingsCtrl?.refresh()
    }

    func renameCat(colorId: String, name: String) {
        guard let idx = catConfigs.firstIndex(where: { $0.colorId == colorId }) else { return }
        catConfigs[idx].name = name; saveConfigs(catConfigs)
        if let inst = catInstances.first(where: { $0.colorDef.id == colorId }) {
            inst.config.name = name; inst.chatBubble?.catName = name
            inst.updateSystemPrompt(lang: L10n.lang)
        }
    }

    // MARK: Size & Model

    func recomputeSize() {
        let tile = getDockTileSize()
        let base = tile / spriteH; let final = base * catScale
        displayW = round(spriteW * final); displayH = round(spriteH * final)
    }

    func applyNewScale(_ s: CGFloat) {
        catScale = s; UserDefaults.standard.set(Double(s), forKey: SCALE_KEY)
        recomputeSize()
        for cat in catInstances {
            cat.applyScale(newW: displayW, newH: displayH, meta: meta, catDir: catDir)
            if cat.posMode == .onDock { cat.showOnDock(dockH: dockHeight) }
        }
    }

    func setLanguage(_ lang: String) {
        L10n.lang = lang; UserDefaults.standard.set(lang, forKey: LANG_KEY)
        for cat in catInstances { cat.updateSystemPrompt(lang: lang) }
        settingsCtrl?.refresh()
    }

    func setModel(_ model: String) {
        selectedModel = model; UserDefaults.standard.set(model, forKey: MODEL_KEY)
        for cat in catInstances { cat.ollamaChat.model = model }
    }

    func setDebateEnabled(_ enabled: Bool) {
        debateEnabled = enabled; UserDefaults.standard.set(enabled, forKey: DEBATE_KEY)
        for cat in catInstances { cat.chatBubble?.debateEnabled = enabled }
    }

    func startDebate(from initiator: CatInstance, topic: String) {
        guard catInstances.count >= 2 else { return }
        // Close all chat bubbles
        for cat in catInstances { cat.chatBubble?.hide() }

        // Build participants from all active cats
        let participants = catInstances.map { cat in
            CatDebateController.Participant(
                name: cat.config.name,
                colorDef: cat.colorDef,
                model: cat.ollamaChat.model
            )
        }

        if debateCtrl == nil { debateCtrl = CatDebateController() }
        debateCtrl!.setup(participants: participants)
        debateCtrl!.show()
        debateCtrl!.topicField.stringValue = topic
        debateCtrl!.startDebate(nil)
    }

    // MARK: Status Bar

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.title = "🐱"; btn.action = #selector(statusItemClicked(_:)); btn.target = self
        }
    }

    @objc func statusItemClicked(_ sender: Any?) {
        let menu = NSMenu()
        let sItem = NSMenuItem(title: L10n.s("settings"), action: #selector(openSettings(_:)), keyEquivalent: ",")
        sItem.target = self; menu.addItem(sItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.s("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu; statusItem.button?.performClick(nil)
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsCtrl == nil { settingsCtrl = SettingsWindowController() }
        let ctrl = settingsCtrl!
        ctrl.getConfigs = { [weak self] in self?.catConfigs ?? [] }
        ctrl.getPreview = { [weak self] colorId in
            guard let self = self, let cd = colorDef(colorId) else { return nil }
            guard let southRel = self.meta.frames.rotations["south"] else { return nil }
            let path = (self.catDir as NSString).appendingPathComponent(southRel)
            guard let img = NSImage(contentsOfFile: path) else { return nil }
            return tintSprite(img, color: cd)
        }
        ctrl.onAdd = { [weak self] colorId in self?.addCat(colorId: colorId) }
        ctrl.onRemove = { [weak self] colorId in self?.removeCat(colorId: colorId) }
        ctrl.onRename = { [weak self] colorId, name in self?.renameCat(colorId: colorId, name: name) }
        ctrl.onScaleChanged = { [weak self] v in self?.applyNewScale(v) }
        ctrl.onModelChanged = { [weak self] m in self?.setModel(m) }
        ctrl.onLangChanged = { [weak self] l in self?.setLanguage(l) }
        ctrl.onDebateToggled = { [weak self] enabled in self?.setDebateEnabled(enabled) }
        ctrl.setup(scale: catScale, model: selectedModel, debate: debateEnabled)
        ctrl.show()
    }

    // MARK: Dock Visibility

    func checkMouseForDock() {
        guard autoHide else { return }
        let mouseY = NSEvent.mouseLocation.y
        guard let screen = NSScreen.main else { return }
        let screenBottom = screen.frame.origin.y
        let nearBottom = mouseY - screenBottom < 6
        let inDockArea = mouseY - screenBottom < dockHeight + displayH

        if nearBottom || (dockVisible && inDockArea) {
            hideTimer?.invalidate(); hideTimer = nil
            if !dockVisible { showAllOnDock() }
        } else if dockVisible && catInstances.allSatisfy({ $0.posMode == .onDock }) {
            if hideTimer == nil {
                hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    self?.hideAllFromDock(); self?.hideTimer = nil
                }
            }
        }
    }

    func pollDock() {
        if let screen = NSScreen.main { screenW = screen.frame.width; screenH = screen.frame.height }
        let newAutoHide = isDockAutoHide()
        if newAutoHide != autoHide {
            autoHide = newAutoHide
            if !autoHide {
                dockHeight = fixedDockHeight()
                if dockHeight < 10 { dockHeight = estimatedDockHeight() }
                showAllOnDock()
            } else { dockHeight = estimatedDockHeight(); hideAllFromDock() }
        }
        if !autoHide {
            let dh = fixedDockHeight()
            if dh > 10 && abs(dh - dockHeight) > 2 {
                dockHeight = dh
                for cat in catInstances where cat.posMode == .onDock && !cat.dragging {
                    cat.showOnDock(dockH: dockHeight)
                }
            }
            if !dockVisible { showAllOnDock() }
        }
    }

    func showAllOnDock() {
        dockVisible = true
        for cat in catInstances { cat.showOnDock(dockH: dockHeight) }
    }

    func hideAllFromDock() {
        dockVisible = false
        for cat in catInstances { cat.chatBubble?.hide() }
        if let frame = frontmostWindowFrame() {
            for (i, cat) in catInstances.enumerated() {
                cat.moveToWindow(frame, index: i, total: catInstances.count)
            }
        } else {
            for cat in catInstances { cat.hideCompletely() }
        }
    }

    func frontmostWindowFrame() -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let wX = (bounds["X"] as? NSNumber)?.doubleValue,
                  let wY = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let wW = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let wH = (bounds["Height"] as? NSNumber)?.doubleValue,
                  wW > 100, wH > 100
            else { continue }
            let cocoaY = screenH - CGFloat(wY) - CGFloat(wH)
            return NSRect(x: CGFloat(wX), y: cocoaY, width: CGFloat(wW), height: CGFloat(wH))
        }
        return nil
    }

    func trackWindows() {
        guard catInstances.contains(where: { $0.posMode == .onWindow }) else { return }
        let frame = frontmostWindowFrame()
        for cat in catInstances { cat.trackWindow(frame) }
    }

    // MARK: Mouse

    func handleMouse(_ event: NSEvent) -> NSEvent? {
        let loc = NSEvent.mouseLocation

        switch event.type {
        case .rightMouseDown:
            for cat in catInstances {
                if cat.window.frame.contains(loc) {
                    let menu = NSMenu(title: "Cat")
                    menu.addItem(NSMenuItem(title: L10n.s("quit"),
                                            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
                    NSMenu.popUpContextMenu(menu, with: event, for: cat.imageView)
                    return nil
                }
            }
            return event

        case .leftMouseDown:
            for cat in catInstances {
                if cat.window.frame.contains(loc) {
                    cat.startDrag(at: loc); activeDragCat = cat
                    return event
                }
            }
            return event

        case .leftMouseDragged:
            activeDragCat?.continueDrag(at: NSEvent.mouseLocation)
            return event

        case .leftMouseUp:
            if let cat = activeDragCat {
                let wasDrag = cat.endDrag()
                activeDragCat = nil
                if !wasDrag {
                    // Close other bubbles, toggle this one
                    for c in catInstances where c !== cat { c.chatBubble?.hide() }
                    cat.toggleChat()
                }
            }
            return event

        default: return event
        }
    }

    // MARK: Ticks

    func renderTick() { for cat in catInstances { cat.renderTick(screenW: screenW) } }
    func behaviorTick() {
        let mouse = NSEvent.mouseLocation
        for cat in catInstances { cat.behaviorTick(screenW: screenW, mouse: mouse) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        for cat in catInstances { cat.cleanup() }
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = CatAppDelegate()
app.delegate = delegate
app.run()
