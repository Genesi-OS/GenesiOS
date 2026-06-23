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
            // models / advisor page
            "adv.title": "Which model fits your hardware",
            "adv.reload": "Reload",
            "adv.placeholder": "e.g. llama3.2:3b   or   llama3.1:8b",
            "adv.download": "Download",
            "adv.downloading": "Downloading…",
            "adv.startingPre": "starting download of ",
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
            "sb.stopped": "Stopped"
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
            // models / advisor page
            "adv.title": "Qual modelo cabe no seu hardware",
            "adv.reload": "Recarregar",
            "adv.placeholder": "ex.: llama3.2:3b   ou   llama3.1:8b",
            "adv.download": "Baixar",
            "adv.downloading": "Baixando…",
            "adv.startingPre": "iniciando download de ",
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
            "sb.stopped": "Parados"
        }
    })
}
