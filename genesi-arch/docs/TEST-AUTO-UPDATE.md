# Testando o Sistema de Atualização Automática

## 🧪 Guia de Teste Completo

### Pré-requisitos

- Genesi OS instalado (ou ISO bootada)
- Acesso à internet
- Terminal e acesso root

---

## Teste 1: Verificar Instalação

```bash
# Verificar se pacote está instalado
pacman -Q genesi-updater

# Verificar arquivos instalados
ls -la /usr/local/bin/genesi-updater
ls -la /usr/lib/systemd/system/genesi-updater.*
ls -la /usr/share/plasma/plasmoids/org.genesi.updater/

# Verificar timer
systemctl status genesi-updater.timer
```

**Resultado esperado**:
```
● genesi-updater.timer - Genesi OS Update Checker Timer
   Loaded: loaded
   Active: active (waiting)
```

---

## Teste 2: Executar Verificação Manual

```bash
# Rodar daemon manualmente
sudo /usr/local/bin/genesi-updater

# Ver logs
sudo journalctl -u genesi-updater -n 20

# Ver estado salvo
cat /var/lib/genesi-updater/state.json
```

**Resultado esperado**:
```json
{
  "last_check": "2026-05-01T14:30:00",
  "updates_available": 0,
  "packages": []
}
```

---

## Teste 3: Simular Updates Disponíveis

```bash
# Ver updates reais disponíveis
checkupdates

# Se houver updates, o daemon deve detectar
sudo /usr/local/bin/genesi-updater

# Verificar flag file
cat /tmp/genesi-updates-available
# Deve mostrar número de updates
```

**Resultado esperado**:
- Notificação desktop aparece
- Flag file criado com número de updates
- State file atualizado

---

## Teste 4: Verificar Notificações

```bash
# Iniciar notifier manualmente (se não estiver rodando)
/usr/local/bin/genesi-update-notifier &

# Criar flag file manualmente para testar
echo "5" > /tmp/genesi-updates-available

# Aguardar 5 segundos
# Notificação deve aparecer
```

**Resultado esperado**:
```
🔄 5 Updates Available
Packages: ...
Click the update icon in the taskbar to install.
```

---

## Teste 5: Verificar Widget

```bash
# Reiniciar Plasma (se widget não aparecer)
kquitapp5 plasmashell && kstart5 plasmashell

# Adicionar widget manualmente se necessário:
# Right-click taskbar → Add Widgets → Search "Genesi Updater"
```

**Resultado esperado**:
- Widget aparece na taskbar
- Se houver updates: ícone pulsante + badge com número
- Se não houver: ícone estático com check verde

---

## Teste 6: Testar Popup do Widget

```bash
# Clicar no widget
# Popup deve abrir mostrando:
```

**Resultado esperado**:
- Lista de pacotes com versões (old → new)
- Botão "Update All"
- Botão "Check" para forçar verificação
- Botão "Details" para ver no terminal

---

## Teste 7: Testar Atualização via Discover

```bash
# Clicar em "Update All" no widget
# OU abrir Discover manualmente:
plasma-discover --mode Update
```

**Resultado esperado**:
- Discover abre na aba "Updates"
- Lista de updates aparece
- Botão "Update All" disponível
- Após update, widget volta ao normal

---

## Teste 8: Verificar Timer Automático

```bash
# Ver próxima execução
systemctl list-timers genesi-updater.timer

# Forçar execução do timer
sudo systemctl start genesi-updater.service

# Ver logs em tempo real
sudo journalctl -u genesi-updater -f
```

**Resultado esperado**:
```
NEXT                         LEFT     LAST                         PASSED  UNIT
Fri 2026-05-01 15:30:00 UTC  45min    Fri 2026-05-01 14:30:00 UTC  15min   genesi-updater.timer
```

---

## Teste 9: Testar Configuração

```bash
# Editar config
sudo nano /etc/genesi-updater.conf

# Mudar intervalo para 5 minutos (para teste)
check_interval=300

# Reiniciar timer
sudo systemctl restart genesi-updater.timer

# Verificar se respeita novo intervalo
systemctl list-timers genesi-updater.timer
```

**Resultado esperado**:
- Timer usa novo intervalo
- Próxima execução em ~5 minutos

---

## Teste 10: Testar GitHub Actions (Desenvolvedor)

```bash
# Fazer mudança em um pacote
cd genesi-arch/packages/genesi-updater
nano PKGBUILD
# Incrementar pkgrel=2

# Commit e push
git add .
git commit -m "test: bump genesi-updater version"
git push origin arch-base

# Aguardar GitHub Actions (~5-10 min)
# Ver em: https://github.com/Genesi-OS/GenesiOS/actions

# Verificar release criado
# Ver em: https://github.com/Genesi-OS/GenesiOS/releases
```

**Resultado esperado**:
- GitHub Actions roda automaticamente
- Release criado com timestamp
- Pacotes `.pkg.tar.zst` publicados
- Database `genesi.db.tar.gz` atualizado

---

## Teste 11: Testar Update Real

```bash
# Forçar refresh do database
sudo pacman -Syy

# Ver updates disponíveis
checkupdates | grep genesi

# Atualizar
sudo pacman -S genesi-updater

# Verificar nova versão
pacman -Q genesi-updater
```

**Resultado esperado**:
- Pacote atualizado com sucesso
- Nova versão instalada
- Daemon reiniciado automaticamente

---

## Teste 12: Stress Test

```bash
# Rodar daemon múltiplas vezes seguidas
for i in {1..10}; do
    echo "Run $i"
    sudo /usr/local/bin/genesi-updater
    sleep 2
done

# Verificar se não há erros
sudo journalctl -u genesi-updater -n 50
```

**Resultado esperado**:
- Todas as execuções bem-sucedidas
- Sem erros nos logs
- State file consistente

---

## Checklist de Funcionalidades

- [ ] Daemon instala corretamente
- [ ] Timer habilitado automaticamente
- [ ] Verificação manual funciona
- [ ] State file é criado e atualizado
- [ ] Flag file é criado quando há updates
- [ ] Notificações aparecem
- [ ] Widget aparece na taskbar
- [ ] Widget mostra badge correto
- [ ] Popup do widget funciona
- [ ] Botão "Update All" abre Discover
- [ ] Discover mostra updates
- [ ] Updates instalam corretamente
- [ ] Widget volta ao normal após update
- [ ] Timer executa automaticamente
- [ ] Configuração é respeitada
- [ ] Logs são gerados corretamente
- [ ] GitHub Actions publica pacotes
- [ ] Repository database é atualizado
- [ ] Pacman sincroniza com repo
- [ ] Updates reais funcionam

---

## Troubleshooting Durante Testes

### Daemon não roda
```bash
# Ver erro detalhado
sudo /usr/local/bin/genesi-updater
python3 -c "import sys; print(sys.version)"
pacman -Q python python-requests python-packaging
```

### Notificações não aparecem
```bash
# Testar notify-send
notify-send "Test" "This is a test"

# Verificar se notifier está rodando
ps aux | grep genesi-update-notifier

# Reiniciar
killall genesi-update-notifier
/usr/local/bin/genesi-update-notifier &
```

### Widget não aparece
```bash
# Verificar arquivos
ls -la /usr/share/plasma/plasmoids/org.genesi.updater/

# Verificar metadata
cat /usr/share/plasma/plasmoids/org.genesi.updater/metadata.json

# Reiniciar Plasma
kquitapp5 plasmashell && kstart5 plasmashell
```

### Timer não executa
```bash
# Ver status
systemctl status genesi-updater.timer

# Habilitar se desabilitado
sudo systemctl enable --now genesi-updater.timer

# Ver logs
sudo journalctl -u genesi-updater.timer -f
```

---

## Métricas de Sucesso

✅ **Funcionalidade**: Todas as funcionalidades do checklist funcionam  
✅ **Performance**: Daemon usa <10MB RAM, executa em <5s  
✅ **Confiabilidade**: 100% das verificações bem-sucedidas  
✅ **UX**: Notificações aparecem em <5s após detecção  
✅ **Integração**: Discover abre e instala updates corretamente  

---

## Próximos Passos Após Testes

1. [ ] Documentar bugs encontrados
2. [ ] Ajustar configurações padrão
3. [ ] Melhorar mensagens de erro
4. [ ] Adicionar mais logs de debug
5. [ ] Criar testes automatizados
6. [ ] Preparar para release público

---

**Status**: Pronto para testar

**Tempo estimado**: 30-45 minutos para todos os testes

**Última atualização**: 2026-05-01
