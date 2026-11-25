/*
 * kcmgenesiupdate.h — the Genesi update page inside Plasma's System Settings.
 *
 * The update UI belongs where a user already looks for settings, not in a
 * program of its own. On caelestia that meant filling in the Nexus page it
 * already registered; on Plasma it means a KCM, because Plasma 6 has no other
 * way in: KQuickConfigModule is the base class for every QML KCM and
 * kcmutils_add_qml_kcm() builds it as a plugin. There is no pure-QML path.
 *
 * All the process work lives here rather than in QML. A KCM's QML has no way
 * to run a command — unlike Quickshell, which has Process — so the C++ side is
 * not ceremony, it is the only place the work can happen.
 *
 * The single privileged operation is delegated to genesi-update-center-apply,
 * a root-owned script that takes no argument reaching pacman, with the polkit
 * action pinning exec.path to it. Nothing in this class can widen that: the
 * argv below is a literal.
 */
#pragma once

#include <KQuickConfigModule>
#include <QVariantList>

class QProcess;

class KcmGenesiUpdate : public KQuickConfigModule
{
    Q_OBJECT

    /** checking | current | available | error */
    Q_PROPERTY(QString updateState READ updateState NOTIFY updatesChanged)
    /** [{name, from, to}] — what actually changes, not just how many */
    Q_PROPERTY(QVariantList packages READ packages NOTIFY updatesChanged)
    Q_PROPERTY(QString channel READ channel NOTIFY systemChanged)
    Q_PROPERTY(QString lastUpdate READ lastUpdate NOTIFY systemChanged)
    /** Whether snap-pac brackets pacman transactions on this machine. */
    Q_PROPERTY(bool canRollback READ canRollback NOTIFY systemChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    /** Live output while an update runs, so the user is never staring at a
     *  frozen dialog wondering whether it died. */
    Q_PROPERTY(QString log READ log NOTIFY logChanged)

public:
    explicit KcmGenesiUpdate(QObject *parent, const KPluginMetaData &data);
    ~KcmGenesiUpdate() override;

    QString updateState() const { return m_updateState; }
    QVariantList packages() const { return m_packages; }
    QString channel() const { return m_channel; }
    QString lastUpdate() const { return m_lastUpdate; }
    bool canRollback() const { return m_canRollback; }
    bool busy() const { return m_busy; }
    QString log() const { return m_log; }

    /** Re-read what is available. Safe to call at any time. */
    Q_INVOKABLE void checkUpdates();
    /** The one privileged action. Fixed argv; see the file header. */
    Q_INVOKABLE void applyUpdates();

Q_SIGNALS:
    void updatesChanged();
    void systemChanged();
    void busyChanged();
    void logChanged();
    /** rc, and a sentence a person can act on. */
    void applyFinished(int rc, const QString &message);

private:
    void setBusy(bool v);
    void appendLog(const QString &line);
    void readSystemInfo();

    QString m_updateState = QStringLiteral("checking");
    QVariantList m_packages;
    QString m_channel;
    QString m_lastUpdate;
    QString m_log;
    bool m_canRollback = false;
    bool m_busy = false;

    QProcess *m_check = nullptr;
    QProcess *m_apply = nullptr;
};
