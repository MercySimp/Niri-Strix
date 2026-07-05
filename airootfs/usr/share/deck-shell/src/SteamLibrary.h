#pragma once
#include <QObject>
#include <QAbstractListModel>
#include <QString>
#include <QList>
#include <QProcess>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFileSystemWatcher>

struct SteamGame {
    QString appId;
    QString name;
    QString coverUrl;
    QString logoUrl;
    bool    installed;
    qint64  sizeOnDisk;
    QString lastPlayed;
};

class SteamLibraryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool    loading    READ loading    NOTIFY loadingChanged)
    Q_PROPERTY(int     count      READ rowCount   NOTIFY countChanged)
    Q_PROPERTY(int     filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)
    Q_PROPERTY(QString homePath   READ homePath   CONSTANT)

public:
    enum Roles {
        AppIdRole = Qt::UserRole + 1,
        NameRole,
        CoverUrlRole,
        LogoUrlRole,
        InstalledRole,
        SizeRole,
        LastPlayedRole
    };

    enum FilterMode {
        InstalledOnly = 0,
        AllOwned      = 1
    };
    Q_ENUM(FilterMode)

    explicit SteamLibraryModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool    loading()    const { return m_loading; }
    int     filterMode() const { return m_filterMode; }
    QString homePath()   const { return QDir::homePath(); }

    void setFilterMode(int mode);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void launchGame(const QString &appId);
    Q_INVOKABLE void installGame(const QString &appId);
    Q_INVOKABLE void uninstallGame(const QString &appId);
    Q_INVOKABLE void fetchOwnedGamesForId(const QString &steamId);

signals:
    void loadingChanged();
    void countChanged();
    void errorOccurred(const QString &message);
    void filterModeChanged();
    // Emitted when installGame() is called so QML can show a toast.
    void installRequested(const QString &appId, const QString &name);

private slots:
    void handleLibraryReply(QNetworkReply *reply);
    void onWatchedDirChanged(const QString &path);

private:
    static QStringList      findLibraryRoots();
    static QList<SteamGame> parseLibraryRoot(const QString &libraryPath);
    static SteamGame        parseAppManifest(const QString &acfPath);
    static QString          steamBasePath();

    void watchLibraryRoots();

    QList<SteamGame> m_gamesLocal;
    QList<SteamGame> m_gamesMerged;
    bool             m_loading        = false;
    int              m_filterMode     = InstalledOnly;
    int              m_installedCount = 0;
    // Pending steamId for re-merge after auto-refresh
    QString          m_lastSteamId;

    QNetworkAccessManager m_nam;
    QFileSystemWatcher    m_watcher;

    void setLoading(bool v);
    void setMergedGames(QList<SteamGame> games);
};
