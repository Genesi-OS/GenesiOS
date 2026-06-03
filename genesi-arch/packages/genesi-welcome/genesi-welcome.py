#!/usr/bin/env python3
import sys
import os
import subprocess
from PyQt5.QtWidgets import QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel, QGridLayout, QFrame
from PyQt5.QtCore import Qt, QSize
from PyQt5.QtGui import QFont, QPixmap, QIcon, QColor

class GenesiWelcome(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Bem-vindo ao Genesi OS")
        self.setFixedSize(800, 600)
        self.setStyleSheet("""
            QMainWindow {
                background-color: #0A1E1A;
            }
            QLabel {
                color: white;
            }
            QPushButton {
                background-color: #0F6E56;
                color: white;
                border-radius: 10px;
                padding: 10px;
                font-size: 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1D9E75;
            }
            QFrame#card {
                background-color: rgba(15, 110, 86, 0.2);
                border: 1px solid rgba(29, 158, 117, 0.4);
                border-radius: 15px;
            }
        """)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(40, 40, 40, 40)
        main_layout.setSpacing(20)

        # Header
        header_layout = QHBoxLayout()
        
        # We assume logo is at /usr/share/pixmaps/genesi-logo.png or we just use text if not found
        logo_label = QLabel()
        logo_pixmap = QPixmap("/usr/share/pixmaps/genesi-logo.png")
        if not logo_pixmap.isNull():
            logo_label.setPixmap(logo_pixmap.scaled(80, 80, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        
        title_layout = QVBoxLayout()
        title_label = QLabel("Genesi OS")
        title_label.setFont(QFont("Segoe UI", 28, QFont.Bold))
        title_label.setStyleSheet("color: #1D9E75;")
        
        subtitle_label = QLabel("Evolua. Conecte-se. Crie.")
        subtitle_label.setFont(QFont("Segoe UI", 14))
        subtitle_label.setStyleSheet("color: #A0C0B0;")
        
        title_layout.addWidget(title_label)
        title_layout.addWidget(subtitle_label)
        
        header_layout.addWidget(logo_label)
        header_layout.addLayout(title_layout)
        header_layout.addStretch()
        
        main_layout.addLayout(header_layout)
        
        # Welcome text
        welcome_text = QLabel("Bem-vindo à nova era da computação inteligente. O Genesi OS foi projetado para extrair o máximo de desempenho com IA local e ferramentas para desenvolvedores.")
        welcome_text.setWordWrap(True)
        welcome_text.setFont(QFont("Segoe UI", 12))
        main_layout.addWidget(welcome_text)
        
        main_layout.addStretch()

        # Grid of actions
        grid = QGridLayout()
        grid.setSpacing(20)
        
        actions = [
            ("Instalar Genesi OS", "Instale o sistema no seu disco", self.launch_installer),
            ("Configurações", "Personalize o Genesi OS", self.launch_settings),
            ("Modo IA", "Gerencie o otimizador de IA", self.launch_ai_mode),
            ("Comunidade", "Junte-se a nós no GitHub", self.open_github)
        ]
        
        for i, (title, desc, callback) in enumerate(actions):
            card = QFrame()
            card.setObjectName("card")
            card_layout = QVBoxLayout(card)
            
            btn = QPushButton(title)
            btn.clicked.connect(callback)
            btn.setCursor(Qt.PointingHandCursor)
            
            desc_label = QLabel(desc)
            desc_label.setAlignment(Qt.AlignCenter)
            desc_label.setStyleSheet("color: #A0C0B0; font-size: 12px;")
            
            card_layout.addWidget(btn)
            card_layout.addWidget(desc_label)
            
            grid.addWidget(card, i // 2, i % 2)
            
        main_layout.addLayout(grid)

    def launch_installer(self):
        subprocess.Popen(["pkexec", "calamares"])

    def launch_settings(self):
        subprocess.Popen(["systemsettings"])

    def launch_ai_mode(self):
        # Prefer the full Monitor dashboard; fall back to the CLI status in a
        # terminal, then to a plain force-on, so the button always does
        # something useful even on a minimal/older install.
        import shutil
        if shutil.which("genesi-ai-monitor"):
            subprocess.Popen(["genesi-ai-monitor"])
            return
        for term in ("konsole", "xterm", "alacritty"):
            if shutil.which(term):
                subprocess.Popen([term, "-e", "bash", "-lc",
                                  "genesi-ai-mode info; echo; "
                                  "read -p 'Enter para fechar...'"])
                return
        subprocess.Popen(["genesi-ai-mode", "on"])

    def open_github(self):
        subprocess.Popen(["xdg-open", "https://github.com/zFreshy/GenesiOS"])

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = GenesiWelcome()
    window.show()
    sys.exit(app.exec_())
