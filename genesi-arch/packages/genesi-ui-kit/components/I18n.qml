/*
 * Genesi UI kit — tiny runtime i18n helper, shared by every Genesi Qt6/QML app.
 *
 * English is the DEFAULT; Portuguese (pt-BR) is the alternate. The choice is
 * persisted (QtCore Settings) and switching is LIVE: every `i18n.t("key")`
 * binding re-evaluates when `lang` changes, because t() reads `lang` during
 * evaluation and QML captures that as a dependency. No .ts/.qm build step.
 *
 * Usage (mirror the Theme pattern — instantiate once per window root):
 *     I18n { id: i18n }
 *     QQC2.Label { text: i18n.t("nav.dashboard") }
 *     // toggle from a button: i18n.toggle()
 *
 * Add a key to BOTH dictionaries below. Missing keys fall back to English, then
 * to the raw key, so a half-translated string is never blank.
 *
 * Canonical source: genesi-arch/packages/genesi-ui-kit/components/. Bundled into
 * each app at build (see README) — NOT a published package.
 */
import QtQuick
import QtCore

Item {
    id: i18n
    visible: false
    width: 0; height: 0

    // "en" (default) or "pt". Persisted across launches.
    property string lang: "en"
    function toggle() { lang = (lang === "en" ? "pt" : "en") }
    // Short label for a switch button ("EN" / "PT").
    readonly property string code: lang === "pt" ? "PT" : "EN"

    Settings {
        id: _store
        category: "Genesi/i18n"
        property alias lang: i18n.lang
    }

    function t(key) {
        var table = _d[lang] || _d["en"]
        if (table && table[key] !== undefined) return table[key]
        if (_d["en"][key] !== undefined) return _d["en"][key]
        return key
    }

    readonly property var _d: ({
        "en": {
            // nav / shell
            "nav.dashboard": "Dashboard",
            "nav.chat": "AI Chat",
            "nav.models": "Models",
            "nav.settings": "Settings",
            "lang.tooltip": "Switch language (English / Português)",
            // mode segmented control
            "mode.on": "Force ON",
            "mode.auto": "Auto",
            "mode.off": "Force OFF",
            // profile segmented control
            "prof.max": "Maximum",
            "prof.balanced": "Balanced",
            "prof.battery": "Battery",
            "prof.auto": "Auto",
            // hero card
            "hero.off": "AI Mode OFF",
            "hero.onMax": "AI Mode ON · maximum",
            "hero.onBalanced": "AI Mode ON · balanced",
            "hero.onBattery": "AI Mode ON · battery",
            "hero.onEconomy": "AI Mode ON · economy",
            "hero.generating": "● generating",
            "hero.warm": "○ model warm · idle",
            "hero.standby": "○ standing by",
            "hero.optReal": "Optimizations applied in real time",
            "hero.noTweaks": "No tweaks applied",
            // metric cards
            "card.cpu": "CPU",
            "card.memory": "MEMORY",
            "card.inference": "INFERENCE",
            "u.cores": "cores",
            "u.threads": "threads",
            "u.inUse": "MB in use",
            "u.noModel": "no model",
            "u.active": "Active",
            // turbo card
            "turbo.title": "Turbo Mode",
            "turbo.speculative": "⚡ speculative",
            "turbo.fullOffload": "full offload",
            "turbo.installBackend": "Install Backend",
            "turbo.backend": "Backend: CUDA / Vulkan",
            "turbo.recommendedGpu": "Recommended for your GPU:",
            "turbo.descSpec": "Advanced mode: ⚡ speculative decoding + dynamic draft + persistent KV cache on disk.",
            "turbo.descFull": "Full GPU offload (stable). Flip ⚡ for the advanced stack.",
            // optimizations card
            "opt.applied": "Optimizations applied",
            "opt.inactive": "Inactive — no tweaks applied",
            "opt.hint": "Start a local model (or use Force ON) to see live tuning here.",
            // benchmark card
            "bench.title": "Performance benchmark",
            "bench.run": "Run benchmark",
            "bench.measuring": "Measuring…",
            "bench.gain": "% generation gain with AI Mode ON",
            "bench.vmNote": "  ·  in a VM the governor is a no-op; run on bare metal for the real gain",
            "bench.descPre": "Compares generation speed (tokens/s) with AI Mode OFF and ON, on model ",
            "bench.descPost": ". Takes ~1 min (runs twice).",
            // chat page
            "chat.model": "Model",
            "chat.reload": "Reload models",
            "chat.noModels": "No Ollama models found. Run `ollama pull llama3.2` and make sure the service is up (`systemctl enable --now ollama`).",
            "chat.emptyTitle": "Chat with the local AI",
            "chat.emptySub": "Runs 100% on your hardware. Ask something below.",
            "chat.placeholder": "Ask the AI something…",
            "chat.ready": "ready",
            "chat.generating": "generating…",
            "chat.error": "error",
            "chat.ollamaRunning": "  — is Ollama running?",
            "chat.hero": "How can I help?",
            "chat.heroSub": "Ask anything. Genesi can reason, create, find information and work with your local models.",
            "chat.sug1Title": "Genesi Assistant",
            "chat.sug1Body": "Help me optimize my local AI setup and maximize performance.",
            "chat.sug1Tag": "AI Mode · Turbo",
            "chat.sug2Title": "Model recommendation",
            "chat.sug2Body": "Find a model that fits my hardware and coding workflow.",
            "chat.sug2Tag": "Models",
            "chat.sug3Title": "Genesi Find",
            "chat.sug3Body": "Search your files by describing them, not by naming them.",
            "chat.sug3Tag": "Search & research",
            "chat.attach": "Attach",
            "chat.stop": "Stop",
            "chat.send": "Send",
            "find.name": "Genesi Find",
            "find.searching": "searching your files…",
            "find.none": "Nothing matched that description.",
            "find.count": "file(s) found",
            "find.open": "Open",
            "find.reveal": "Show in folder",
            "find.copy": "Copy path",
            "find.copied": "Path copied",
            "find.placeholder": "Describe the file you are looking for…",
            "find.on": "Genesi Find is on — your next message searches your files.",
            // models / advisor page
            "adv.title": "Which model fits your hardware",
            "adv.reload": "Reload",
            "adv.empty": "Nothing to report yet. Genesi looks at your GPU, your RAM and the models you have, then says which ones actually fit.",
            "adv.placeholder": "e.g. llama3.2:3b   or   llama3.1:8b",
            "adv.download": "Download",
            "adv.downloading": "Downloading…",
            "adv.startingPre": "starting download of ",
            // ── local GGUF library ──
            "gguf.title": "Local GGUF models",
            "gguf.subtitle": "Use any .gguf on this machine — a Hugging Face "
                + "download works directly, no Ollama import. Drag a file onto "
                + "this window, pick one, or paste a direct link.",
            "gguf.addFile": "Add GGUF file",
            "gguf.add": "Add",
            "gguf.adding": "Adding…",
            "gguf.added": "Added",
            "gguf.urlPlaceholder": "…or paste a direct .gguf link",
            "gguf.pick": "Choose a GGUF model",
            "gguf.drop": "Drop the .gguf here",
            "gguf.openFolder": "Open the models folder",
            "gguf.rescan": "Rescan for GGUF files",
            "gguf.remove": "Remove from the library",
            "gguf.use": "Use with Turbo",
            "gguf.inUse": "In use",
            "gguf.empty": "No GGUF files found yet. Add one above, or drop it in "
                + "your Downloads folder and press rescan.",
            "gguf.fitGpu": "FITS GPU",
            "gguf.fitMoe": "MoE OFFLOAD",
            "gguf.fitSpill": "SLOW",
            "gguf.fitCpu": "CPU",
            // dialogs + tooltips
            "dlg.backendTitle": "Install the Turbo backend",
            "dlg.backendIntro": "Choose the Turbo inference engine (llama-server).",
            "dlg.recommended": "Recommended",
            "dlg.vulkanDesc": "Universal: runs on any GPU (AMD, Intel, NVIDIA open/NVK). It's Genesi's ready-to-go backend (genesi-llama-cpp, lightweight, ~tens of MB). Best choice for most people and for the live ISO.",
            "dlg.cudaDesc": "NVIDIA only, with the proprietary driver active. ~1.5–2× faster than Vulkan, but it's a heavy AUR build (llama.cpp-cuda, pulls CUDA). Best on an installed system, not the RAM-backed live ISO.",
            "dlg.cudaWarn": "⚠ nvidia-smi isn't responding here — install the proprietary NVIDIA driver first, otherwise CUDA won't run.",
            "dlg.aurNeed": "Requires an AUR helper (paru/yay) installed.",
            "dlg.turboTitle": "Which model for Turbo?",
            "dlg.turboPick": "Pick the model Turbo should serve. It stays on this one until you turn Turbo off or pick another.",
            "dlg.turboNone": "No local models found. Pull one first (Chat page) or run: ollama pull llama3.2",
            "dlg.fitsGpu": "fits your GPU",
            "dlg.startTurbo": "Start Turbo on this model",
            "tip.recVram": "Use the largest model that runs 100% in your VRAM (full offload, no CPU spill)",
            // API Inspector
            "insp.httpsHelp": "HTTPS not decrypting?",
            "insp.trustCert": "Trust HTTPS cert",
            "insp.caTrusted": "✓ CA trusted",
            "insp.openBrowser": "Open Browser",
            "insp.openBrowserTip": "Launch a pre-configured browser routed through the inspector (no system-wide proxy)",
            // Sandboxes
            "sb.newWorkspace": "New workspace",
            "sb.removeWorkspace": "Remove workspace",
            "sb.distroboxMissing": "Distrobox is not installed",
            "sb.noBackend": "No container backend found",
            "sb.dockerNotRunning": "Docker is installed but not running",
            "sb.dockerNoPerm": "Your user can't talk to Docker yet",
            "sb.all": "All workspaces",
            "sb.running": "Running",
            "sb.stopped": "Stopped",
            // Snapshots ("indestructible OS")
            "snap.subtitle": "Your system, crash-proof",
            "snap.refresh": "Refresh",
            "snap.create": "Snapshot now",
            "snap.baseline": "Genesi baseline",
            "snap.beforeUpdate": "Before update",
            "snap.afterUpdate": "After update",
            "snap.manual": "Manual snapshot",
            "snap.stProtected": "Protected",
            "snap.stProtectedSub": "A restore point is taken automatically before every update. If a boot ever breaks, pick a snapshot in the GRUB menu to go back.",
            "snap.stArming": "Setting up protection…",
            "snap.stArmingSub": "Genesi is configuring snapshots on this Btrfs system. This finishes on the next boot.",
            "snap.stUnavailable": "Unavailable",
            "snap.stUnavailableSub": "Snapshots need a Btrfs root filesystem. This install isn't on Btrfs, so protection is off.",
            "snap.capUpdate": "Auto before updates",
            "snap.capBoot": "Recovery at boot",
            "snap.capPoints": "restore points",
            "snap.noBtrfsTitle": "Root isn't Btrfs",
            "snap.noBtrfsBody": "The snapshot system needs a Btrfs root. Reinstall Genesi with the default Btrfs layout to enable it.",
            "snap.armingTitle": "Finishing setup",
            "snap.armingBody": "Snapshots are being configured. Reboot once and protection will be fully active.",
            "snap.timeline": "RESTORE POINTS",
            "snap.empty": "No snapshots yet — one will appear before your next update, or create one now.",
            "snap.restore": "Restore",
            "snap.restoreTip": "Make this snapshot the system you boot into (reboot to apply)",
            "snap.delete": "Delete snapshot",
            "snap.createTitle": "Create a snapshot",
            "snap.createPlaceholder": "What are you about to change? (optional)",
            "snap.cancel": "Cancel",
            "snap.rollbackTitle": "Roll back to",
            "snap.rollbackBody": "Genesi will make this snapshot the default system and reboot into it. Your current state is snapshotted first, so this is itself undoable. Nothing is deleted.",
            "snap.rollbackConfirm": "Roll back & reboot",
            // recovery mode (booted a read-only snapshot from the GRUB menu)
            "rec.title": "You're in Recovery Mode",
            "rec.body": "You picked an older snapshot in the GRUB menu, so the system is running read-only — nothing you change here is saved. If this snapshot works well, restore it to make it your normal, writable system again, then reboot.",
            "rec.snapshot": "Booted snapshot",
            "rec.restore": "Restore this system",
            "rec.restoreTip": "Make this snapshot your permanent, writable system. Your current system is kept as a backup — nothing is deleted.",
            "rec.reboot": "Reboot",
            "rec.confirmTitle": "Restore this snapshot?",
            "rec.confirmBody": "Genesi will make the snapshot you booted your normal system. Your current system is kept as a one-click backup, and nothing is deleted. When it finishes, reboot to use the restored system.",
            "rec.confirmBtn": "Restore this system",
            "rec.actionsLocked": "Read-only right now — restore this system first (above) to manage snapshots again.",
            // genesi-find — describe a file instead of naming it
            "find.title": "Find a file",
            "find.placeholder": "Describe the file — \"the contract PDF from last month\"",
            "find.search": "Search",
            "find.searching": "Searching…",
            "find.scope": "in",
            "find.empty": "Nothing matched that description.",
            "find.hint": "Describe it the way you would describe it to a person. Words from the name help most.",
            "find.open": "Open",
            "find.reveal": "Show in folder",
            "find.copyPath": "Copy path",
            "find.results": "results",
            "find.byModel": "refined by the local model",
            "find.byParser": "built-in parser — no model warm",
            "find.filter": "filter"
        },
        "pt": {
            // nav / shell
            "nav.dashboard": "Painel",
            "nav.chat": "Chat IA",
            "nav.models": "Modelos",
            "nav.settings": "Ajustes",
            "lang.tooltip": "Trocar idioma (English / Português)",
            // mode segmented control
            "mode.on": "Forçar ON",
            "mode.auto": "Auto",
            "mode.off": "Forçar OFF",
            // profile segmented control
            "prof.max": "Máximo",
            "prof.balanced": "Equilibrado",
            "prof.battery": "Bateria",
            "prof.auto": "Auto",
            // hero card
            "hero.off": "AI Mode desligado",
            "hero.onMax": "AI Mode ligado · máximo",
            "hero.onBalanced": "AI Mode ligado · equilibrado",
            "hero.onBattery": "AI Mode ligado · bateria",
            "hero.onEconomy": "AI Mode ligado · economia",
            "hero.generating": "● gerando",
            "hero.warm": "○ modelo aquecido · ocioso",
            "hero.standby": "○ em espera",
            "hero.optReal": "Otimizações aplicadas em tempo real",
            "hero.noTweaks": "Nenhum ajuste aplicado",
            // metric cards
            "card.cpu": "CPU",
            "card.memory": "MEMÓRIA",
            "card.inference": "INFERÊNCIA",
            "u.cores": "núcleos",
            "u.threads": "threads",
            "u.inUse": "MB em uso",
            "u.noModel": "sem modelo",
            "u.active": "Ativo",
            // turbo card
            "turbo.title": "Modo Turbo",
            "turbo.speculative": "⚡ especulativo",
            "turbo.fullOffload": "offload total",
            "turbo.installBackend": "Instalar backend",
            "turbo.backend": "Backend: CUDA / Vulkan",
            "turbo.recommendedGpu": "Recomendado pra sua GPU:",
            "turbo.descSpec": "Modo avançado: ⚡ decodificação especulativa + draft dinâmico + cache KV persistente em disco.",
            "turbo.descFull": "Offload total na GPU (estável). Ative o ⚡ pro modo avançado.",
            // optimizations card
            "opt.applied": "Otimizações aplicadas",
            "opt.inactive": "Inativo — nenhum ajuste aplicado",
            "opt.hint": "Inicie um modelo local (ou use Forçar ON) pra ver os ajustes ao vivo aqui.",
            // benchmark card
            "bench.title": "Benchmark de desempenho",
            "bench.run": "Rodar benchmark",
            "bench.measuring": "Medindo…",
            "bench.gain": "% de ganho na geração com o AI Mode ligado",
            "bench.vmNote": "  ·  numa VM o governor não faz efeito; rode em bare metal pro ganho real",
            "bench.descPre": "Compara a velocidade de geração (tokens/s) com o AI Mode desligado e ligado, no modelo ",
            "bench.descPost": ". Leva ~1 min (roda duas vezes).",
            // chat page
            "chat.model": "Modelo",
            "chat.reload": "Recarregar modelos",
            "chat.noModels": "Nenhum modelo do Ollama encontrado. Rode `ollama pull llama3.2` e confira se o serviço está ativo (`systemctl enable --now ollama`).",
            "chat.emptyTitle": "Converse com a IA local",
            "chat.emptySub": "Roda 100% no seu hardware. Pergunte algo abaixo.",
            "chat.placeholder": "Pergunte algo à IA…",
            "chat.ready": "pronto",
            "chat.generating": "gerando…",
            "chat.error": "erro",
            "chat.ollamaRunning": "  — o Ollama está rodando?",
            "chat.hero": "Como posso ajudar?",
            "chat.heroSub": "Pergunte qualquer coisa. O Genesi raciocina, cria, encontra informação e trabalha com seus modelos locais.",
            "chat.sug1Title": "Assistente Genesi",
            "chat.sug1Body": "Me ajude a otimizar minha IA local e extrair o máximo de desempenho.",
            "chat.sug1Tag": "AI Mode · Turbo",
            "chat.sug2Title": "Recomendação de modelo",
            "chat.sug2Body": "Ache um modelo que caiba no meu hardware e no meu fluxo de código.",
            "chat.sug2Tag": "Modelos",
            "chat.sug3Title": "Genesi Find",
            "chat.sug3Body": "Busque seus arquivos descrevendo eles, sem precisar do nome.",
            "chat.sug3Tag": "Busca e pesquisa",
            "chat.attach": "Anexar",
            "chat.stop": "Parar",
            "chat.send": "Enviar",
            "find.name": "Genesi Find",
            "find.searching": "procurando nos seus arquivos…",
            "find.none": "Nada bateu com essa descrição.",
            "find.count": "arquivo(s) encontrado(s)",
            "find.open": "Abrir",
            "find.reveal": "Mostrar na pasta",
            "find.copy": "Copiar caminho",
            "find.copied": "Caminho copiado",
            "find.placeholder": "Descreva o arquivo que você procura…",
            "find.on": "Genesi Find ligado — sua próxima mensagem busca nos seus arquivos.",
            // models / advisor page
            "adv.title": "Qual modelo cabe no seu hardware",
            "adv.reload": "Recarregar",
            "adv.empty": "Nada a relatar ainda. O Genesi olha sua GPU, sua RAM e os modelos que você tem, e diz quais realmente cabem.",
            "adv.placeholder": "ex.: llama3.2:3b   ou   llama3.1:8b",
            "adv.download": "Baixar",
            "adv.downloading": "Baixando…",
            "adv.startingPre": "iniciando download de ",
            // ── biblioteca GGUF local ──
            "gguf.title": "Modelos GGUF locais",
            "gguf.subtitle": "Use qualquer .gguf desta máquina — um download do "
                + "Hugging Face funciona direto, sem importar para o Ollama. "
                + "Arraste um arquivo para esta janela, escolha um, ou cole um "
                + "link direto.",
            "gguf.addFile": "Adicionar GGUF",
            "gguf.add": "Adicionar",
            "gguf.adding": "Adicionando…",
            "gguf.added": "Adicionado",
            "gguf.urlPlaceholder": "…ou cole um link .gguf direto",
            "gguf.pick": "Escolha um modelo GGUF",
            "gguf.drop": "Solte o .gguf aqui",
            "gguf.openFolder": "Abrir a pasta de modelos",
            "gguf.rescan": "Procurar arquivos GGUF de novo",
            "gguf.remove": "Remover da biblioteca",
            "gguf.use": "Usar com o Turbo",
            "gguf.inUse": "Em uso",
            "gguf.empty": "Nenhum arquivo GGUF encontrado ainda. Adicione um "
                + "acima, ou coloque na pasta Downloads e clique em procurar.",
            "gguf.fitGpu": "CABE NA GPU",
            "gguf.fitMoe": "OFFLOAD MoE",
            "gguf.fitSpill": "LENTO",
            "gguf.fitCpu": "CPU",
            // dialogs + tooltips
            "dlg.backendTitle": "Instalar o backend do Turbo",
            "dlg.backendIntro": "Escolha o motor de inferência do Turbo (llama-server).",
            "dlg.recommended": "Recomendado",
            "dlg.vulkanDesc": "Universal: roda em qualquer GPU (AMD, Intel, NVIDIA open/NVK). É o backend pronto do Genesi (genesi-llama-cpp, leve, ~dezenas de MB). Melhor opção pra maioria e pra ISO live.",
            "dlg.cudaDesc": "Só NVIDIA, com o driver proprietário ativo. ~1,5–2× mais rápido que o Vulkan, mas é um build pesado do AUR (llama.cpp-cuda, puxa o CUDA). Melhor num sistema instalado, não na ISO live em RAM.",
            "dlg.cudaWarn": "⚠ o nvidia-smi não está respondendo aqui — instale o driver NVIDIA proprietário primeiro, senão o CUDA não roda.",
            "dlg.aurNeed": "Precisa de um helper do AUR (paru/yay) instalado.",
            "dlg.turboTitle": "Qual modelo pro Turbo?",
            "dlg.turboPick": "Escolha o modelo que o Turbo vai servir. Ele fica nesse até você desligar o Turbo ou escolher outro.",
            "dlg.turboNone": "Nenhum modelo local encontrado. Baixe um primeiro (página Chat) ou rode: ollama pull llama3.2",
            "dlg.fitsGpu": "cabe na sua GPU",
            "dlg.startTurbo": "Iniciar o Turbo nesse modelo",
            "tip.recVram": "Use o maior modelo que roda 100% na sua VRAM (offload total, sem cair pra CPU)",
            // API Inspector
            "insp.httpsHelp": "HTTPS não descriptografando?",
            "insp.trustCert": "Confiar no cert HTTPS",
            "insp.caTrusted": "✓ CA confiável",
            "insp.openBrowser": "Abrir navegador",
            "insp.openBrowserTip": "Abre um navegador pré-configurado já apontado pro inspector (sem mexer no proxy do sistema)",
            // Sandboxes
            "sb.newWorkspace": "Novo workspace",
            "sb.removeWorkspace": "Remover workspace",
            "sb.distroboxMissing": "O Distrobox não está instalado",
            "sb.noBackend": "Nenhum backend de container encontrado",
            "sb.dockerNotRunning": "O Docker está instalado mas não está rodando",
            "sb.dockerNoPerm": "Seu usuário ainda não consegue falar com o Docker",
            "sb.all": "Todos os workspaces",
            "sb.running": "Rodando",
            "sb.stopped": "Parados",
            // Snapshots ("OS indestrutível")
            "snap.subtitle": "Seu sistema, à prova de falhas",
            "snap.refresh": "Atualizar",
            "snap.create": "Criar snapshot",
            "snap.baseline": "Marco Genesi",
            "snap.beforeUpdate": "Antes do update",
            "snap.afterUpdate": "Depois do update",
            "snap.manual": "Snapshot manual",
            "snap.stProtected": "Protegido",
            "snap.stProtectedSub": "Um ponto de restauração é criado automaticamente antes de cada update. Se algum boot quebrar, escolha um snapshot no menu do GRUB pra voltar.",
            "snap.stArming": "Configurando proteção…",
            "snap.stArmingSub": "O Genesi está configurando os snapshots neste sistema Btrfs. Termina no próximo boot.",
            "snap.stUnavailable": "Indisponível",
            "snap.stUnavailableSub": "Snapshots precisam de uma raiz Btrfs. Esta instalação não está em Btrfs, então a proteção está desligada.",
            "snap.capUpdate": "Auto antes dos updates",
            "snap.capBoot": "Recuperação no boot",
            "snap.capPoints": "pontos de restauração",
            "snap.noBtrfsTitle": "A raiz não é Btrfs",
            "snap.noBtrfsBody": "O sistema de snapshots precisa de uma raiz Btrfs. Reinstale o Genesi com o layout Btrfs padrão pra habilitar.",
            "snap.armingTitle": "Finalizando a configuração",
            "snap.armingBody": "Os snapshots estão sendo configurados. Reinicie uma vez e a proteção fica totalmente ativa.",
            "snap.timeline": "PONTOS DE RESTAURAÇÃO",
            "snap.empty": "Nenhum snapshot ainda — um vai aparecer antes do próximo update, ou crie um agora.",
            "snap.restore": "Restaurar",
            "snap.restoreTip": "Faz deste snapshot o sistema que você inicia (reinicie pra aplicar)",
            "snap.delete": "Apagar snapshot",
            "snap.createTitle": "Criar um snapshot",
            "snap.createPlaceholder": "O que você vai mudar? (opcional)",
            "snap.cancel": "Cancelar",
            "snap.rollbackTitle": "Voltar para",
            "snap.rollbackBody": "O Genesi vai tornar este snapshot o sistema padrão e reiniciar nele. Seu estado atual é salvo antes, então dá pra desfazer. Nada é apagado.",
            "snap.rollbackConfirm": "Voltar & reiniciar",
            // modo recuperação (iniciou um snapshot só-leitura pelo menu do GRUB)
            "rec.title": "Você está no Modo de Recuperação",
            "rec.body": "Você escolheu um snapshot antigo no menu do GRUB, então o sistema está rodando só-leitura — nada que você mudar aqui é salvo. Se este snapshot funciona bem, restaure ele pra virar de novo o seu sistema normal e gravável, e depois reinicie.",
            "rec.snapshot": "Snapshot iniciado",
            "rec.restore": "Restaurar este sistema",
            "rec.restoreTip": "Torna este snapshot o seu sistema definitivo e gravável. Seu sistema atual é guardado como backup — nada é apagado.",
            "rec.reboot": "Reiniciar",
            "rec.confirmTitle": "Restaurar este snapshot?",
            "rec.confirmBody": "O Genesi vai tornar o snapshot que você iniciou o seu sistema normal. Seu sistema atual é guardado como backup de um clique, e nada é apagado. Quando terminar, reinicie pra usar o sistema restaurado.",
            "rec.confirmBtn": "Restaurar este sistema",
            "rec.actionsLocked": "Só-leitura agora — restaure este sistema primeiro (acima) pra voltar a gerenciar os snapshots.",
            // genesi-find — descrever o arquivo em vez de saber o nome
            "find.title": "Encontrar um arquivo",
            "find.placeholder": "Descreva o arquivo — \"o pdf do contrato do mês passado\"",
            "find.search": "Buscar",
            "find.searching": "Buscando…",
            "find.scope": "em",
            "find.empty": "Nada corresponde a essa descrição.",
            "find.hint": "Descreva do jeito que você descreveria pra uma pessoa. Palavras que estão no nome ajudam mais.",
            "find.open": "Abrir",
            "find.reveal": "Mostrar na pasta",
            "find.copyPath": "Copiar caminho",
            "find.results": "resultados",
            "find.byModel": "refinado pelo modelo local",
            "find.byParser": "parser interno — nenhum modelo quente",
            "find.filter": "filtro"
        }
    })
}
