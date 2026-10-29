/*
 * Genesi Migrate — the window someone opens on the Linux they are leaving.
 *
 * Six steps down a rail: welcome → scan → apps → files → settings → ready.
 * Nothing on the machine changes until the last button, and in this build the
 * last button only writes the migration manifest (the reboot-into-installer
 * step comes next). The screen says so rather than pretending.
 *
 * Self-contained on purpose: this runs on Ubuntu/Fedora/openSUSE from an
 * AppImage, so no Kirigami, no shared Genesi kit (it imports Kirigami), no
 * shader effects (VMs fall back to the software renderer, where they draw
 * blank). The palette is the Genesi navy + emerald, fixed — there is no Genesi
 * colour scheme to follow on someone else's distro.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "icons.js" as Icons

ApplicationWindow {
    id: win
    // Sized to the screen, never past it. A fixed 1100x740 with a 920x640
    // minimum was cut off on an 800x600 VirtualBox guest (no Guest
    // Additions), and on small laptops: the third card and the right edge of
    // every page were off-screen, with no way to reach them.
    width: Math.min(1100, Screen.desktopAvailableWidth - 32)
    height: Math.min(740, Screen.desktopAvailableHeight - 32)
    minimumWidth: Math.min(640, Screen.desktopAvailableWidth)
    minimumHeight: Math.min(480, Screen.desktopAvailableHeight)
    // Below this the rail shrinks to its numbered dots and the pages use
    // smaller margins and type.
    readonly property bool compact: width < 960
    readonly property int pad: compact ? 20 : 40
    visible: true
    title: "Genesi Migrate"
    color: c.bg0

    // ── palette ─────────────────────────────────────────────────────────
    QtObject {
        id: c
        readonly property color bg0: "#040b17"
        readonly property color bg1: "#0a1220"
        readonly property color rail: "#070f1c"
        readonly property color card: "#0d1623"
        readonly property color cardHi: "#132036"
        readonly property color line: "#1b2740"
        readonly property color lineHi: "#27374f"
        readonly property color accent: "#1FBE6A"
        readonly property color accentHi: "#34D989"
        readonly property color mint: "#8BE8C8"
        readonly property color textHi: "#EAEEF2"
        readonly property color textMid: "#A3B0C2"
        readonly property color textLo: "#66768C"
        readonly property color blue: "#3AAFE0"
        readonly property color purple: "#C589DE"
        readonly property color orange: "#F0A548"
        readonly property color red: "#EF6A5A"
    }

    // ── language ────────────────────────────────────────────────────────
    // English first, always; Portuguese is one click away on the rail.
    property bool pt: forcedLang ? forcedLang.indexOf("pt") === 0 : false
    readonly property var dict: pt ? i18nPt : i18nEn
    function tr(k) { var v = dict[k]; return v === undefined ? (i18nEn[k] || k) : v }
    function trf(k, a, b) {
        var s = tr(k)
        if (a !== undefined) s = s.split("%1").join(a)
        if (b !== undefined) s = s.split("%2").join(b)
        return s
    }

    readonly property var i18nEn: ({
        "step.welcome": "Welcome", "step.scan": "Scan", "step.apps": "Apps",
        "step.files": "Files", "step.settings": "Settings", "step.ready": "Ready",
        "rail.safe": "Nothing on this computer changes until the last step.",
        "next": "Continue", "back": "Back",
        "w.eyebrow": "MOVE TO GENESI",
        "w.title": "Bring your whole Linux\nto Genesi.",
        "w.sub": "Your apps, files and settings, from %1 to Genesi. No starting over.",
        "w.f1.t": "Your apps", "w.f1.d": "We find the Genesi version of every app you use, native, AUR or Flathub.",
        "w.f2.t": "Your files", "w.f2.d": "Documents, photos, browser profiles and SSH keys come along.",
        "w.f3.t": "Your setup", "w.f3.d": "Language, keyboard, Wi-Fi and desktop arrive already configured.",
        "w.note": "The scan only reads. It doesn't install, delete or change anything.",
        "w.start": "Scan my system",
        "s.title": "Looking around your system…",
        "s.sub": "This takes a few seconds. Only reading, nothing is changed.",
        "s.system": "Distribution", "s.apps": "Installed apps", "s.flatpak": "Flatpaks, Snaps and tools",
        "s.files": "Your files", "s.machine": "Disks and boot", "s.settings": "Language, keyboard and Wi-Fi",
        "s.error": "The scan failed: %1",
        "s.retry": "Try again",
        "a.title": "Your apps",
        "a.sub": "%1 of %2 apps are coming to Genesi.",
        "a.all": "All", "a.attention": "Needs a check", "a.selectAll": "Select all", "a.selectNone": "Select none",
        "a.core": "%1 apps from your current desktop were left out: Genesi brings its own.",
        "a.empty": "Nothing here.",
        "t.pacman": "Genesi", "t.aur": "AUR", "t.flatpak": "Flathub", "t.likely": "We'll check", "t.search": "Search Flathub",
        "src.dpkg": "APT", "src.rpm": "RPM", "src.pacman": "pacman", "src.flatpak": "Flatpak",
        "src.snap": "Snap", "src.cli": "Terminal", "src.system": "System", "src.xbps-query": "XBPS",
        "d.alongsideTitle": "Install next to %1 (dual boot)",
        "d.alongsideSub": "%1 shrinks to make room. You pick which one to start every time the PC boots.",
        "d.alongside": "Genesi gets its own partition next to %1. Nothing is erased; the PC asks which system to start.",
        "d.alongsideShort": "next to %1, %2",
        "d.alongsideNo.fs": "Only possible when the system partition is ext4 or btrfs.",
        "d.alongsideNo.layout": "Not possible with an encrypted or LVM system partition.",
        "d.alongsideNo.space": "Not enough free space: Genesi needs 30 GB and the current system keeps 10 GB of room.",
        "d.alongsideNo.unknown": "We couldn't measure the system partition.",
        "d.keeps": "%1 keeps %2",
        "d.gets": "Genesi gets %1",
        "p.space": "Check the free space",
        "p.download": "Download Genesi",
        "p.verify": "Check the download (SHA-256)",
        "p.files": "Copy your files to the external drive",
        "p.arm": "Prepare the restart (asks for your password)",
        "p.build": "Build and verify your Genesi system (requires administrator access)",
        "r.nativeReady": "Genesi is prepared. Restart to run automatic offline maintenance, preserve your home files and switch to Btrfs. The PC then restarts into Genesi. No graphical installer is involved.",
        "p.cancel": "Cancel",
        "p.later": "Not now",
        "p.retry": "Try again",
        "p.reboot": "Restart and migrate",
        "r.readyTitle": "Ready to restart",
        "r.readyText": "When the PC restarts it opens the Genesi installer, already filled in with your choices. Only Genesi Migrate's entry is used, once; nothing else in your boot menu changes.",
        "r.readyTextRam": "When the PC restarts it loads Genesi into memory (a minute or two), then opens the installer already filled in with your choices.",
        "st.extGone": "The external drive isn't mounted any more. Plug it in, open it in the file manager and try again.",
        "st.noUuid": "We couldn't identify the partition that would hold the download.",
        "st.fs": "The partition that would hold the download uses %1, which the boot menu can't read.",
        "st.ram": "This needs to load Genesi into memory, which takes 7 GB of RAM (this PC has %1 GB). Pick an external drive for your files, or install from a USB stick.",
        "st.space": "Not enough free space: %1 needed, %2 free.",
        "st.sha": "The download didn't match its checksum, so it was deleted. Try again.",
        "st.short": "The download was cut short. Try again: it resumes where it stopped.",
        "st.net": "No connection to the download server (%1).",
        "st.auth": "The password prompt was closed. Nothing was changed.",
        "st.helper": "Preparing the restart failed: %1",
        "st.cancelled": "Cancelled. What was downloaded is kept, so trying again resumes.",
        "st.other": "Something went wrong: %1",
        "warn.secureBoot": "Secure Boot is on. Restarting straight into the installer needs it off: turn it off in the firmware (BIOS) settings, or install from a USB stick.",
        "step.disk": "Disk",
        "d.title": "Where Genesi goes",
        "d.sub": "Pick the disk. Nothing is erased now: the installer still asks one last time.",
        "d.replace": "Migrate %1 to Genesi on %2. Keep your home files; convert ext4 to Btrfs during offline maintenance. Requires UEFI and a supported disk layout.",
        "d.replaceShort": "replacing %1",
        "d.whole": "Use the whole disk for Genesi. Everything on it will be erased.",
        "d.wholeExternal": "Use the whole external disk. Genesi boots straight from it: great for trying it without touching this PC.",
        "d.tagSystem": "Current system", "d.tagExternal": "External",
        "d.empty": "Empty disk",
        "d.none": "We couldn't list the disks here. The installer will ask which one to use.",
        "d.homeHere": "Your personal folder is on this disk. Installing here erases it, so your files need an external drive.",
        "d.confirm": "I understand: everything on %1 (%2) will be erased.",
        "d.safety": "Windows and other partitions are never touched unless you pick their whole disk.",
        "f.stay": "They stay where they are",
        "f.stay.d": "Your files remain on the %2 disk. Native migration preserves the entire home; another-disk installations copy your selected files.",
        "r.target": "Genesi goes to",
        "r.dest.stay": "the old disk, where they already are",
        "f.title": "Your files",
        "f.sub": "Pick what comes with you.",
        "f.total": "%1 selected",
        "f.hiddenTitle": "Behind the scenes",
        "documents": "Documents", "pictures": "Pictures", "music": "Music", "videos": "Videos",
        "downloads": "Downloads", "desktop": "Desktop", "other": "Other folders",
        "browsers": "Browsers", "keys": "SSH & GPG keys", "appconfig": "App settings", "steam": "Steam games",
        "browsers.d": "Bookmarks, logins, extensions", "keys.d": "Your access to servers and Git",
        "appconfig.d": "Each app's preferences", "steam.d": "Steam can download them again",
        "f.whereTitle": "Where your files wait during the switch",
        "f.whereSub": "Installing Genesi formats the system partition. Your files need somewhere safe for those minutes.",
        "f.whereSubStay": "Your personal files remain preserved during migration. Native migration keeps the entire /home, including folders not selected above.",
        "f.keepHome": "Keep my /home partition",
        "f.keepHome.d": "It's already separate (%1). Genesi only formats the system partition.",
        "f.external": "External drive: %1",
        "f.external.d": "%1 free · we'll copy %2",
        "f.external.small": "Only %1 free — needs %2",
        "f.external.unmounted": "Open the drive in your file manager so we can measure it",
        "f.none": "Don't keep files",
        "f.none.d": "Only apps and settings come along. Your files will be erased.",
        "f.noExternal": "To keep your files, plug in an external drive or USB stick with %1 free.",
        "f.orAlongside": "Or go back to Disk and pick \"Install next to\": your current system stays, and so do your files.",
        "f.orOtherDisk": "Or go back to Disk and install Genesi on your other disk: your files stay where they are.",
        "f.rescan": "Look again",
        "e.title": "Your setup",
        "e.sub": "Genesi will start with these, so the installer doesn't ask again.",
        "e.lang": "Language", "e.kb": "Keyboard", "e.tz": "Time zone", "e.user": "User",
        "e.wifi": "Wi-Fi networks", "e.wifiNone": "No saved networks", "e.wifiN": "%1 saved",
        "e.bringWifi": "Bring my Wi-Fi networks",
        "e.desktop": "Desktop",
        "e.desktopNow": "You use %1 today. We picked the closest Genesi desktop.",
        "e.desktopUnknown": "We picked Plasma, the Genesi default.",
        "r.title": "Ready to move",
        "r.sub": "Here's the plan. Check it once more.",
        "r.apps": "apps", "r.files": "of files", "r.settings": "settings", "r.dest": "Files wait on",
        "r.dest.keep": "your /home partition", "r.dest.none": "nowhere — not kept",
        "r.how": "What happens when you click",
        "r.h1": "We save the migration plan", "r.h2": "We download Genesi and verify its SHA-256",
        "r.h3": "Restart to complete the migration", "r.h4": "Start Genesi with your apps and files",
        "r.soon": "next update",
        "r.go": "Prepare migration",
        "r.blocked": "Migration can't continue on this computer yet.",
        "r.savedTitle": "Plan saved",
        "r.savedText": "Everything you chose is in %1. The next step, restarting straight into the Genesi installer, arrives in the next update of Genesi Migrate.",
        "r.open": "Open folder",
        "r.saveFail": "Couldn't save the plan: %1",
        "warn.luks": "Your disk is encrypted (LUKS). Automatic migration doesn't support encrypted disks yet, for now install from a USB stick.",
        "warn.windows": "We found a Windows partition. It won't be touched, but double-check the disk choice in the installer.",
        "warn.bootloader": "Your system doesn't boot with GRUB (%1). Restarting into the installer may need a USB stick.",
        "warn.bootloaderUnknown": "We couldn't tell how this computer boots. Restarting into the installer may need a USB stick.",
        "warn.needDest": "Pick where your files wait during the switch.",
        "demo": "DEMO DATA"
    })
    readonly property var i18nPt: ({
        "step.welcome": "Boas-vindas", "step.scan": "Análise", "step.apps": "Apps",
        "step.files": "Arquivos", "step.settings": "Ajustes", "step.ready": "Pronto",
        "rail.safe": "Nada muda neste computador até a última etapa.",
        "next": "Continuar", "back": "Voltar",
        "w.eyebrow": "VENHA PARA O GENESI",
        "w.title": "Traga seu Linux inteiro\npara o Genesi.",
        "w.sub": "Seus apps, arquivos e configurações, do %1 para o Genesi. Sem recomeçar do zero.",
        "w.f1.t": "Seus apps", "w.f1.d": "Achamos a versão Genesi de cada app que você usa: nativa, AUR ou Flathub.",
        "w.f2.t": "Seus arquivos", "w.f2.d": "Documentos, fotos, perfis do navegador e chaves SSH vêm junto.",
        "w.f3.t": "Suas configurações", "w.f3.d": "Idioma, teclado, Wi-Fi e área de trabalho já chegam configurados.",
        "w.note": "A análise só lê. Não instala, não apaga e não muda nada.",
        "w.start": "Analisar meu sistema",
        "s.title": "Conhecendo seu sistema…",
        "s.sub": "Leva alguns segundos. Só leitura, nada é alterado.",
        "s.system": "Distribuição", "s.apps": "Apps instalados", "s.flatpak": "Flatpaks, Snaps e ferramentas",
        "s.files": "Seus arquivos", "s.machine": "Discos e boot", "s.settings": "Idioma, teclado e Wi-Fi",
        "s.error": "A análise falhou: %1",
        "s.retry": "Tentar de novo",
        "a.title": "Seus apps",
        "a.sub": "%1 de %2 apps vão com você para o Genesi.",
        "a.all": "Todos", "a.attention": "Precisam de checagem", "a.selectAll": "Marcar todos", "a.selectNone": "Desmarcar todos",
        "a.core": "%1 apps do seu desktop atual ficaram de fora: o Genesi traz os dele.",
        "a.empty": "Nada por aqui.",
        "t.pacman": "Genesi", "t.aur": "AUR", "t.flatpak": "Flathub", "t.likely": "Vamos conferir", "t.search": "Buscar no Flathub",
        "src.system": "Sistema", "src.cli": "Terminal",
        "d.alongsideTitle": "Instalar ao lado do %1 (dual boot)",
        "d.alongsideSub": "O %1 encolhe para abrir espaço. Você escolhe qual iniciar toda vez que liga o PC.",
        "d.alongside": "O Genesi ganha uma partição própria ao lado do %1. Nada é apagado; o PC pergunta qual sistema iniciar.",
        "d.alongsideShort": "ao lado do %1, %2",
        "d.alongsideNo.fs": "Só é possível quando a partição do sistema é ext4 ou btrfs.",
        "d.alongsideNo.layout": "Não é possível com a partição do sistema criptografada ou em LVM.",
        "d.alongsideNo.space": "Espaço livre insuficiente: o Genesi precisa de 30 GB e o sistema atual fica com 10 GB de folga.",
        "d.alongsideNo.unknown": "Não conseguimos medir a partição do sistema.",
        "d.keeps": "%1 fica com %2",
        "d.gets": "Genesi fica com %1",
        "p.space": "Conferir o espaço livre",
        "p.download": "Baixar o Genesi",
        "p.verify": "Conferir o download (SHA-256)",
        "p.files": "Copiar seus arquivos para o disco externo",
        "p.arm": "Preparar o reinício (pede sua senha)",
        "p.build": "Montar e verificar seu Genesi (requer acesso de administrador)",
        "r.nativeReady": "O Genesi esta preparado. Reinicie para a manutencao automatica preservar seus arquivos e concluir a mudanca para Btrfs. Depois o PC reinicia no Genesi, sem instalador grafico.",
        "p.cancel": "Cancelar",
        "p.later": "Agora não",
        "p.retry": "Tentar de novo",
        "p.reboot": "Reiniciar e migrar",
        "r.readyTitle": "Pronto para reiniciar",
        "r.readyText": "Quando o PC reiniciar, ele abre o instalador do Genesi já preenchido com suas escolhas. A entrada do Genesi Migrate é usada uma vez só; nada mais no seu menu de boot muda.",
        "r.readyTextRam": "Quando o PC reiniciar, ele carrega o Genesi na memória (um ou dois minutos) e abre o instalador já preenchido com suas escolhas.",
        "st.extGone": "O disco externo não está mais montado. Conecte, abra no gerenciador de arquivos e tente de novo.",
        "st.noUuid": "Não conseguimos identificar a partição que guardaria o download.",
        "st.fs": "A partição que guardaria o download usa %1, que o menu de boot não consegue ler.",
        "st.ram": "Isso precisa carregar o Genesi na memória, o que pede 7 GB de RAM (este PC tem %1 GB). Escolha um disco externo para seus arquivos ou instale pelo pendrive.",
        "st.space": "Espaço livre insuficiente: precisa de %1, tem %2.",
        "st.sha": "O download não bateu com o checksum e foi apagado. Tente de novo.",
        "st.short": "O download foi interrompido. Tente de novo: ele continua de onde parou.",
        "st.net": "Sem conexão com o servidor de download (%1).",
        "st.auth": "A janela de senha foi fechada. Nada foi alterado.",
        "st.helper": "Preparar o reinício falhou: %1",
        "st.cancelled": "Cancelado. O que já foi baixado fica guardado, então tentar de novo continua de onde parou.",
        "st.other": "Algo deu errado: %1",
        "warn.secureBoot": "O Secure Boot está ligado. Reiniciar direto no instalador precisa dele desligado: desligue nas configurações da BIOS ou instale pelo pendrive.",
        "step.disk": "Disco",
        "d.title": "Onde instalar o Genesi",
        "d.sub": "Escolha o disco. Nada é apagado agora: o instalador ainda pede uma última confirmação.",
        "d.replace": "Migrar o %1 para Genesi em %2. Seus arquivos pessoais ficam; ext4 sera convertido para Btrfs na manutencao offline. Requer UEFI e layout suportado.",
        "d.replaceShort": "no lugar do %1",
        "d.whole": "Usar o disco inteiro para o Genesi. Tudo que está nele será apagado.",
        "d.wholeExternal": "Usar o disco externo inteiro. O Genesi inicia direto dele: ótimo para testar sem mexer neste PC.",
        "d.tagSystem": "Sistema atual", "d.tagExternal": "Externo",
        "d.empty": "Disco vazio",
        "d.none": "Não conseguimos listar os discos aqui. O instalador vai perguntar qual usar.",
        "d.homeHere": "Sua pasta pessoal está neste disco. Instalar aqui apaga ela, então seus arquivos precisam de um HD externo.",
        "d.confirm": "Entendi: tudo em %1 (%2) será apagado.",
        "d.safety": "O Windows e outras partições nunca são tocados, a não ser que você escolha o disco inteiro deles.",
        "f.stay": "Ficam onde estão",
        "f.stay.d": "Seus arquivos continuam no disco do %2. A migracao nativa preserva todo o home; em outro disco, copia os arquivos selecionados.",
        "r.target": "Genesi vai para",
        "r.dest.stay": "o disco antigo, onde já estão",
        "f.title": "Seus arquivos",
        "f.sub": "Escolha o que vem com você.",
        "f.total": "%1 selecionados",
        "f.hiddenTitle": "Por trás dos panos",
        "documents": "Documentos", "pictures": "Imagens", "music": "Músicas", "videos": "Vídeos",
        "downloads": "Downloads", "desktop": "Área de trabalho", "other": "Outras pastas",
        "browsers": "Navegadores", "keys": "Chaves SSH e GPG", "appconfig": "Configurações dos apps", "steam": "Jogos da Steam",
        "browsers.d": "Favoritos, logins, extensões", "keys.d": "Seu acesso a servidores e ao Git",
        "appconfig.d": "As preferências de cada app", "steam.d": "A Steam baixa de novo",
        "f.whereTitle": "Onde seus arquivos esperam durante a troca",
        "f.whereSub": "Instalar o Genesi formata a partição do sistema. Seus arquivos precisam de um lugar seguro nesses minutos.",
        "f.whereSubStay": "Seus arquivos pessoais ficam preservados. A migracao nativa mantem todo o /home, inclusive pastas nao selecionadas acima.",
        "f.keepHome": "Manter minha partição /home",
        "f.keepHome.d": "Ela já é separada (%1). O Genesi só formata a partição do sistema.",
        "f.external": "Disco externo: %1",
        "f.external.d": "%1 livres · vamos copiar %2",
        "f.external.small": "Só %1 livres — precisa de %2",
        "f.external.unmounted": "Abra o disco no gerenciador de arquivos para medirmos o espaço",
        "f.none": "Não manter arquivos",
        "f.none.d": "Só apps e configurações vêm junto. Seus arquivos serão apagados.",
        "f.noExternal": "Para manter seus arquivos, conecte um HD externo ou pendrive com %1 livres.",
        "f.orAlongside": "Ou volte para Disco e escolha \"Instalar ao lado\": seu sistema atual continua, e seus arquivos também.",
        "f.orOtherDisk": "Ou volte para Disco e instale o Genesi no seu outro disco: seus arquivos ficam onde estão.",
        "f.rescan": "Procurar de novo",
        "e.title": "Suas configurações",
        "e.sub": "O Genesi já começa assim, e o instalador não pergunta de novo.",
        "e.lang": "Idioma", "e.kb": "Teclado", "e.tz": "Fuso horário", "e.user": "Usuário",
        "e.wifi": "Redes Wi-Fi", "e.wifiNone": "Nenhuma rede salva", "e.wifiN": "%1 salvas",
        "e.bringWifi": "Trazer minhas redes Wi-Fi",
        "e.desktop": "Área de trabalho",
        "e.desktopNow": "Hoje você usa %1. Escolhemos o desktop do Genesi mais parecido.",
        "e.desktopUnknown": "Escolhemos o Plasma, o padrão do Genesi.",
        "r.title": "Pronto para a mudança",
        "r.sub": "Este é o plano. Dá uma última conferida.",
        "r.apps": "apps", "r.files": "de arquivos", "r.settings": "ajustes", "r.dest": "Arquivos esperam em",
        "r.dest.keep": "sua partição /home", "r.dest.none": "lugar nenhum — não serão mantidos",
        "r.how": "O que acontece quando você clicar",
        "r.h1": "Salvamos o plano de migração", "r.h2": "Baixamos o Genesi e verificamos o SHA-256",
        "r.h3": "Reinicie para concluir a migracao", "r.h4": "Inicie o Genesi com seus apps e arquivos",
        "r.soon": "próxima versão",
        "r.go": "Preparar migração",
        "r.blocked": "A migração ainda não pode continuar neste computador.",
        "r.savedTitle": "Plano salvo",
        "r.savedText": "Tudo o que você escolheu está em %1. A próxima etapa, reiniciar direto no instalador do Genesi, chega na próxima versão do Genesi Migrate.",
        "r.open": "Abrir pasta",
        "r.saveFail": "Não deu para salvar o plano: %1",
        "warn.luks": "Seu disco é criptografado (LUKS). A migração automática ainda não suporta discos criptografados, por enquanto instale pelo pendrive.",
        "warn.windows": "Encontramos uma partição do Windows. Ela não será tocada, mas confira a escolha de disco no instalador.",
        "warn.bootloader": "Seu sistema não inicia pelo GRUB (%1). Reiniciar no instalador pode precisar de um pendrive.",
        "warn.bootloaderUnknown": "Não identificamos como este computador inicia. Reiniciar no instalador pode precisar de um pendrive.",
        "warn.needDest": "Escolha onde seus arquivos esperam durante a troca.",
        "demo": "DADOS DE DEMONSTRAÇÃO"
    })

    // ── state ───────────────────────────────────────────────────────────
    property int page: 0
    property int reached: 0              // furthest step reached (rail clicks)
    property var manifest: null
    property string scanError: ""
    property var stagesDone: ({})
    property string stageNow: ""
    property real scanFrac: 0
    property int rev: 0                  // bumped on every checkbox change
    property string appFilter: "all"
    property string strategy: ""         // "stay" | "keep-home" | "external:/dev/x" | "none"
    property string installTarget: "replace"  // "replace" (today's system partition) | "disk:/dev/x" (whole disk)
    property bool wipeConfirmed: false   // a whole-disk target needs an explicit "I understand"
    property real genesiBytes: 0         // v2 "alongside": the size Genesi gets
    // prepare
    property string prepState: ""        // "" | running | done | failed
    property var prepFrac: ({})          // step id -> 0..1
    property var prepDetail: ({})        // step id -> "1.2 / 3.4 GB · 20 MB/s"
    property string prepError: ""
    property bool prepRam: false
    property string desktopId: "KDE-Desktop"
    property bool bringWifi: true
    property string savedPath: ""
    property string saveError: ""
    readonly property var desktops: JSON.parse(backend.desktopsJson)

    onPageChanged: if (page > reached) reached = page

    ListModel { id: appsModel }
    ListModel { id: filesModel }

    function fmt(b) {
        if (b === null || b === undefined) return "?"
        var u = ["B", "KB", "MB", "GB", "TB"], i = 0, v = b
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        var s = (i >= 3 ? v.toFixed(v < 10 ? 1 : 0) : Math.round(v).toString())
        return (pt ? s.replace(".", ",") : s) + " " + u[i]
    }

    function load(m) {
        manifest = m
        appsModel.clear()
        for (var i = 0; i < m.apps.length; i++) {
            var a = m.apps[i]
            appsModel.append({ aid: a.id, name: (pt && a.namePt) ? a.namePt : a.name,
                               icon: a.icon || "", source: a.source, pkg: a.package || "",
                               kind: a.kind || "", target: a.target || "",
                               confidence: a.confidence, sel: a.selected })
        }
        filesModel.clear()
        for (var j = 0; j < m.files.length; j++) {
            var f = m.files[j]
            filesModel.append({ fid: f.id, group: f.group, bytes: f.bytes, estimate: !!f.estimate,
                                sel: f.selected, extra: (f.names || []).join(", ") })
        }
        desktopId = m.settings.genesiDesktop || "KDE-Desktop"
        bringWifi = (m.settings.wifi || []).length > 0
        installTarget = "replace"
        wipeConfirmed = false
        pickDefaultStrategy()
        rev++
    }

    function selectedApps() { var _ = rev, n = 0; for (var i = 0; i < appsModel.count; i++) if (appsModel.get(i).sel) n++; return n }
    function selectedBytes() { var _ = rev, n = 0; for (var i = 0; i < filesModel.count; i++) if (filesModel.get(i).sel) n += filesModel.get(i).bytes; return n }
    function attentionCount() { var _ = rev, n = 0; for (var i = 0; i < appsModel.count; i++) if (appsModel.get(i).confidence === "likely") n++; return n }
    function setAllApps(v) {
        for (var i = 0; i < appsModel.count; i++)
            if (appFilter === "all" || appsModel.get(i).confidence === "likely") appsModel.setProperty(i, "sel", v)
        rev++
    }

    // ── where Genesi goes, and where the files wait ──────────────────
    function disks() { var _ = rev; return manifest && manifest.machine.disks ? manifest.machine.disks : [] }
    function systemDisk() { var d = disks(); for (var i = 0; i < d.length; i++) if (d[i].system) return d[i]; return null }
    function alongsideInfo() { var _ = rev; return manifest && manifest.plan.alongside ? manifest.plan.alongside : { ok: false, why: "unknown", min: 0, max: 0 } }
    function onSystem() { return installTarget === "replace" || installTarget === "alongside" }
    function targetDisk() {
        if (onSystem()) return systemDisk()
        var d = disks(), dev = installTarget.slice(5)
        for (var i = 0; i < d.length; i++) if (d[i].device === dev) return d[i]
        return null
    }
    function onTarget(device) {
        // a partition is on the target disk when that disk lists it -- not a
        // prefix test, which takes /dev/nvme0n10 for part of /dev/nvme0n1
        var t = targetDisk()
        if (onSystem() || !t) return false
        if (t.device === device) return true
        for (var i = 0; i < t.partitions.length; i++) if (t.partitions[i].device === device) return true
        return false
    }
    // Genesi on another disk (or next to the old system, which keeps its
    // partition) and today's files are not erased: nothing to move.
    function stayAvailable() {
        if (installTarget === "replace") return true
        if (installTarget === "alongside") return true
        var t = targetDisk()
        return !onSystem() && t !== null && !t.system && !t.home
    }
    function strategies() {
        var _ = rev, out = []
        if (!manifest) return out
        var ss = manifest.plan.strategies
        for (var i = 0; i < ss.length; i++) {
            // keep-home is "format only the system partition": replace only
            if (ss[i].id === "keep-home" && installTarget !== "replace") continue
            if (ss[i].id === "external" && onTarget(ss[i].device)) continue
            out.push(ss[i])
        }
        return out
    }
    function externalOk(s) { return s.free !== null && s.free !== undefined && s.free >= selectedBytes() * 1.05 }
    function pickDefaultStrategy() {
        if (stayAvailable()) { strategy = "stay"; return }
        var ss = strategies()
        for (var i = 0; i < ss.length; i++)
            if (ss[i].id === "keep-home") { strategy = "keep-home"; return }
        for (var k = 0; k < ss.length; k++)
            if (ss[k].id === "external" && externalOk(ss[k])) { strategy = "external:" + ss[k].device; return }
        strategy = ""
    }
    function strategyValid() {
        var _ = rev
        if (strategy === "none") return true
        if (strategy === "stay") return stayAvailable()
        var ss = strategies()
        for (var i = 0; i < ss.length; i++) {
            if (strategy === "keep-home" && ss[i].id === "keep-home") return true
            if (ss[i].id === "external" && "external:" + ss[i].device === strategy) return externalOk(ss[i])
        }
        return false
    }
    function otherDiskAvailable() {
        var d = disks()
        for (var i = 0; i < d.length; i++) if (!d[i].system && !d[i].home && !d[i].removable) return true
        return false
    }
    function chooseTarget(t) {
        installTarget = t
        wipeConfirmed = false
        if (t === "alongside") {
            var a = alongsideInfo()
            // half of what is free, rounded to 5 GiB, within the limits
            var g = 5 * 1073741824
            genesiBytes = Math.max(a.min, Math.min(a.max, Math.round(a.max / 2 / g) * g))
        }
        pickDefaultStrategy()
        rev++
    }
    function targetValid() {
        var _ = rev
        if (installTarget === "replace") return true
        if (installTarget === "alongside") { var a = alongsideInfo(); return a.ok && genesiBytes >= a.min && genesiBytes <= a.max }
        return targetDisk() !== null && wipeConfirmed
    }
    function targetLabel() {
        var t = targetDisk()
        if (installTarget === "replace")
            return trf("d.replaceShort", manifest ? manifest.os.name : "Linux") + (t ? "  ·  " + t.model : "")
        if (installTarget === "alongside")
            return trf("d.alongsideShort", manifest ? manifest.os.name : "Linux", fmt(genesiBytes)) + (t ? "  ·  " + t.model : "")
        return t ? t.model + "  (" + t.device + ")" : "—"
    }
    function partColor(p) {
        if (p.mountpoint === "/") return c.accent
        if (p.mountpoint === "/home" || (manifest && p.device === manifest.machine.homeDevice)) return c.blue
        if (p.fstype === "ntfs") return "#6C7BD9"
        if (p.fstype === "vfat") return c.orange
        if (p.fstype === "swap") return c.textLo
        return c.purple
    }
    function partName(p) {
        if (p.mountpoint === "/") return manifest ? manifest.os.name : "Linux"
        if (p.mountpoint === "/boot/efi" || p.mountpoint === "/efi" || (p.fstype === "vfat" && p.size < 2 * 1073741824)) return "EFI"
        if (p.label) return p.label
        if (p.mountpoint) return p.mountpoint
        return p.fstype || "?"
    }

    function warnings() {
        var _ = rev, out = []
        if (!manifest) return out
        var p = manifest.plan
        for (var i = 0; i < p.blockers.length; i++) {
            // an encrypted root only matters when it is the partition replaced
            if (p.blockers[i] === "luks" && !onSystem()) continue
            out.push({ blocker: true, key: p.blockers[i] })
        }
        for (var j = 0; j < p.warnings.length; j++) out.push({ blocker: false, key: p.warnings[j] })
        return out
    }
    function blocked() { var w = warnings(); for (var i = 0; i < w.length; i++) if (w[i].blocker) return true; return false }
    function warnText(k) {
        if (k === "bootloader")
            return manifest.machine.bootloader === "unknown" ? tr("warn.bootloaderUnknown")
                                                             : trf("warn.bootloader", manifest.machine.bootloader)
        return tr("warn." + k)
    }

    function buildManifest() {
        var m = JSON.parse(JSON.stringify(manifest))
        var selApps = {}, selFiles = {}
        for (var i = 0; i < appsModel.count; i++) selApps[appsModel.get(i).aid] = appsModel.get(i).sel
        for (var j = 0; j < filesModel.count; j++) selFiles[filesModel.get(j).fid] = filesModel.get(j).sel
        for (var a = 0; a < m.apps.length; a++) m.apps[a].selected = !!selApps[m.apps[a].id]
        for (var f = 0; f < m.files.length; f++) m.files[f].selected = !!selFiles[m.files[f].id]
        var t = targetDisk(), mc = manifest.machine
        // Device names can change order in the live system: the installer
        // finds the disk again by serial/WWN + size, partitions by UUID.
        var install = { mode: installTarget === "replace" ? "native" : installTarget === "alongside" ? "alongside" : "disk",
                        disk: t ? t.device : "", diskSerial: t ? (t.serial || "") : "", diskWwn: t ? (t.wwn || "") : "",
                        diskSize: t ? t.size : 0, rootUuid: mc.rootUuid || "", espUuid: mc.espUuid || "",
                        homeUuid: strategy === "keep-home" ? (mc.homeUuid || "") : "" }
        if (installTarget === "alongside") install.genesiBytes = genesiBytes
        m.choices = { strategy: strategy, desktop: desktopId, wifi: bringWifi,
                      install: install,
                      language: pt ? "pt_BR" : "en_US", selectedBytes: selectedBytes() }
        return JSON.stringify(m)
    }

    function prepSteps() {
        var _ = rev, out = ["space", "download", "verify"]
        if (installTarget === "replace") out.push("build")
        if (strategy.indexOf("external:") === 0) out.push("files")
        out.push("arm")
        return out
    }
    property string prepCurrent: ""
    onClosing: function(close) {
        if (prepState === "running" && installTarget === "replace" && (prepCurrent === "build" || prepCurrent === "arm")) close.accepted = false
    }
    function startPrepare() {
        var m = buildManifest()
        backend.saveManifest(m)
        prepFrac = ({}); prepDetail = ({}); prepError = ""
        prepState = "running"
        backend.prepare(m)
    }

    function canAdvance() {
        var _ = rev
        if (page === 1) return manifest !== null
        if (page === 3) return targetValid()
        if (page === 4) return strategyValid()
        return true
    }

    Connections {
        target: backend
        function onProgress(stage, frac) {
            var d = Object.assign({}, stagesDone)
            if (stageNow !== "") d[stageNow] = true
            stagesDone = d
            stageNow = stage
            scanFrac = frac
        }
        function onScanned(json) {
            var m = JSON.parse(json)
            if (m.error) { scanError = m.error; return }
            var d = Object.assign({}, stagesDone)
            d[stageNow] = true
            stagesDone = d
            load(m)
            advanceTimer.start()
        }
        function onMachineUpdated(json) {
            var r = JSON.parse(json)
            if (r.error) return
            var m = manifest
            m.machine = r.machine
            m.plan = r.plan
            manifest = m
            if (!strategyValid()) pickDefaultStrategy()
            rev++
        }
        function onPrepStep(step, frac, detail) {
            prepCurrent = step
            var f = Object.assign({}, prepFrac); f[step] = frac; prepFrac = f
            var d = Object.assign({}, prepDetail); d[step] = detail; prepDetail = d
        }
        function onPrepFailed(key, argsJson) {
            var a = JSON.parse(argsJson)
            prepError = key === "st.cancelled" ? tr("st.cancelled") : trf(key, a[0], a[1])
            prepState = "failed"
        }
        function onPrepDone(planJson) {
            prepRam = !!JSON.parse(planJson).copytoram
            prepState = "done"
        }
        function onSaved(ok, msg) {
            if (ok) { savedPath = msg; saveError = "" } else saveError = msg
        }
    }
    Timer { id: advanceTimer; interval: 700; onTriggered: if (win.page === 1) win.page = 2 }

    function startScan() {
        scanError = ""; stagesDone = ({}); stageNow = ""; scanFrac = 0; manifest = null
        page = 1
        backend.scan()
    }

    Component.onCompleted: if (startPage > 0) { startScan(); pendingPage = startPage }
    property int pendingPage: -1
    onManifestChanged: if (manifest && pendingPage > 1) { var p = pendingPage; pendingPage = -1; advanceTimer.stop(); page = p }

    // ── small building blocks ───────────────────────────────────────────
    // An Item around the Image, not an Image: layouts size children by their
    // implicit size, an Image's is its sourceSize (drawn at 2x here), and it
    // is read-only -- so the wrapper is what carries the real size.
    component Icon: Item {
        property string name: "box"
        property color tint: c.textHi
        property real stroke: 2
        property int size: 18
        implicitWidth: size; implicitHeight: size
        width: size; height: size
        Image {
            anchors.fill: parent
            sourceSize: Qt.size(parent.size * 2, parent.size * 2)
            smooth: true
            source: Icons.url(parent.name, parent.tint.toString(), parent.stroke)
        }
    }

    component Btn: Rectangle {
        id: b
        property string text: ""
        property string icon: ""
        property string iconRight: ""
        property bool primary: false
        property bool enabledState: true
        signal clicked()
        implicitHeight: 44
        implicitWidth: row.implicitWidth + 40
        radius: 12
        opacity: enabledState ? 1 : 0.45
        color: primary ? (ma.pressed ? Qt.darker(c.accent, 1.15) : ma.containsMouse && enabledState ? c.accentHi : c.accent)
                       : (ma.pressed ? c.line : ma.containsMouse && enabledState ? c.cardHi : "transparent")
        border.width: primary ? 0 : 1
        border.color: c.lineHi
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Icon { visible: b.icon !== ""; name: b.icon; tint: b.primary ? "#06210F" : c.textHi; size: 16 }
            Text { text: b.text; color: b.primary ? "#06210F" : c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold }
            Icon { visible: b.iconRight !== ""; name: b.iconRight; tint: b.primary ? "#06210F" : c.textHi; size: 16 }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: b.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (b.enabledState) b.clicked()
        }
    }

    component Check: Rectangle {
        property bool checked: false
        width: 22; height: 22; radius: 7
        color: checked ? c.accent : "transparent"
        border.width: checked ? 0 : 1.5
        border.color: c.lineHi
        Behavior on color { ColorAnimation { duration: 110 } }
        Icon { anchors.centerIn: parent; visible: parent.checked; name: "check"; tint: "#06210F"; stroke: 3; size: 14 }
    }

    component Radio: Rectangle {
        property bool checked: false
        width: 22; height: 22; radius: 11
        color: "transparent"
        border.width: 1.5
        border.color: checked ? c.accent : c.lineHi
        Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: c.accent; visible: parent.checked }
    }

    component Card: Rectangle {
        radius: 16
        color: c.card
        border.width: 1
        border.color: c.line
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(c.card, 1.12) }
            GradientStop { position: 1; color: c.card }
        }
    }

    component Pill: Rectangle {
        property string text: ""
        property color tone: c.accent
        implicitHeight: 24
        implicitWidth: pl.implicitWidth + 18
        radius: 12
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.14)
        border.width: 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.35)
        Text { id: pl; anchors.centerIn: parent; text: parent.text; color: parent.tone; font.pixelSize: 12; font.weight: Font.DemiBold }
    }

    component Banner: Rectangle {
        property string text: ""
        property bool danger: false
        readonly property color tone: danger ? c.red : c.orange
        Layout.fillWidth: true
        implicitHeight: bt.implicitHeight + 24
        radius: 12
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
        border.width: 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.35)
        Icon { id: bi; x: 14; y: 13; name: "alert"; tint: parent.tone; size: 17 }
        Text {
            id: bt
            anchors { left: bi.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: parent.text; color: c.textHi; wrapMode: Text.WordWrap; font.pixelSize: 13; lineHeight: 1.15
        }
    }

    component PageHeader: ColumnLayout {
        property string title: ""
        property string sub: ""
        spacing: 6
        Layout.fillWidth: true
        Text { text: parent.title; color: c.textHi; font.pixelSize: win.compact ? 22 : 28; font.weight: Font.Bold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Text { text: parent.sub; color: c.textMid; font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }

    // ── layout ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: c.bg1 }
            GradientStop { position: 1; color: c.bg0 }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // the rail
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: win.compact ? 72 : 250
            color: c.rail
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: c.line }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: win.compact ? 14 : 24
                spacing: 0

                RowLayout {
                    spacing: 12
                    Layout.alignment: win.compact ? Qt.AlignHCenter : Qt.AlignLeft
                    Rectangle {
                        width: 40; height: 40; radius: 12
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#13492F" }
                            GradientStop { position: 1; color: "#0B2A1C" }
                        }
                        border.width: 1; border.color: "#1F6B47"
                        Image { anchors.centerIn: parent; width: 26; height: 26; sourceSize: Qt.size(64, 64); source: Icons.leaf(c.mint.toString()) }
                    }
                    ColumnLayout {
                        visible: !win.compact
                        spacing: 0
                        Text { text: "Genesi"; color: c.textHi; font.pixelSize: 17; font.weight: Font.Bold }
                        Text { text: "Migrate"; color: c.mint; font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                }

                Item { Layout.preferredHeight: 36 }

                Repeater {
                    model: ["welcome", "scan", "apps", "disk", "files", "settings", "ready"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: win.page === index
                        readonly property bool done: index < win.page || (index <= win.reached && index !== win.page)
                        readonly property bool clickable: index <= win.reached && index !== 1 && win.manifest !== null
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 11
                        color: current ? c.cardHi : railMa.containsMouse && clickable ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: win.compact ? 9 : 12
                            spacing: 12
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: current ? c.accent : done ? Qt.rgba(0.12, 0.75, 0.42, 0.16) : "transparent"
                                border.width: current || done ? 0 : 1.5
                                border.color: c.lineHi
                                Icon { anchors.centerIn: parent; visible: done && !current; name: "check"; tint: c.accentHi; stroke: 3; size: 13 }
                                Text {
                                    anchors.centerIn: parent; visible: current || !done
                                    text: index + 1; font.pixelSize: 12; font.weight: Font.Bold
                                    color: current ? "#06210F" : c.textLo
                                }
                            }
                            Text {
                                visible: !win.compact
                                text: win.tr("step." + modelData)
                                color: current ? c.textHi : done ? c.textMid : c.textLo
                                font.pixelSize: 14; font.weight: current ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                            }
                        }
                        MouseArea {
                            id: railMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: parent.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (parent.clickable) win.page = index
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    visible: backend.demo && !win.compact
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    Layout.bottomMargin: 12
                    radius: 8
                    color: Qt.rgba(0.94, 0.65, 0.28, 0.12)
                    Text { anchors.centerIn: parent; text: win.tr("demo"); color: c.orange; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Icon { name: "shield"; tint: c.mint; size: 16; Layout.alignment: win.compact ? Qt.AlignHCenter : Qt.AlignTop }
                    Text {
                        visible: !win.compact
                        text: win.tr("rail.safe"); color: c.textLo; font.pixelSize: 12
                        wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.2
                    }
                }

                GridLayout {
                    Layout.topMargin: 16
                    Layout.alignment: win.compact ? Qt.AlignHCenter : Qt.AlignLeft
                    columns: win.compact ? 1 : 2
                    rowSpacing: 4
                    columnSpacing: 4
                    Repeater {
                        model: ["en", "pt"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool on: (modelData === "pt") === win.pt
                            width: 38; height: 24; radius: 7
                            color: on ? c.cardHi : "transparent"
                            border.width: 1; border.color: on ? c.lineHi : "transparent"
                            Text { anchors.centerIn: parent; text: modelData.toUpperCase(); color: on ? c.textHi : c.textLo; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pt = modelData === "pt" }
                        }
                    }
                }
            }
        }

        // the content
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                // ── 0 welcome ──────────────────────────────────────────
                Item {
                    Flickable {
                        id: welcomeFlick
                        anchors.fill: parent
                        contentHeight: Math.max(height, welcomeCol.implicitHeight + 2 * win.pad)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ColumnLayout {
                        id: welcomeCol
                        x: win.pad + 8; y: win.pad + 8
                        width: welcomeFlick.width - 2 * (win.pad + 8)
                        height: welcomeFlick.contentHeight - 2 * (win.pad + 8)
                        spacing: 0

                        Text { text: win.tr("w.eyebrow"); color: c.mint; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 2.2 }
                        Text {
                            Layout.topMargin: 14
                            text: win.tr("w.title"); color: c.textHi
                            font.pixelSize: win.compact ? 30 : 42; font.weight: Font.Bold; lineHeight: 1.05
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.topMargin: 16
                            Layout.fillWidth: true
                            Layout.maximumWidth: 620
                            text: win.trf("w.sub", backend.osPretty); color: c.textMid
                            font.pixelSize: 16; wrapMode: Text.WordWrap; lineHeight: 1.25
                        }

                        GridLayout {
                            Layout.topMargin: win.compact ? 24 : 36
                            Layout.fillWidth: true
                            columns: width >= 640 ? 3 : 1
                            columnSpacing: 16
                            rowSpacing: 12
                            Repeater {
                                model: [["grid", "w.f1", c.accentHi], ["folder", "w.f2", c.blue], ["sliders", "w.f3", c.purple]]
                                delegate: Card {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: parent.columns === 1 ? 118 : 170
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 20
                                        spacing: 10
                                        Rectangle {
                                            width: 42; height: 42; radius: 12
                                            color: Qt.rgba(modelData[2].r, modelData[2].g, modelData[2].b, 0.13)
                                            Icon { anchors.centerIn: parent; name: modelData[0]; tint: modelData[2]; size: 20 }
                                        }
                                        Text { Layout.topMargin: 4; text: win.tr(modelData[1] + ".t"); color: c.textHi; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Text {
                                            text: win.tr(modelData[1] + ".d"); color: c.textMid; font.pixelSize: 13
                                            wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.2
                                        }
                                        Item { Layout.fillHeight: true }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.minimumHeight: 24 }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: win.compact ? 1 : 2
                            columnSpacing: 16
                            rowSpacing: 14
                            RowLayout {
                                spacing: 10
                                Layout.fillWidth: true
                                Icon { name: "lock"; tint: c.textLo; size: 16 }
                                Text { text: win.tr("w.note"); color: c.textLo; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            Btn {
                                primary: true; text: win.tr("w.start"); iconRight: "arrow-right"; implicitHeight: 50
                                Layout.alignment: win.compact ? Qt.AlignLeft : Qt.AlignRight
                                onClicked: win.startScan()
                            }
                        }
                    }
                    }
                }

                // ── 1 scan ─────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 96, 560)
                        spacing: 0

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 84; height: 84; radius: 26
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#13492F" }
                                GradientStop { position: 1; color: "#0B2A1C" }
                            }
                            border.width: 1; border.color: "#1F6B47"
                            Image {
                                anchors.centerIn: parent; width: 50; height: 50; sourceSize: Qt.size(128, 128)
                                source: Icons.leaf(c.mint.toString())
                                SequentialAnimation on opacity {
                                    running: win.page === 1 && !win.manifest && win.scanError === ""
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.45; to: 1; duration: 800; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                        Text { Layout.topMargin: 26; Layout.alignment: Qt.AlignHCenter; text: win.tr("s.title"); color: c.textHi; font.pixelSize: 26; font.weight: Font.Bold }
                        Text { Layout.topMargin: 8; Layout.alignment: Qt.AlignHCenter; text: win.tr("s.sub"); color: c.textMid; font.pixelSize: 14 }

                        Rectangle {
                            Layout.topMargin: 28
                            Layout.fillWidth: true
                            height: 6; radius: 3; color: c.line
                            Rectangle {
                                width: parent.width * win.scanFrac; height: parent.height; radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: c.accent }
                                    GradientStop { position: 1; color: c.mint }
                                }
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }

                        Card {
                            Layout.topMargin: 24
                            Layout.fillWidth: true
                            Layout.preferredHeight: stagesCol.implicitHeight + 32
                            ColumnLayout {
                                id: stagesCol
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 4
                                Repeater {
                                    model: ["system", "apps", "flatpak", "files", "machine", "settings"]
                                    delegate: RowLayout {
                                        required property string modelData
                                        readonly property bool done: !!win.stagesDone[modelData]
                                        readonly property bool active: win.stageNow === modelData && !done
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        spacing: 12
                                        Item {
                                            width: 22; height: 22
                                            Rectangle { anchors.fill: parent; radius: 11; color: Qt.rgba(0.12, 0.75, 0.42, 0.16); visible: done }
                                            Icon { anchors.centerIn: parent; visible: done; name: "check"; tint: c.accentHi; stroke: 3; size: 12 }
                                            Rectangle {
                                                anchors.centerIn: parent; visible: !done
                                                width: active ? 10 : 6; height: width; radius: width / 2
                                                color: active ? c.mint : c.lineHi
                                                SequentialAnimation on scale {
                                                    running: active; loops: Animation.Infinite
                                                    NumberAnimation { from: 1; to: 1.5; duration: 450 }
                                                    NumberAnimation { from: 1.5; to: 1; duration: 450 }
                                                }
                                            }
                                        }
                                        Text {
                                            text: win.tr("s." + modelData); Layout.fillWidth: true
                                            color: done ? c.textHi : active ? c.textHi : c.textLo; font.pixelSize: 14
                                        }
                                    }
                                }
                            }
                        }

                        Banner { Layout.topMargin: 16; visible: win.scanError !== ""; danger: true; text: win.trf("s.error", win.scanError) }
                        Btn { Layout.topMargin: 12; Layout.alignment: Qt.AlignHCenter; visible: win.scanError !== ""; text: win.tr("s.retry"); icon: "refresh-cw"; onClicked: win.startScan() }
                    }
                }

                // ── 2 apps ─────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: win.pad
                        anchors.bottomMargin: 8
                        spacing: 18

                        PageHeader {
                            title: win.tr("a.title")
                            sub: win.trf("a.sub", win.selectedApps(), appsModel.count)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [["all", "a.all"], ["attention", "a.attention"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool on: win.appFilter === modelData[0]
                                    implicitHeight: 34
                                    implicitWidth: fl.implicitWidth + 30
                                    radius: 17
                                    color: on ? c.cardHi : "transparent"
                                    border.width: 1; border.color: on ? c.lineHi : c.line
                                    RowLayout {
                                        id: fl
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { text: win.tr(modelData[1]); color: on ? c.textHi : c.textMid; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        Rectangle {
                                            visible: modelData[0] === "attention" && win.attentionCount() > 0
                                            width: 20; height: 18; radius: 9; color: Qt.rgba(0.94, 0.65, 0.28, 0.18)
                                            Text { anchors.centerIn: parent; text: win.attentionCount(); color: c.orange; font.pixelSize: 11; font.weight: Font.Bold }
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.appFilter = modelData[0] }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                readonly property bool allOn: win.selectedApps() === appsModel.count
                                text: allOn ? win.tr("a.selectNone") : win.tr("a.selectAll")
                                color: c.mint; font.pixelSize: 13; font.weight: Font.DemiBold
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setAllApps(!parent.allOn) }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ListView {
                                id: appList
                                anchors.fill: parent
                                anchors.margins: 6
                                model: appsModel
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                delegate: Rectangle {
                                    id: row
                                    required property int index
                                    required property string name
                                    required property string icon
                                    required property string source
                                    required property string pkg
                                    required property string kind
                                    required property string target
                                    required property string confidence
                                    required property bool sel
                                    readonly property bool shown: win.appFilter === "all" || confidence === "likely"
                                    width: appList.width - 12
                                    height: shown ? 60 : 0
                                    visible: shown
                                    radius: 11
                                    color: rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.035) : "transparent"
                                    readonly property color tone: confidence === "likely" ? c.orange
                                                                : kind === "aur" ? c.blue
                                                                : kind === "flatpak" ? c.purple : c.accentHi
                                    readonly property string targetLabel: confidence === "likely"
                                        ? (kind === "flatpak-search" ? win.tr("t.search") : win.tr("t.likely"))
                                        : win.tr("t." + kind)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 14
                                        Check { checked: row.sel }
                                        Rectangle {
                                            width: 38; height: 38; radius: 10
                                            color: c.cardHi
                                            border.width: 1; border.color: c.line
                                            Image {
                                                id: appIcon
                                                anchors.centerIn: parent
                                                width: 26; height: 26; sourceSize: Qt.size(64, 64)
                                                source: row.icon !== "" ? "file://" + row.icon : ""
                                                visible: status === Image.Ready
                                                smooth: true
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                visible: appIcon.status !== Image.Ready
                                                text: row.source === "cli" ? ">_" : row.name.charAt(0).toUpperCase()
                                                color: c.mint; font.pixelSize: row.source === "cli" ? 13 : 16; font.weight: Font.Bold
                                                font.family: row.source === "cli" ? "monospace" : ""
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text { text: row.name; color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text {
                                                text: win.tr("src." + row.source) + (row.pkg && row.source !== "cli" ? "  ·  " + row.pkg : "")
                                                color: c.textLo; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                        }
                                        Icon { name: "arrow-right"; tint: c.textLo; size: 15 }
                                        ColumnLayout {
                                            spacing: 2
                                            // Fixed, so the arrows line up. A child with fillWidth makes a
                                            // layout fill too, which split the row by text length.
                                            Layout.fillWidth: false
                                            Layout.minimumWidth: win.compact ? 140 : 210
                                            Layout.maximumWidth: win.compact ? 140 : 210
                                            Pill { text: row.targetLabel; tone: row.tone; Layout.alignment: Qt.AlignLeft }
                                            Text {
                                                text: row.target; color: c.textLo; font.pixelSize: 11; font.family: "monospace"
                                                elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { appsModel.setProperty(row.index, "sel", !row.sel); win.rev++ }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: win.manifest && win.manifest.desktopComponents > 0
                            spacing: 8
                            Icon { name: "info"; tint: c.textLo; size: 14 }
                            Text { text: win.manifest ? win.trf("a.core", win.manifest.desktopComponents) : ""; color: c.textLo; font.pixelSize: 12 }
                        }
                    }
                }

                // ── 3 disk ─────────────────────────────────────────────
                Item {
                    Flickable {
                        id: diskFlick
                        anchors.fill: parent
                        contentHeight: diskCol.implicitHeight + 48
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: diskCol
                            x: win.pad; y: win.pad
                            width: diskFlick.width - 2 * win.pad
                            spacing: 14

                            PageHeader { title: win.tr("d.title"); sub: win.tr("d.sub") }

                            Card {
                                visible: win.disks().length === 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12
                                    Icon { name: "info"; tint: c.textMid; size: 18 }
                                    Text { text: win.tr("d.none"); color: c.textMid; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                }
                            }

                            Repeater {
                                model: win.disks()
                                delegate: Card {
                                    id: dc
                                    required property var modelData
                                    readonly property string sid: modelData.system ? "replace" : "disk:" + modelData.device
                                    readonly property bool chosen: win.installTarget === sid || (modelData.system && win.installTarget === "alongside")
                                    readonly property real total: Math.max(1, modelData.size)
                                    readonly property var bars: modelData.partitions.filter(function (p) { return p.size > 0 && p.type !== "crypt" })
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: dcCol.implicitHeight + 36
                                    border.color: chosen ? (modelData.system ? c.accent : c.red) : c.line
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (!dc.chosen) win.chooseTarget(dc.sid)
                                    }
                                    ColumnLayout {
                                        id: dcCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 14
                                            Radio { checked: dc.chosen }
                                            Rectangle {
                                                width: 42; height: 42; radius: 12
                                                color: dc.modelData.system ? Qt.rgba(0.12, 0.75, 0.42, 0.13)
                                                     : dc.modelData.removable ? Qt.rgba(0.77, 0.54, 0.87, 0.13) : Qt.rgba(0.23, 0.69, 0.88, 0.12)
                                                Icon {
                                                    anchors.centerIn: parent; name: "hard-drive"; size: 20
                                                    tint: dc.modelData.system ? c.accentHi : dc.modelData.removable ? c.purple : c.blue
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                RowLayout {
                                                    spacing: 8
                                                    Layout.fillWidth: true
                                                    Text {
                                                        text: dc.modelData.model + "  ·  " + win.fmt(dc.modelData.size)
                                                        color: c.textHi; font.pixelSize: 15; font.weight: Font.DemiBold
                                                        elide: Text.ElideRight; Layout.maximumWidth: 360
                                                    }
                                                    Pill { visible: dc.modelData.system; text: win.tr("d.tagSystem"); tone: c.accentHi }
                                                    Pill { visible: dc.modelData.removable; text: win.tr("d.tagExternal"); tone: c.purple }
                                                    Pill { visible: dc.modelData.windows; text: "Windows"; tone: "#8C9BFF" }
                                                    Item { Layout.fillWidth: true }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.WordWrap
                                                    color: c.textMid; font.pixelSize: 13; lineHeight: 1.15
                                                    text: dc.modelData.system && win.installTarget === "alongside"
                                                          ? win.trf("d.alongside", win.manifest.os.name)
                                                          : dc.modelData.system
                                                          ? win.trf("d.replace", win.manifest.os.name, win.manifest.machine.rootDevice)
                                                          : dc.modelData.removable ? win.tr("d.wholeExternal") : win.tr("d.whole")
                                                }
                                            }
                                            Text { text: dc.modelData.device; color: c.textLo; font.pixelSize: 12; font.family: "monospace"; Layout.alignment: Qt.AlignTop }
                                        }

                                        // what is on the disk today, to scale
                                        Item {
                                            id: barBox
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 36
                                            Layout.preferredHeight: 10
                                            Rectangle { anchors.fill: parent; radius: 3; color: c.line }
                                            Row {
                                                anchors.fill: parent
                                                spacing: 2
                                                Repeater {
                                                    model: dc.bars
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        height: 10; radius: 3
                                                        width: Math.max(6, (barBox.width - 2 * dc.bars.length) * modelData.size / dc.total)
                                                        color: win.partColor(modelData)
                                                        // what this choice would erase is drawn faded
                                                        opacity: !dc.chosen || win.installTarget === "alongside" ? 1
                                                               : !dc.modelData.system ? 0.3
                                                               : modelData.mountpoint === "/" ? 0.3 : 1
                                                    }
                                                }
                                            }
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 36
                                            spacing: 16
                                            Repeater {
                                                model: dc.bars
                                                delegate: Row {
                                                    required property var modelData
                                                    spacing: 6
                                                    Rectangle { width: 8; height: 8; radius: 4; color: win.partColor(modelData); anchors.verticalCenter: parent.verticalCenter }
                                                    Text { text: win.partName(modelData); color: c.textMid; font.pixelSize: 12 }
                                                    Text { text: win.fmt(modelData.size); color: c.textLo; font.pixelSize: 12 }
                                                }
                                            }
                                            Text { visible: dc.bars.length === 0; text: win.tr("d.empty"); color: c.textLo; font.pixelSize: 12 }
                                        }

                                        // v2: next to today's system (dual boot)
                                        Rectangle {
                                            id: alongRow
                                            visible: dc.modelData.system
                                            readonly property var info: win.alongsideInfo()
                                            readonly property bool on: win.installTarget === "alongside"
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 36
                                            implicitHeight: alongCol.implicitHeight + 24
                                            radius: 12
                                            color: on ? Qt.rgba(0.12, 0.75, 0.42, 0.08) : Qt.rgba(1, 1, 1, 0.02)
                                            border.width: 1
                                            border.color: on ? Qt.rgba(0.12, 0.75, 0.42, 0.45) : c.line
                                            opacity: info.ok ? 1 : 0.55
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: alongRow.info.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: if (alongRow.info.ok) win.chooseTarget(alongRow.on ? "replace" : "alongside")
                                            }
                                            ColumnLayout {
                                                id: alongCol
                                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                                spacing: 10
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 12
                                                    Check { checked: alongRow.on }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        Text { text: win.trf("d.alongsideTitle", win.manifest ? win.manifest.os.name : ""); color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                        Text {
                                                            text: alongRow.info.ok ? win.trf("d.alongsideSub", win.manifest ? win.manifest.os.name : "") : win.tr("d.alongsideNo." + alongRow.info.why)
                                                            color: alongRow.info.ok ? c.textLo : c.orange; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                        }
                                                    }
                                                }
                                                // the split, to scale: old system | Genesi
                                                ColumnLayout {
                                                    visible: alongRow.on
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Item {
                                                        id: splitBar
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 12
                                                        readonly property real total: Math.max(1, alongRow.info.partSize || 1)
                                                        Rectangle { width: parent.width; height: 12; radius: 4; color: c.line }
                                                        Rectangle {
                                                            width: parent.width * Math.max(0, 1 - win.genesiBytes / splitBar.total) - 2
                                                            height: 12; radius: 4; color: c.accent
                                                        }
                                                        Rectangle {
                                                            x: parent.width * Math.max(0, 1 - win.genesiBytes / splitBar.total)
                                                            width: parent.width - x; height: 12; radius: 4; color: c.mint
                                                        }
                                                    }
                                                    Slider {
                                                        id: sizeSlider
                                                        Layout.fillWidth: true
                                                        from: alongRow.info.min
                                                        to: Math.max(alongRow.info.min + 1, alongRow.info.max)
                                                        stepSize: 1073741824
                                                        value: win.genesiBytes
                                                        onMoved: { win.genesiBytes = value; win.rev++ }
                                                        background: Rectangle {
                                                            x: sizeSlider.leftPadding
                                                            y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                            width: sizeSlider.availableWidth; height: 4; radius: 2; color: c.lineHi
                                                            Rectangle { width: sizeSlider.visualPosition * parent.width; height: 4; radius: 2; color: c.mint }
                                                        }
                                                        handle: Rectangle {
                                                            x: sizeSlider.leftPadding + sizeSlider.visualPosition * (sizeSlider.availableWidth - width)
                                                            y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                            width: 20; height: 20; radius: 10
                                                            color: sizeSlider.pressed ? c.mint : c.textHi
                                                            border.width: 3; border.color: c.accent
                                                        }
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: win.trf("d.keeps", win.manifest ? win.manifest.os.name : "", win.fmt(Math.max(0, (alongRow.info.partSize || 0) - win.genesiBytes))); color: c.textMid; font.pixelSize: 12 }
                                                        Item { Layout.fillWidth: true }
                                                        Text { text: win.trf("d.gets", win.fmt(win.genesiBytes)); color: c.mint; font.pixelSize: 12; font.weight: Font.DemiBold }
                                                    }
                                                }
                                            }
                                        }

                                        Banner {
                                            visible: dc.chosen && dc.modelData.home && !dc.modelData.system
                                            danger: true
                                            text: win.tr("d.homeHere")
                                        }

                                        // erasing a whole disk takes an explicit yes
                                        Rectangle {
                                            visible: dc.chosen && !dc.modelData.system
                                            Layout.fillWidth: true
                                            implicitHeight: 48
                                            radius: 12
                                            color: Qt.rgba(0.94, 0.42, 0.35, 0.09)
                                            border.width: 1
                                            border.color: Qt.rgba(0.94, 0.42, 0.35, win.wipeConfirmed ? 0.6 : 0.3)
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                spacing: 12
                                                Check { checked: win.wipeConfirmed; color: checked ? c.red : "transparent" }
                                                Text {
                                                    text: win.trf("d.confirm", dc.modelData.model, win.fmt(dc.modelData.size))
                                                    color: c.textHi; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { win.wipeConfirmed = !win.wipeConfirmed; win.rev++ }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.topMargin: 4
                                spacing: 10
                                Icon { name: "shield"; tint: c.mint; size: 15 }
                                Text { text: win.tr("d.safety"); color: c.textLo; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ── 4 files ────────────────────────────────────────────
                Item {
                    Flickable {
                        id: filesFlick
                        anchors.fill: parent
                        contentHeight: filesCol.implicitHeight + 48
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: filesCol
                            x: win.pad; y: win.pad
                            width: filesFlick.width - 2 * win.pad
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                PageHeader { title: win.tr("f.title"); sub: win.tr("f.sub") }
                                Pill { text: win.trf("f.total", win.fmt(win.selectedBytes())); tone: c.mint; Layout.alignment: Qt.AlignBottom }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 760 ? 3 : 2
                                columnSpacing: 12
                                rowSpacing: 12
                                Repeater {
                                    model: filesModel
                                    delegate: Card {
                                        id: fc
                                        required property int index
                                        required property string fid
                                        required property string group
                                        required property double bytes
                                        required property bool estimate
                                        required property bool sel
                                        required property string extra
                                        visible: group === "files"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? 92 : 0
                                        border.color: sel ? Qt.rgba(0.12, 0.75, 0.42, 0.45) : c.line
                                        readonly property var icons: ({ documents: "file-text", pictures: "image", music: "music",
                                                                       videos: "film", downloads: "download", desktop: "monitor", other: "folder" })
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 14
                                            Rectangle {
                                                width: 42; height: 42; radius: 12
                                                color: Qt.rgba(0.23, 0.69, 0.88, 0.12)
                                                Icon { anchors.centerIn: parent; name: fc.icons[fc.fid] || "folder"; tint: c.blue; size: 20 }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                Text { text: win.tr(fc.fid); color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Text {
                                                    text: (fc.estimate ? "≥ " : "") + win.fmt(fc.bytes) + (fc.extra ? "  ·  " + fc.extra : "")
                                                    color: c.textLo; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                                                }
                                            }
                                            Check { checked: fc.sel }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { filesModel.setProperty(fc.index, "sel", !fc.sel); win.rev++ }
                                        }
                                    }
                                }
                            }

                            Text { Layout.topMargin: 6; text: win.tr("f.hiddenTitle"); color: c.textMid; font.pixelSize: 13; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }

                            Card {
                                Layout.fillWidth: true
                                Layout.preferredHeight: hiddenCol.implicitHeight + 12
                                ColumnLayout {
                                    id: hiddenCol
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 0
                                    Repeater {
                                        model: filesModel
                                        delegate: Rectangle {
                                            id: hr
                                            required property int index
                                            required property string fid
                                            required property string group
                                            required property double bytes
                                            required property bool estimate
                                            required property bool sel
                                            visible: group === "hidden"
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: visible ? 58 : 0
                                            radius: 10
                                            color: hma.containsMouse ? Qt.rgba(1, 1, 1, 0.035) : "transparent"
                                            readonly property var icons: ({ browsers: "globe", keys: "key", appconfig: "sliders", steam: "play" })
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                spacing: 14
                                                Icon { name: hr.icons[hr.fid] || "folder"; tint: c.purple; size: 18 }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    Text { text: win.tr(hr.fid); color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                    Text { text: win.tr(hr.fid + ".d"); color: c.textLo; font.pixelSize: 12; Layout.fillWidth: true }
                                                }
                                                Text {
                                                    text: (hr.estimate ? "≥ " : "") + win.fmt(hr.bytes); color: c.textMid; font.pixelSize: 13
                                                    horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 90
                                                }
                                                Check { checked: hr.sel }
                                            }
                                            MouseArea {
                                                id: hma
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { filesModel.setProperty(hr.index, "sel", !hr.sel); win.rev++ }
                                            }
                                        }
                                    }
                                }
                            }

                            // where the files wait
                            Text { Layout.topMargin: 10; text: win.tr("f.whereTitle"); color: c.textHi; font.pixelSize: 18; font.weight: Font.Bold }
                            Text { Layout.topMargin: -10; text: win.stayAvailable() ? win.tr("f.whereSubStay") : win.tr("f.whereSub"); color: c.textMid; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                            Card {
                                id: stayCard
                                readonly property bool chosen: win.strategy === "stay"
                                visible: win.stayAvailable()
                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? 74 : 0
                                border.color: chosen ? c.accent : c.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 14
                                    Radio { checked: stayCard.chosen }
                                    Icon { name: "check-circle"; tint: stayCard.chosen ? c.accentHi : c.textMid; size: 20 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: win.tr("f.stay"); color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Text {
                                            text: win.manifest ? win.trf("f.stay.d", win.targetDisk() ? win.targetDisk().model : "", win.manifest.os.name) : ""
                                            color: c.textLo; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                        }
                                    }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.strategy = "stay" }
                            }

                            Repeater {
                                model: win.strategies()
                                delegate: Card {
                                    id: sc
                                    required property var modelData
                                    readonly property string sid: modelData.id === "external" ? "external:" + modelData.device : modelData.id
                                    readonly property bool ok: modelData.id === "keep-home" || win.externalOk(modelData)
                                    readonly property bool chosen: win.strategy === sid
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 74
                                    opacity: ok ? 1 : 0.6
                                    border.color: chosen ? c.accent : c.line
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 14
                                        Radio { checked: sc.chosen }
                                        Icon { name: "hard-drive"; tint: sc.chosen ? c.accentHi : c.textMid; size: 20 }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text {
                                                text: sc.modelData.id === "keep-home" ? win.tr("f.keepHome") : win.trf("f.external", sc.modelData.label)
                                                color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                color: sc.ok ? c.textLo : c.orange; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                text: sc.modelData.id === "keep-home" ? win.trf("f.keepHome.d", sc.modelData.device)
                                                    : !sc.modelData.mounted ? win.tr("f.external.unmounted")
                                                    : sc.ok ? win.trf("f.external.d", win.fmt(sc.modelData.free), win.fmt(win.selectedBytes()))
                                                    : win.trf("f.external.small", win.fmt(sc.modelData.free), win.fmt(win.selectedBytes() * 1.05))
                                            }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: sc.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: if (sc.ok) win.strategy = sc.sid
                                    }
                                }
                            }

                            Card {
                                visible: !win.stayAvailable() && !win.strategies().some(function (s) { return s.id === "external" })
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                color: "transparent"
                                gradient: null
                                border.color: c.lineHi
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 14
                                    Icon { name: "hard-drive"; tint: c.textLo; size: 20 }
                                    Text {
                                        // One disk, one partition, replacing it: the files have
                                        // nowhere to wait. Say which ways out this machine has.
                                        text: win.trf("f.noExternal", win.fmt(win.selectedBytes() * 1.05))
                                              + (win.installTarget === "replace" && win.alongsideInfo().ok ? " " + win.tr("f.orAlongside") : "")
                                              + (win.otherDiskAvailable() ? " " + win.tr("f.orOtherDisk") : "")
                                        color: c.textMid; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                    Btn { text: win.tr("f.rescan"); icon: "refresh-cw"; implicitHeight: 36; onClicked: win.rescan() }
                                }
                            }

                            Card {
                                id: noneCard
                                visible: win.installTarget !== "replace"
                                readonly property bool chosen: win.strategy === "none"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 74
                                border.color: chosen ? c.red : c.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 14
                                    Radio { checked: noneCard.chosen }
                                    Icon { name: "x"; tint: noneCard.chosen ? c.red : c.textMid; size: 20 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text { text: win.tr("f.none"); color: c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Text { text: win.tr("f.none.d"); color: noneCard.chosen ? c.red : c.textLo; font.pixelSize: 12; Layout.fillWidth: true }
                                    }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.strategy = "none" }
                            }
                        }
                    }
                }

                // ── 5 settings ─────────────────────────────────────────
                Item {
                    Flickable {
                        id: setFlick
                        anchors.fill: parent
                        contentHeight: setCol.implicitHeight + 48
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: setCol
                            x: win.pad; y: win.pad
                            width: setFlick.width - 2 * win.pad
                            spacing: 18

                            PageHeader { title: win.tr("e.title"); sub: win.tr("e.sub") }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 12
                                rowSpacing: 12
                                Repeater {
                                    model: win.manifest ? [
                                        ["globe", "e.lang", win.manifest.settings.locale.split(".")[0]],
                                        ["type", "e.kb", win.manifest.settings.keyboard.layout + (win.manifest.settings.keyboard.variant ? " (" + win.manifest.settings.keyboard.variant + ")" : "")],
                                        ["clock", "e.tz", win.manifest.settings.timezone],
                                        ["user", "e.user", (win.manifest.settings.user.fullName ? win.manifest.settings.user.fullName + " · " : "") + win.manifest.settings.user.name]
                                    ] : []
                                    delegate: Card {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 76
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 14
                                            Rectangle {
                                                width: 42; height: 42; radius: 12
                                                color: Qt.rgba(0.77, 0.54, 0.87, 0.12)
                                                Icon { anchors.centerIn: parent; name: modelData[0]; tint: c.purple; size: 19 }
                                            }
                                            ColumnLayout {
                                                spacing: 3
                                                Layout.fillWidth: true
                                                Text { text: win.tr(modelData[1]); color: c.textLo; font.pixelSize: 12 }
                                                Text { text: modelData[2]; color: c.textHi; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            Icon { name: "check"; tint: c.accentHi; stroke: 2.5; size: 16 }
                                        }
                                    }
                                }
                            }

                            // Wi-Fi
                            Card {
                                id: wifiCard
                                readonly property var nets: win.manifest ? win.manifest.settings.wifi : []
                                Layout.fillWidth: true
                                Layout.preferredHeight: wifiCol.implicitHeight + 32
                                ColumnLayout {
                                    id: wifiCol
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12
                                    RowLayout {
                                        spacing: 14
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: 42; height: 42; radius: 12
                                            color: Qt.rgba(0.23, 0.69, 0.88, 0.12)
                                            Icon { anchors.centerIn: parent; name: "wifi"; tint: c.blue; size: 19 }
                                        }
                                        ColumnLayout {
                                            spacing: 3
                                            Layout.fillWidth: true
                                            Text { text: win.tr("e.wifi"); color: c.textLo; font.pixelSize: 12 }
                                            Text {
                                                text: wifiCard.nets.length ? win.trf("e.wifiN", wifiCard.nets.length) : win.tr("e.wifiNone")
                                                color: c.textHi; font.pixelSize: 15; font.weight: Font.DemiBold
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        RowLayout {
                                            visible: wifiCard.nets.length > 0
                                            spacing: 10
                                            Text { text: win.tr("e.bringWifi"); color: c.textMid; font.pixelSize: 13 }
                                            Check {
                                                checked: win.bringWifi
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.bringWifi = !win.bringWifi }
                                            }
                                        }
                                    }
                                    Flow {
                                        visible: wifiCard.nets.length > 0
                                        Layout.fillWidth: true
                                        spacing: 8
                                        opacity: win.bringWifi ? 1 : 0.4
                                        Repeater {
                                            model: wifiCard.nets
                                            delegate: Pill { required property string modelData; text: modelData; tone: c.blue }
                                        }
                                    }
                                }
                            }

                            // desktop
                            Text { Layout.topMargin: 10; text: win.tr("e.desktop"); color: c.textHi; font.pixelSize: 18; font.weight: Font.Bold }
                            Text {
                                Layout.topMargin: -10
                                text: win.manifest && win.manifest.settings.desktop
                                      ? win.trf("e.desktopNow", win.manifest.settings.desktop.split(":").pop())
                                      : win.tr("e.desktopUnknown")
                                color: c.textMid; font.pixelSize: 13
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 3 : 2
                                columnSpacing: 10
                                rowSpacing: 10
                                Repeater {
                                    model: win.desktops
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool chosen: win.desktopId === modelData.id
                                        readonly property bool suggested: win.manifest && win.manifest.settings.genesiDesktop === modelData.id
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52
                                        radius: 12
                                        color: chosen ? Qt.rgba(0.12, 0.75, 0.42, 0.10) : dma.containsMouse ? c.cardHi : c.card
                                        border.width: 1
                                        border.color: chosen ? c.accent : c.line
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 10
                                            Radio { checked: chosen }
                                            Text { text: modelData.name; color: c.textHi; font.pixelSize: 14; font.weight: chosen ? Font.DemiBold : Font.Normal; Layout.fillWidth: true; elide: Text.ElideRight }
                                            Icon { visible: suggested; name: "zap"; tint: c.mint; size: 14 }
                                        }
                                        MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.desktopId = modelData.id }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 6 ready ────────────────────────────────────────────
                Item {
                    Flickable {
                        id: readyFlick
                        anchors.fill: parent
                        contentHeight: readyCol.implicitHeight + 48
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: readyCol
                            x: win.pad; y: win.pad
                            width: readyFlick.width - 2 * win.pad
                            spacing: 18

                            PageHeader { title: win.tr("r.title"); sub: win.tr("r.sub") }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Repeater {
                                    model: [
                                        ["grid", win.selectedApps().toString(), "r.apps", c.accentHi],
                                        ["folder", win.strategy === "none" ? "0" : win.fmt(win.selectedBytes()), "r.files", c.blue],
                                        ["sliders", (5 + (win.bringWifi && win.manifest && win.manifest.settings.wifi.length ? 1 : 0)).toString(), "r.settings", c.purple]
                                    ]
                                    delegate: Card {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 104
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 18
                                            spacing: 6
                                            Icon { name: modelData[0]; tint: modelData[3]; size: 20 }
                                            Item { Layout.fillHeight: true }
                                            RowLayout {
                                                spacing: 8
                                                Text { text: modelData[1]; color: c.textHi; font.pixelSize: 26; font.weight: Font.Bold }
                                                Text { text: win.tr(modelData[2]); color: c.textMid; font.pixelSize: 13; Layout.alignment: Qt.AlignBaseline }
                                            }
                                        }
                                    }
                                }
                            }

                            Card {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12
                                    Icon { name: "hard-drive"; tint: c.textMid; size: 18 }
                                    Text { text: win.tr("r.dest"); color: c.textLo; font.pixelSize: 13 }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        color: win.strategy === "none" ? c.red : c.textHi; font.pixelSize: 14; font.weight: Font.DemiBold
                                        text: win.strategy === "keep-home" ? win.tr("r.dest.keep")
                                            : win.strategy === "stay" ? win.tr("r.dest.stay")
                                            : win.strategy === "none" ? win.tr("r.dest.none")
                                            : (function () { var ss = win.strategies(); for (var i = 0; i < ss.length; i++) if ("external:" + ss[i].device === win.strategy) return ss[i].label + "  (" + ss[i].device + ")"; return "—" })()
                                    }
                                    Text { text: win.manifest ? (win.desktops.filter(function (d) { return d.id === win.desktopId })[0] || { name: "" }).name : ""; color: c.mint; font.pixelSize: 13; font.weight: Font.DemiBold }
                                }
                            }

                            Card {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12
                                    Icon { name: "monitor"; tint: c.textMid; size: 18 }
                                    Text { text: win.tr("r.target"); color: c.textLo; font.pixelSize: 13 }
                                    Text {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: win.targetLabel()
                                        color: win.installTarget === "replace" ? c.textHi : c.orange
                                        font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Banner { visible: !win.strategyValid(); text: win.tr("warn.needDest") }
                            Repeater {
                                model: win.warnings()
                                delegate: Banner { required property var modelData; danger: modelData.blocker; text: win.warnText(modelData.key) }
                            }

                            Text { Layout.topMargin: 6; text: win.tr("r.how"); color: c.textHi; font.pixelSize: 18; font.weight: Font.Bold }
                            Card {
                                Layout.fillWidth: true
                                Layout.preferredHeight: howCol.implicitHeight + 24
                                ColumnLayout {
                                    id: howCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 0
                                    Repeater {
                                        model: win.prepSteps()
                                        delegate: ColumnLayout {
                                            required property string modelData
                                            required property int index
                                            readonly property real frac: win.prepFrac[modelData] === undefined ? -1 : win.prepFrac[modelData]
                                            readonly property bool doneNow: frac >= 1
                                            readonly property bool active: frac >= 0 && frac < 1 && win.prepState === "running"
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 6
                                            spacing: 4
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                spacing: 14
                                                Rectangle {
                                                    width: 26; height: 26; radius: 13
                                                    color: doneNow ? c.accent : active ? Qt.rgba(0.12, 0.75, 0.42, 0.16) : c.cardHi
                                                    Icon { anchors.centerIn: parent; visible: doneNow; name: "check"; tint: "#06210F"; stroke: 3; size: 13 }
                                                    Text { anchors.centerIn: parent; visible: !doneNow; text: index + 1; color: active ? c.accentHi : c.textLo; font.pixelSize: 12; font.weight: Font.Bold }
                                                }
                                                Text { text: win.tr("p." + modelData); color: doneNow || active ? c.textHi : c.textMid; font.pixelSize: 14; Layout.fillWidth: true }
                                                Text { text: win.prepDetail[modelData] || ""; color: c.textLo; font.pixelSize: 12 }
                                            }
                                            Rectangle {
                                                visible: active && frac > 0
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 40
                                                Layout.bottomMargin: 6
                                                height: 4; radius: 2; color: c.line
                                                Rectangle { width: parent.width * Math.min(1, frac); height: 4; radius: 2; color: c.mint }
                                            }
                                        }
                                    }
                                }
                            }

                            Card {
                                visible: win.prepState === "done"
                                Layout.fillWidth: true
                                Layout.preferredHeight: doneCol.implicitHeight + 36
                                border.color: Qt.rgba(0.12, 0.75, 0.42, 0.5)
                                RowLayout {
                                    id: doneCol
                                    anchors.fill: parent
                                    anchors.margins: 18
                                    spacing: 16
                                    Icon { name: "check-circle"; tint: c.accentHi; size: 26; Layout.alignment: Qt.AlignTop }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text { text: win.tr("r.readyTitle"); color: c.textHi; font.pixelSize: 16; font.weight: Font.Bold }
                                        Text { text: win.installTarget === "replace" ? win.tr("r.nativeReady") : win.tr(win.prepRam ? "r.readyTextRam" : "r.readyText"); color: c.textMid; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.2 }
                                    }
                                }
                            }
                            Banner { visible: win.prepState === "failed"; danger: true; text: win.prepError }

                            Banner { visible: win.saveError !== ""; danger: true; text: win.trf("r.saveFail", win.saveError) }
                        }
                    }
                }
            }

            // bottom bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                visible: win.page >= 2
                color: "transparent"
                Rectangle { width: parent.width; height: 1; color: c.line }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: win.pad
                    anchors.rightMargin: win.pad
                    spacing: 12
                    Btn {
                        text: win.tr("back"); icon: "arrow-left"
                        enabledState: win.prepState !== "running"
                        onClicked: win.page = win.page === 2 ? 0 : win.page - 1
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: win.page === 6 && win.blocked()
                        text: win.tr("r.blocked"); color: c.red; font.pixelSize: 13
                    }
                    Btn {
                        visible: win.page < 6
                        primary: true
                        text: win.tr("next")
                        iconRight: "arrow-right"
                        enabledState: win.canAdvance()
                        onClicked: win.page = win.page + 1
                    }
                    Btn {
                        visible: win.page === 6 && win.prepState === "running"
                        text: win.tr("p.cancel")
                        enabledState: win.installTarget !== "replace" || (win.prepCurrent !== "build" && win.prepCurrent !== "arm")
                        icon: "x"
                        onClicked: backend.cancelPrepare()
                    }
                    Btn {
                        visible: win.page === 6 && win.prepState === "done"
                        text: win.tr("p.later")
                        onClicked: { if (backend.disarm()) { win.prepState = ""; win.prepFrac = ({}); win.prepDetail = ({}) } }
                    }
                    Btn {
                        visible: win.page === 6 && (win.prepState === "" || win.prepState === "failed")
                        primary: true
                        text: win.prepState === "failed" ? win.tr("p.retry") : win.tr("r.go")
                        icon: "zap"
                        enabledState: !win.blocked() && win.strategyValid() && win.targetValid()
                        onClicked: win.startPrepare()
                    }
                    Btn {
                        visible: win.page === 6 && win.prepState === "done"
                        primary: true
                        text: win.tr("p.reboot")
                        icon: "power"
                        onClicked: backend.reboot()
                    }
                }
            }
        }
    }

    function rescan() {
        var files = []
        for (var i = 0; i < filesModel.count; i++) {
            var f = filesModel.get(i)
            files.push({ id: f.fid, bytes: f.bytes, selected: f.sel })
        }
        backend.rescanDisks(JSON.stringify(files))
    }
}
