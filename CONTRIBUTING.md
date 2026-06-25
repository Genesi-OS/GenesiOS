# Contributing to Genesi OS

Thank you for your interest in contributing to Genesi OS! This document provides guidelines and instructions for contributing.

## 🌟 Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest new features
- 🔧 Submit code improvements
- 📖 Improve documentation
- 🎨 Design improvements
- 🧪 Test pre-releases
- 🌍 Translations (future)

## 📋 Before You Start

1. **Check existing issues**: Someone might already be working on it
2. **Read the roadmap**: See [ROADMAP.md](docs/ROADMAP.md)
3. **Join discussions**: Ask questions in [Discussions](https://github.com/Genesi-OS/GenesiOS/discussions)

## 🐛 Reporting Bugs

### Before Reporting

- Search [existing issues](https://github.com/Genesi-OS/GenesiOS/issues)
- Test on latest version
- Check if it's a CachyOS/Arch issue

### Bug Report Template

```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**System Info**
- Genesi OS version: [e.g. 2026.05.01]
- Kernel: [run `uname -r`]
- Desktop: [KDE Plasma version]
- Hardware: [CPU, RAM, GPU]

**Logs**
```bash
# Relevant logs
journalctl -b -p err
```

**Additional context**
Any other relevant information.
```

## 💡 Suggesting Features

### Feature Request Template

```markdown
**Is your feature request related to a problem?**
A clear description of the problem.

**Describe the solution you'd like**
What you want to happen.

**Describe alternatives you've considered**
Other solutions you've thought about.

**Additional context**
Mockups, examples, or references.
```

## 🔧 Code Contributions

### Development Setup

```bash
# Clone repository
git clone https://github.com/Genesi-OS/GenesiOS
cd GenesiOS

# Install dependencies (on CachyOS/Arch)
sudo pacman -S base-devel archiso git

# Build packages
cd genesi-arch/packages
bash build-packages.sh

# Build ISO
cd ..
sudo ./buildiso.sh -p desktop
```

### Coding Standards

#### Shell Scripts
- Use `#!/usr/bin/env bash`
- Use `set -e` for error handling
- Add comments for complex logic
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

#### Python
- Follow [PEP 8](https://pep8.org/)
- Use type hints
- Add docstrings
- Use `black` for formatting

#### PKGBUILD
- Follow [Arch PKGBUILD guidelines](https://wiki.archlinux.org/title/PKGBUILD)
- Use `SKIP` for local sources
- Add comments for patches

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: fix bug
docs: update documentation
style: formatting changes
refactor: code refactoring
test: add tests
chore: maintenance tasks
```

Examples:
```
feat: add manual toggle to AI Mode widget
fix: AI Mode not detecting llama.cpp processes
docs: update installation guide with screenshots
```

### Pull Request Process

1. **Fork the repository**
2. **Create a branch**: `git checkout -b feature/my-feature`
3. **Make changes**: Follow coding standards
4. **Test thoroughly**: Build and test ISO
5. **Commit**: Use conventional commits
6. **Push**: `git push origin feature/my-feature`
7. **Open PR**: Use PR template

### PR Template

```markdown
**Description**
What does this PR do?

**Related Issue**
Fixes #123

**Type of Change**
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

**Testing**
How was this tested?
- [ ] Built ISO successfully
- [ ] Tested in VM
- [ ] Tested on real hardware

**Screenshots**
If applicable.

**Checklist**
- [ ] Code follows style guidelines
- [ ] Self-reviewed code
- [ ] Commented complex code
- [ ] Updated documentation
- [ ] No new warnings
- [ ] Added tests (if applicable)
```

## 📖 Documentation Contributions

### Documentation Structure

```
docs/
├── installation.md      # Installation guide
├── features.md          # Feature overview
├── faq.md              # Frequently asked questions
├── troubleshooting.md  # Common issues
└── ROADMAP.md          # Development roadmap
```

### Documentation Standards

- Use clear, simple language
- Add code examples
- Include screenshots
- Test all commands
- Keep up to date

## 🎨 Design Contributions

### Design Guidelines

- **Colors**: Verde Genesis #1D9E75, Floresta #04342C, Menta #E1F5EE
- **Style**: Glassmorphism (blur + transparency)
- **Icons**: Rounded, modern
- **Typography**: Noto Sans, Fira Sans

### Submitting Designs

- Create mockups in Figma/Inkscape
- Export as PNG (high resolution)
- Open issue with designs
- Explain design decisions

## 🧪 Testing

### Testing Checklist

- [ ] ISO builds successfully
- [ ] Boots in VirtualBox
- [ ] Boots on real hardware
- [ ] Installation completes
- [ ] Branding persists after install
- [ ] AI Mode works
- [ ] Updates work
- [ ] No regressions

### Reporting Test Results

```markdown
**Test Environment**
- VM: VirtualBox 7.0
- RAM: 8GB
- CPU: 4 cores
- Disk: 50GB

**Test Results**
- [x] ISO boots
- [x] Installation works
- [x] AI Mode activates
- [ ] Widget not showing (bug)

**Logs**
Attach relevant logs.
```

## 🌍 Translations (Future)

We plan to support multiple languages. Stay tuned!

## 📜 License

By contributing, you agree that your contributions will be licensed under GPL-3.0.

## ❓ Questions?

- Open a [Discussion](https://github.com/Genesi-OS/GenesiOS/discussions)
- Check [FAQ](docs/faq.md)
- Read [Documentation](docs/)

## 🙏 Thank You!

Every contribution helps make Genesi OS better. We appreciate your time and effort!

---

**Happy Contributing! 🚀**
