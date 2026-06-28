#pragma once
#include <QObject>
#include <QAbstractListModel>
#include <QString>
#include <QList>
#include <QProcess>

// ── Data carrier for one installed game ─────────────────────────────────────
struct SteamGame {
    QString appId;       // e.g. "570"
    QString name;        // e.g. "Dota 2"
    QString coverUrl;    // Steam CDN portrait cover (600×900)
    QString logoUrl;     // Steam CDN hero logo
    bool    installed;   // true = appmanifest present
    qint64  sizeOnDisk;  // bytes
    QString lastPlayed;  // unix timestamp string from acf, or ""
};

// ── Qt list model exposed to QML as "SteamLibrary" context property ──────────
class SteamLibraryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int  count   READ rowCount NOTIFY countChanged)

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

    explicit SteamLibraryModel(QObject *parent = nullptr);

    // QAbstractListModel
    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool loading() const { return m_loading; }

    // Called from QML
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void launchGame(const QString &appId);
    Q_INVOKABLE void installGame(const QString &appId);  // opens store page

signals:
    void loadingChanged();
    void countChanged();
    void errorOccurred(const QString &message);

private:
    // VDF helpers
    static QStringList  findLibraryRoots();
    static QList<SteamGame> parseLibraryRoot(const QString &libraryPath);
    static SteamGame        parseAppManifest(const QString &acfPath);
    static QString          steamBasePath();

    QList<SteamGame> m_games;
    bool             m_loading = false;

    void setLoading(bool v);
    void setGames(QList<SteamGame> games);
};
