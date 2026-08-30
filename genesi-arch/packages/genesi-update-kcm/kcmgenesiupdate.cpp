#include "kcmgenesiupdate.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTextStream>

K_PLUGIN_CLASS_WITH_JSON(KcmGenesiUpdate, "kcm_genesi_update.json")

namespace
{
/** The privileged helper. A literal, never built from anything the UI holds. */
const char *APPLY_HELPER = "/usr/bin/genesi-update-center-apply";
}

KcmGenesiUpdate::KcmGenesiUpdate(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    readSystemInfo();
    checkUpdates();
}

KcmGenesiUpdate::~KcmGenesiUpdate()
{
    // A running `pacman -Su` must NOT be killed because a settings page was
    // closed: a half-applied transaction is far worse than an orphaned
    // process, and pacman's own lock is what keeps the system consistent.
    // The check is cheap and interruptible, so that one may go.
    if (m_check && m_check->state() != QProcess::NotRunning) {
        m_check->kill();
        m_check->waitForFinished(2000);
    }
}

void KcmGenesiUpdate::setBusy(bool v)
{
    if (m_busy == v) {
        return;
    }
    m_busy = v;
    Q_EMIT busyChanged();
}

void KcmGenesiUpdate::appendLog(const QString &line)
{
    m_log += line;
    if (!line.endsWith(QLatin1Char('\n'))) {
        m_log += QLatin1Char('\n');
    }
    Q_EMIT logChanged();
}

void KcmGenesiUpdate::readSystemInfo()
{
    // Which channel this machine follows. genesi-channel is the single source
    // of truth; parsing pacman.conf ourselves would be a second one, and the
    // two would drift.
    QProcess ch;
    ch.start(QStringLiteral("genesi-channel"), {QStringLiteral("get")});
    if (ch.waitForFinished(5000) && ch.exitCode() == 0) {
        m_channel = QString::fromUtf8(ch.readAllStandardOutput()).trimmed();
    }

    // Whether this update can be undone. snap-pac already brackets every
    // pacman transaction with a snapshot on a Btrfs install -- Genesi has done
    // this all along and has never told anyone, which is the most reassuring
    // thing an updater could possibly say.
    m_canRollback = !QStandardPaths::findExecutable(QStringLiteral("snapper")).isEmpty()
        && QFileInfo::exists(QStringLiteral("/etc/snapper/configs/root"));

    // Last upgrade, from pacman's own log. Tracking it separately would be a
    // second source of truth about the same fact.
    QFile log(QStringLiteral("/var/log/pacman.log"));
    if (log.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&log);
        QString last;
        while (!in.atEnd()) {
            const QString line = in.readLine();
            if (line.contains(QLatin1String("starting full system upgrade"))) {
                last = line;
            }
        }
        const int close = last.indexOf(QLatin1Char(']'));
        if (last.startsWith(QLatin1Char('[')) && close > 1) {
            m_lastUpdate = last.mid(1, close - 1);
        }
    }

    Q_EMIT systemChanged();
}

void KcmGenesiUpdate::checkUpdates()
{
    if (m_check && m_check->state() != QProcess::NotRunning) {
        return;
    }

    m_updateState = QStringLiteral("checking");
    Q_EMIT updatesChanged();

    if (!m_check) {
        m_check = new QProcess(this);
        connect(m_check, &QProcess::finished, this, [this](int rc, QProcess::ExitStatus) {
            const QString out = QString::fromUtf8(m_check->readAllStandardOutput());
            m_packages.clear();

            const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &raw : lines) {
                const QString line = raw.trimmed();
                if (line.isEmpty()) {
                    continue;
                }
                const QStringList p = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                QVariantMap pkg;
                pkg[QStringLiteral("name")] = p.value(0);
                pkg[QStringLiteral("from")] = p.value(1);
                // "name old -> new"
                pkg[QStringLiteral("to")] = (p.value(2) == QLatin1String("->")) ? p.value(3) : QString();
                m_packages.append(pkg);
            }

            // checkupdates exits 2 for "nothing to do". Treating that happy
            // answer as an error is how an updater starts crying wolf, and a
            // user who has been cried wolf at stops reading the notification
            // that finally matters.
            if (rc != 0 && rc != 2) {
                m_updateState = QStringLiteral("error");
            } else {
                m_updateState = m_packages.isEmpty() ? QStringLiteral("current")
                                                     : QStringLiteral("available");
            }
            setBusy(false);
            Q_EMIT updatesChanged();
        });
    }

    setBusy(true);
    // `checkupdates` (pacman-contrib) syncs into a PRIVATE database, so it
    // needs no root and can never leave the real one half-synced -- the
    // `pacman -Sy` footgun that produces a partial upgrade later. Falling back
    // to `pacman -Qu` reads what is already on disk, which can be stale but is
    // never wrong about what it does know.
    if (!QStandardPaths::findExecutable(QStringLiteral("checkupdates")).isEmpty()) {
        m_check->start(QStringLiteral("checkupdates"), {});
    } else {
        m_check->start(QStringLiteral("pacman"), {QStringLiteral("-Qu")});
    }
}

void KcmGenesiUpdate::applyUpdates()
{
    if (m_apply && m_apply->state() != QProcess::NotRunning) {
        return;
    }

    m_log.clear();
    Q_EMIT logChanged();

    if (!m_apply) {
        m_apply = new QProcess(this);
        m_apply->setProcessChannelMode(QProcess::MergedChannels);

        connect(m_apply, &QProcess::readyReadStandardOutput, this, [this] {
            appendLog(QString::fromUtf8(m_apply->readAllStandardOutput()));
        });

        connect(m_apply, &QProcess::finished, this, [this](int rc, QProcess::ExitStatus) {
            setBusy(false);

            QString msg;
            if (rc == 0) {
                msg = i18n("System updated.");
            } else if (rc == 2) {
                msg = i18n("Nothing to update — already up to date.");
            } else if (rc == 126 || rc == 127) {
                // pkexec's own "cancelled / not authorised". Calling that a
                // failed update would be a lie: nothing was attempted and
                // nothing changed.
                msg = i18n("Authentication cancelled. Nothing was changed.");
            } else {
                msg = i18n("The update failed. Nothing was left half-applied.");
            }

            Q_EMIT applyFinished(rc, msg);
            readSystemInfo();
            checkUpdates();
        });
    }

    setBusy(true);
    // A FIXED argv. No element comes from the UI, so there is nothing here for
    // a crafted package name or a stray click to influence. pkexec raises the
    // privilege; the helper decides what the privilege is spent on.
    m_apply->start(QStringLiteral("pkexec"), {QString::fromUtf8(APPLY_HELPER)});
}

#include "kcmgenesiupdate.moc"
