"""English for everything the catalogue says.

The tables in build-catalog.py are written in Portuguese, because that is the
language this shelf was designed in and the one its copy was tuned in. What
SHIPS leads with English, because Genesi is installed from anywhere, and falls
back to the machine's own language when it has one.

Keeping the translations here rather than inline in each table means adding a
card does not mean editing two places -- and it means the check in
build-catalog can be exhaustive. A string with no entry here FAILS THE BUILD
rather than shipping a shelf that is half one language and half the other,
which is the state every half-internationalised app is permanently stuck in.

These are translations, not transliterations. "Cadê meu tema?" is a joke about
a theme that draws almost nothing, and "Where's my theme?" is the same joke;
"O sono que você não teve" is about sleep you did not get, and rendering it
word by word would produce something nobody would write in English.
"""

# Names that are the same in both languages: brands, game titles, the names
# the theme authors chose. Listed rather than guessed, because "a string with
# no translation is fine if it looks like a proper noun" is a rule that
# silently ships "Floresta Escura" to somebody in Oslo the day a heuristic
# decides it looks foreign enough.
SAME = {
    "Arch Nord", "Aurora", "Caelestia", "Caelestia Locklike",
    "Caelestia Minimalist", "Catppuccin Frappe", "Catppuccin Latte",
    "Catppuccin Macchiato", "Catppuccin Mocha", "Cyberpunk", "Dracula",
    "Echo", "Enfield", "Everblush", "Everforest", "Genesi", "Genshin Impact",
    "Gruvbox", "Hacker", "Hollow Knight", "Hypr", "Hyprland", "Jake",
    "Material You", "Minecraft", "Minimal", "Munchlax", "NieR: Automata",
    "Nine Sols", "Ninja Gaiden", "Nord", "Old World", "One Dark", "Pixie",
    "Reverse: 1999", "Rose Pine", "Rose Pine Dawn", "Rose Pine Moon", "Shado",
    "Silent", "Silent Catppuccin Latte", "Silent Catppuccin Macchiato",
    "Silent Catppuccin Mocha", "Silent Everforest", "Silent Ken",
    "Silent Nord", "Silent Rei", "Solarized", "Star Rail", "Terraria",
    "The Last of Us", "Tokyo Night", "Windows 7", "Wuthering Waves", "osu!",
}

ENGLISH = {
    # ── Sections ───────────────────────────────────────────────────────────
    "O que vale a pena hoje.": "Worth a look today.",
    "Um desktop inteiro, de uma vez.": "A whole desktop, in one go.",
    "A cor de tudo, do topo ao terminal.":
        "The colour of everything, from the bar to the terminal.",
    "Antes de entrar: o que pede sua senha no boot.":
        "Before you are in: what asks for your password at boot.",
    "Já dentro: a tranca do caelestia, que segue o seu tema e o seu papel "
    "de parede.":
        "Once you are in: caelestia's own lock, which follows your theme and "
        "your wallpaper.",
    "Quinze arranjos da barra.": "Fifteen arrangements of the bar.",
    "O cartão de visita do terminal.": "What your terminal says hello with.",
    "Papéis de parede e detalhes.": "Wallpapers and small things.",
    "Combinações que já vêm casadas.": "Combinations that already match.",
    "Em breve.": "Coming soon.",

    # ── Colour schemes ─────────────────────────────────────────────────────
    "Caelestia Claro": "Caelestia Light",
    "Verde Profundo": "Deep Green",
    "Verde Mata": "Forest Green",
    "Everforest Duro": "Everforest Hard",
    "Everforest Claro": "Everforest Light",
    "Gruvbox Duro": "Gruvbox Hard",
    "Gruvbox Macio": "Gruvbox Soft",
    "Gruvbox Claro": "Gruvbox Light",
    "O tom da casa, no escuro.": "The house colour, in the dark.",
    "O mesmo, na luz.": "The same, in the light.",
    "Quase preto, com seiva.": "Almost black, with sap in it.",
    "Verde sem gritar.": "Green without shouting.",
    "Musgo, pedra e madeira.": "Moss, stone and wood.",
    "O mesmo, com mais contraste.": "The same, with more contrast.",
    "Papel e folha.": "Paper and leaf.",
    "Escuro com um rubor.": "Dark with a blush.",
    "O pastel que todo mundo conhece.": "The pastel everybody knows.",
    "Um passo mais claro.": "One step lighter.",
    "Meio do caminho.": "Halfway between.",
    "Claro, sem estourar.": "Light, without glaring.",
    "Terra, mostarda e ferrugem.": "Earth, mustard and rust.",
    "Fundo mais fechado.": "A deeper background.",
    "Fundo mais aberto.": "A lighter background.",
    "O mesmo, de dia.": "The same, by day.",
    "Gelo e aço.": "Ice and steel.",
    "Cidade às três da manhã.": "A city at three in the morning.",
    "Vinho e pinho.": "Wine and pine.",
    "Um pouco mais alto.": "A little higher.",
    "O amanhecer da mesma.": "The same one at dawn.",
    "Roxo clássico.": "Classic purple.",
    "O tema de editor virou desktop.": "The editor theme, grown into a desktop.",
    "Sepia e quieto.": "Sepia and quiet.",
    "O mais estudado de todos.": "The most studied of them all.",
    "Cinza com um fio de cor.": "Grey with a thread of colour.",

    # ── Wallpapers ─────────────────────────────────────────────────────────
    "Floresta Escura": "Dark Forest",
    "Natureza": "Nature",
    "Lago": "Lake",
    "Lago Ilustrado": "Lake, Illustrated",
    "Montanhas": "Mountains",
    "Cidade Nord": "Nord City",
    "Montanhas OLED": "OLED Mountains",
    "Lua": "Moon",
    "Outono": "Autumn",
    "Sol Verde": "Green Sun",
    "Castelo no Céu": "Castle in the Sky",
    "Onda de Tinta": "Ink Wave",
    "Cidade Gruvbox": "Gruvbox City",
    "Neocidade": "Neo City",
    "Mata fechada ao anoitecer.": "Deep woods at nightfall.",
    "Verde aberto, sem pressa.": "Open green, in no hurry.",
    "A paleta everforest em desenho.": "The everforest palette, drawn.",
    "Água parada e montanha.": "Still water and a mountain.",
    "O mesmo silêncio, desenhado.": "The same silence, drawn.",
    "Camadas até o horizonte.": "Layers to the horizon.",
    "A cidade em nord, bem larga.": "The city in nord, and very wide.",
    "Preto real, para telas OLED.": "True black, for OLED screens.",
    "Uma lua e nada mais.": "A moon and nothing else.",
    "Uma árvore em queda de folhas.": "A tree letting go of its leaves.",
    "Luz filtrada por folhas.": "Light coming through leaves.",
    "Árvore, castelo, nuvem.": "Tree, castle, cloud.",
    "Nanquim em movimento.": "Ink in motion.",
    "Luz fria sobre o horizonte.": "Cold light over the horizon.",
    "Quase nada, bem colocado.": "Almost nothing, well placed.",
    "O logo, em nord.": "The logo, in nord.",
    "Retro em terra e mostarda.": "Retro in earth and mustard.",
    "Neon e chuva.": "Neon and rain.",

    # ── Bars ───────────────────────────────────────────────────────────────
    "Padrão": "Default",
    "Rente": "Flush",
    "Centralizado": "Centred",
    "Fio": "Thread",
    "Ilha": "Island",
    "Numeros": "Numbers",
    "Arejado": "Airy",
    "Janelas": "Windows",
    "Painel": "Panel",
    "Informativo": "Informative",
    "Compacto": "Compact",
    "Limpo": "Clean",
    "Relogio": "Clock",
    "Trilha": "Trail",
    "Oculta": "Hidden",
    "A barra como o caelestia entrega.": "The bar as caelestia ships it.",
    "Sem moldura: encostada na borda da tela.":
        "No frame: right against the edge of the screen.",
    "Logo em cima, espaços no meio, o resto embaixo.":
        "Logo at the top, workspaces in the middle, the rest below.",
    "O mais estreito que dá para acertar com o mouse.":
        "As narrow as you can still hit with a pointer.",
    "Cantos bem redondos, barra na beirada.":
        "Round corners, floating off the edge.",
    "Espaços de trabalho numerados.": "Numbered workspaces.",
    "Mais espaço entre tudo.": "More room between everything.",
    "Mostra as janelas abertas.": "Shows the windows you have open.",
    "Denso, como um painel de controle.": "Dense, like a control panel.",
    "Tudo que dá para medir, medido.": "Everything measurable, measured.",
    "O essencial, junto.": "The essentials, close together.",
    "So o necessario.": "Only what is needed.",
    "O relógio em primeiro lugar.": "The clock first.",
    "Uma linha contínua.": "One continuous line.",
    "Some até você precisar.": "Gone until you reach for it.",

    # ── Fastfetch ──────────────────────────────────────────────────────────
    "Completo": "Full",
    "Sem logo": "No logo",
    "Verde": "Green",
    "Com imagem": "With a picture",
    "Com imagem (pequena)": "With a picture (small)",
    "Ficha técnica": "Spec sheet",
    "Ficha técnica (sem logo)": "Spec sheet (no logo)",
    "Ficha técnica (neon)": "Spec sheet (neon)",
    "Ficha técnica (tinta)": "Spec sheet (ink)",
    "Ficha técnica (castelo)": "Spec sheet (castle)",
    "Ficha técnica (lua)": "Spec sheet (moon)",
    "Ficha técnica (gruvbox)": "Spec sheet (gruvbox)",
    "Cinco linhas e o logo pequeno.": "Five lines and the small logo.",
    "Tudo que dá para contar sobre a máquina.":
        "Everything there is to say about the machine.",
    "Só texto, para quem abre muitos terminais.":
        "Text only, for anybody who opens a lot of terminals.",
    "As cores da casa no prompt.": "The house colours at the prompt.",
    "Uma foto no lugar do desenho, em sixel. Precisa de um terminal que "
    "desenhe imagens: o foot, que é o padrão do Genesi, desenha.":
        "A photograph where the ASCII goes, in sixel. Needs a terminal that "
        "draws images: foot, which is Genesi's default, does.",
    "Vitais, sistema e sessão separados, com a paleta embaixo. O jeitão que "
    "as pessoas montam à mão.":
        "Vitals, system and session in their own sections, with the palette "
        "underneath. The look people build by hand.",
    "A mesma ficha, sem desenho nenhum na frente.":
        "The same sheet, with no drawing in front of it.",

    # ── Rices ──────────────────────────────────────────────────────────────
    "Floresta Viva": "Living Forest",
    "Orvalho": "Dew",
    "Noite Baixa": "Low Night",
    "Terra": "Earth",
    "Meia-Noite": "Midnight",
    "Papel": "Paper",
    "Verde fechado e barra rente sobre a mata.":
        "Deep green and a flush bar over the woods.",
    "Verde claro da casa sobre água parada.":
        "The house's lighter green over still water.",
    "Preto real, barra fina, nada brilhando.":
        "True black, a thin bar, nothing glowing.",
    "Gruvbox, cidade retrô e barra densa.":
        "Gruvbox, a retro city and a dense bar.",
    "Tokyo Night com neon e barra centralizada.":
        "Tokyo Night with neon and a centred bar.",
    "Claro, quieto, para trabalhar de dia.":
        "Light and quiet, for working in daylight.",

    # ── Bundles ────────────────────────────────────────────────────────────
    "Primeira Troca": "First Change",
    "Vida no Terminal": "Life at the Terminal",
    "Descanso": "Rest",
    "O básico para o desktop deixar de ser o padrão: cor, papel de parede e "
    "uma barra que respira.":
        "The basics for a desktop that is no longer the default one: colour, "
        "a wallpaper, and a bar with room to breathe.",
    "Fastfetch completo e uma barra densa: para quem vive no prompt.":
        "Full fastfetch and a dense bar: for anybody who lives at the prompt.",
    "Claro de dia, sem barulho visual: tema claro, papel minimalista e barra "
    "limpa.":
        "Light by day and visually quiet: a light theme, a minimal wallpaper "
        "and a clean bar.",

    # ── Back to factory ────────────────────────────────────────────────────
    "Como vem de fábrica": "The way it ships",
    "A paleta que segue o seu papel de parede, que é a do Genesi novo.":
        "The palette that follows your wallpaper, which is what a new Genesi "
        "has.",
    "A tela de login do Genesi, sem nada baixado por cima.":
        "Genesi's own login screen, with nothing downloaded over it.",
    "A tranca do próprio caelestia, que segue o seu tema e o seu papel de "
    "parede.":
        "caelestia's own lock, which follows your theme and your wallpaper.",
    "Volta para o cartão do Genesi que aparece ao abrir o terminal.":
        "Back to the Genesi card your terminal opens with.",
    "O arranjo de barra que vem no Genesi novo.":
        "The bar arrangement a new Genesi has.",

    # ── Genesi's own login screens ─────────────────────────────────────────
    "A padrão do sistema": "The system's own",
    "A nossa: a marca, a hora e um campo só. Vem com a loja.":
        "Ours: the mark, the time and one field. It comes with the store.",
    "Volta para a tela que o Genesi instala. É o caminho de volta de "
    "qualquer uma das outras.":
        "Back to the screen Genesi installs. It is the way back from any of "
        "the others.",

    # ── qylock ─────────────────────────────────────────────────────────────
    "Campo": "Field",
    "Café": "Coffee",
    "Travesseiro": "Pillow",
    "Café (pixel)": "Coffee (pixel)",
    "Cidade ao Anoitecer": "City at Dusk",
    "Cachoeira": "Waterfall",
    "Guarda-chuva": "Umbrella",
    "Material You (escuro)": "Material You (dark)",
    "Bicicleta": "Bicycle",
    "Cidade Noturna": "Night City",
    "Sakura (pixel)": "Sakura (pixel)",
    "Quarto na Chuva": "Rainy Room",
    "Cão Samurai": "Samurai Dog",
    "Esmeralda": "Emerald",
    "Inverno": "Winter",
    "Cyberpunk (pixel)": "Cyberpunk (pixel)",
    "Arranha-céus": "Skyscrapers",
    "Espada": "Sword",
    "Floresta (qylock)": "Forest (qylock)",
    "A tela de título, com a fonte e tudo.":
        "The title screen, font and all.",
    "Madeira, tochas e o menu do jogo.":
        "Wood, torches and the game's own menu.",
    "Areia, serifa e o silêncio do jogo.":
        "Sand, serif and the quiet of the game.",
    "Aquele azul. Sim, aquele mesmo.": "That blue. Yes, that one.",
    "Oito bits e um ninja.": "Eight bits and a ninja.",
    "Um campo aberto e a luz baixa.": "An open field and low light.",
    "Traço oriental em vermelho e osso.":
        "Eastern linework in red and bone.",
    "Alguém tomando café, desenhado.": "Somebody having coffee, drawn.",
    "O sono que você não teve.": "The sleep you did not get.",
    "O mesmo café, em pixel art animada.":
        "The same coffee, in animated pixel art.",
    "Telhados e a última luz, em pixel.":
        "Rooftops and the last of the light, in pixel art.",
    "Água caindo, quadro a quadro.": "Falling water, frame by frame.",
    "Um pokémon dormindo na sua tela de login.":
        "A sleeping pokémon on your login screen.",
    "Chuva, um guarda-chuva e neon.": "Rain, an umbrella and neon.",
    "O desenho do Android, claro.": "Android's own look, in light.",
    "O mesmo, no escuro.": "The same, in the dark.",
    "Uma estrada, uma bicicleta, fim de tarde.":
        "A road, a bicycle, late afternoon.",
    "Art déco e um relógio parado.": "Art deco and a stopped clock.",
    "Neon em pixel, com chuva.": "Pixel neon, with rain.",
    "Pétalas caindo, quadro a quadro.": "Falling petals, frame by frame.",
    "A janela, a chuva, a luminária.": "The window, the rain, the lamp.",
    "O trem entre as estrelas.": "The train between the stars.",
    "Exatamente o que está escrito.": "Exactly what it says.",
    "Verde em pixel, do jeito da casa.":
        "Pixel green, in the house's own shade.",
    "Neve caindo devagar.": "Snow coming down slowly.",
    "Uma moto antiga e poeira.": "An old motorcycle and dust.",
    "Neon, fumaça e oito bits.": "Neon, smoke and eight bits.",
    "Vento, capa e horizonte.": "Wind, a cloak and the horizon.",
    "A cidade de cima, em pixel.": "The city from above, in pixel art.",
    "Uma lâmina e muito preto.": "A blade and a great deal of black.",
    "Hallownest, em pixel e azul.": "Hallownest, in pixel art and blue.",
    "Cinco fundos e o rosa de sempre. O maior da prateleira.":
        "Five backgrounds and the usual pink. The largest on the shelf.",
    "Mata fechada, em altíssima resolução.":
        "Deep woods, at very high resolution.",
    "Teyvat na tela de login.": "Teyvat on your login screen.",
    "O mundo depois. O mais pesado de todos.":
        "The world after. The heaviest of them all.",

    # ── astronaut ──────────────────────────────────────────────────────────
    "Astronauta": "Astronaut",
    "Buraco Negro": "Black Hole",
    "Japonesa": "Japanese",
    "Sakura (animada)": "Sakura (animated)",
    "Sakura (parada)": "Sakura (still)",
    "Folhas Roxas": "Purple Leaves",
    "Um astronauta à deriva, e o campo de senha no meio do espaço.":
        "An astronaut adrift, and the password field out in space.",
    "Fundo animado engolindo a luz. O mais pesado dos dez.":
        "An animated background swallowing the light. The heaviest of the "
        "ten.",
    "Neon rosa e ciano, chuva na cidade.":
        "Pink and cyan neon, rain over the city.",
    "A garota do Hyprland, animada.": "The Hyprland girl, animated.",
    "Hora de aventura na tela de login.":
        "Adventure Time on your login screen.",
    "Torii, montanha e um degradê de fim de tarde.":
        "A torii, a mountain and a late-afternoon gradient.",
    "Pétalas caindo em pixel art, em movimento.":
        "Falling petals in pixel art, moving.",
    "A mesma cena em pixel art, sem animação -- mais leve.":
        "The same scene in pixel art, without the animation -- lighter.",
    "Terminal verde sobre ruína. Mono e sujo, do jeito certo.":
        "A green terminal over ruin. Monospaced and grimy, in the right way.",
    "Folhagem roxa e um campo discreto embaixo.":
        "Purple foliage and a discreet field below it.",

    # ── caelestia, silent, echo, pixie, where-is-my, hypr ──────────────────
    "Silent (esquerda)": "Silent (left)",
    "Silent (direita)": "Silent (right)",
    "Silent Catppuccin Frappé": "Silent Catppuccin Frappé",
    "Cadê meu tema?": "Where's my theme?",
    "Cadê meu tema? (azul)": "Where's my theme? (blue)",
    "Cadê meu tema? (cinza)": "Where's my theme? (grey)",
    "Cadê meu tema? (nord)": "Where's my theme? (nord)",
    "Cadê meu tema? (rosé pine)": "Where's my theme? (rosé pine)",
    "Cadê meu tema? (árvore)": "Where's my theme? (tree)",
    "A tela de login igual ao bloqueio do caelestia: relógio enorme, citação, "
    "avatar. É o desktop do Genesi antes de entrar nele.":
        "The login screen as caelestia's own lock: a huge clock, a quote, an "
        "avatar. It is the Genesi desktop, before you are in it.",
    "A mesma família, reduzida ao relógio e ao campo.":
        "The same family, cut down to the clock and the field.",
    "Um cartão de vidro no meio da tela. O mais bem acabado da lista.":
        "A glass card in the middle of the screen. The most finished of the "
        "lot.",
    "O mesmo cartão, encostado à esquerda.":
        "The same card, against the left.",
    "O mesmo cartão, encostado à direita.":
        "The same card, against the right.",
    "Catppuccin escuro, o de sempre.": "Catppuccin dark, the usual one.",
    "Catppuccin um tom acima do mocha.": "Catppuccin a shade above mocha.",
    "Catppuccin morno.": "Catppuccin, lukewarm.",
    "Catppuccin claro, para quem usa tema claro.":
        "Catppuccin light, for anybody on a light theme.",
    "Verde de floresta, que é a cor da casa.":
        "Forest green, which is the house colour.",
    "Azul frio do Nord.": "Nord's cold blue.",
    "Com vídeo de fundo. Bonito, e o mais pesado da prateleira.":
        "With a video background. Handsome, and the heaviest on the shelf.",
    "Também com vídeo de fundo.": "Also with a video background.",
    "Um terminal do macOS com o log de boot correndo dentro. Você digita a "
    "senha no prompt.":
        "A macOS terminal with the boot log running inside it. You type your "
        "password at the prompt.",
    "Material You: relógio empilhado, cantos macios, cor de Pixel.":
        "Material You: a stacked clock, soft corners, Pixel colour.",
    "Fundo preto e a senha em letras gigantes. Nada mais na tela.":
        "A black background and the password in enormous letters. Nothing "
        "else on the screen.",
    "O mesmo nada, em azul.": "The same nothing, in blue.",
    "O mesmo nada, em cinza.": "The same nothing, in grey.",
    "O mesmo nada, com a paleta Nord.": "The same nothing, in Nord.",
    "O mesmo nada, em rosé pine moon.": "The same nothing, in rosé pine moon.",
    "Com uma foto atrás, para provar que dá.":
        "With a photograph behind it, to prove it can be done.",
    "O jeitão do hyprlock na tela de login: relógio empilhado, cartão no "
    "meio, paleta fixa. Não segue o seu papel de parede.":
        "hyprlock's look on the login screen: a stacked clock, a card in the "
        "middle, a fixed palette. It does not follow your wallpaper.",

    # ── Tags ───────────────────────────────────────────────────────────────
    "agua": "water",
    "animado": "animated",
    "anime": "anime",
    "antes da sessão": "before the session",
    "arch": "arch",
    "arte": "art",
    "azul": "blue",
    "barra": "bar",
    "caelestia": "caelestia",
    "calmo": "calm",
    "cartoon": "cartoon",
    "catppuccin": "catppuccin",
    "cidade": "city",
    "claro": "light",
    "combina": "matching",
    "comeco": "to start with",
    "completo": "complete",
    "curto": "short",
    "darkgreen": "darkgreen",
    "de fábrica": "factory",
    "desfoque": "blur",
    "dracula": "dracula",
    "escuro": "dark",
    "espaço": "space",
    "everblush": "everblush",
    "everforest": "everforest",
    "foto": "photo",
    "frio": "cold",
    "gruvbox": "gruvbox",
    "imagem": "image",
    "jogo": "game",
    "leve": "light-weight",
    "limpo": "clean",
    "login": "login",
    "longo": "long",
    "material": "material",
    "minimalista": "minimal",
    "moderno": "modern",
    "mono": "mono",
    "natureza": "nature",
    "neon": "neon",
    "noite": "night",
    "nord": "nord",
    "nostalgia": "nostalgia",
    "oldworld": "oldworld",
    "oled": "oled",
    "onedark": "onedark",
    "padrão": "default",
    "paisagem": "landscape",
    "pixel": "pixel",
    "quente": "warm",
    "qylock": "qylock",
    "retro": "retro",
    "rosa": "pink",
    "rosepine": "rosepine",
    "roxo": "purple",
    "rápido": "quick",
    "sessão": "session",
    "seções": "sections",
    "shadotheme": "shadotheme",
    "sixel": "sixel",
    "solarized": "solarized",
    "terminal": "terminal",
    "tokyonight": "tokyonight",
    "verde": "green",
    "vidro": "glass",
    "vídeo": "video",
}
