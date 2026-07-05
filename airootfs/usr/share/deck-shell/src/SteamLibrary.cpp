#include "SteamLibrary.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QDebug>
#include <algorithm>

static QString backendUrl()
{
    QByteArray env = qgetenv("DECK_BACKEND_URL");
    return env.isEmpty()
        ? QStringLiteral("https://api.accesshomeserver.uk")
        : QString::fromUtf8(env);
}

// ---------------------------------------------------------------------------
// VDF helpers
// ---------------------------------------------------------------------------
static QString vdfValue(const QStringList &lines, const QString &key)
{
    QRegularExpression re(
        QStringLiteral("^\\s*\"") + QRegularExpression::escape(key) +
        QStringLiteral("\"\\s+\"([^\"]*)\""));
    for (const QString &line : lines) {
        auto m = re.match(line);
        if (m.hasMatch()) return m.captured(1);
    }
    return {};
}

// ---------------------------------------------------------------------------
// Local Steam library scanning
// ---------------------------------------------------------------------------
QString SteamLibraryModel::steamBasePath()
{
    for (const QString &p : {
            QDir::homePath() + "/.steam/steam",
            QDir::homePath() + "/.local/share/Steam",
            QDir::homePath() + "/.var/app/com.valvesoftware.Steam/data/Steam"
         }) {
        if (QDir(p).exists()) return p;
    }
    return {};
}

QStringList SteamLibraryModel::findLibraryRoots()
{
    QString base = steamBasePath();
    if (base.isEmpty()) return {};

    QStringList roots;
    auto addRoot = [&](const QString &path) {
        QDir d(path);
        QString canon = d.canonicalPath();
        if (canon.isEmpty()) canon = d.absolutePath();
        if (!roots.contains(canon)) roots << canon;
    };

    addRoot(base + "/steamapps");

    QFile f(base + "/steamapps/libraryfolders.vdf");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return roots;

    QTextStream in(&f);
    QStringList lines;
    while (!in.atEnd()) lines << in.readLine();

    QRegularExpression pathRe(R"rx(^\s*"path"\s+"([^"]+)")rx");
    QRegularExpression legacyRe(R"rx(^\s*"[0-9]+"\s+"(/[^"]+)")rx");
    for (const QString &line : lines) {
        auto m = pathRe.match(line);
        if (m.hasMatch()) { addRoot(m.captured(1) + "/steamapps"); continue; }
        auto m2 = legacyRe.match(line);
        if (m2.hasMatch()) addRoot(m2.captured(1) + "/steamapps");
    }
    return roots;
}

SteamGame SteamLibraryModel::parseAppManifest(const QString &acfPath)
{
    QFile f(acfPath);
    SteamGame g{};
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return g;

    QTextStream in(&f);
    QStringList lines;
    while (!in.atEnd()) lines << in.readLine();

    g.appId      = vdfValue(lines, "appid");
    g.name       = vdfValue(lines, "name");
    g.lastPlayed = vdfValue(lines, "LastPlayed");
    QString sz   = vdfValue(lines, "SizeOnDisk");
    g.sizeOnDisk = sz.isEmpty() ? 0 : sz.toLongLong();
    g.installed  = !g.appId.isEmpty() && !g.name.isEmpty();
    g.coverUrl   = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/library_600x900.jpg").arg(g.appId);
    g.logoUrl    = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/header.jpg").arg(g.appId);
    return g;
}

QList<SteamGame> SteamLibraryModel::parseLibraryRoot(const QString &path)
{
    QList<SteamGame> games;
    QDir dir(path);
    if (!dir.exists()) return games;
    for (const QString &fn : dir.entryList({"appmanifest_*.acf"}, QDir::Files)) {
        SteamGame g = parseAppManifest(dir.filePath(fn));
        if (g.installed) games << g;
    }
    return games;
}

// ---------------------------------------------------------------------------
// Watch steamapps dirs so the grid auto-updates when games install/uninstall.
// ---------------------------------------------------------------------------
void SteamLibraryModel::watchLibraryRoots()
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    const QStringList roots = findLibraryRoots();
    if (!roots.isEmpty())
        m_watcher.addPaths(roots);
}

void SteamLibraryModel::onWatchedDirChanged(const QString &path)
{
    Q_UNUSED(path)
    qDebug() << "[SteamLibrary] steamapps dir changed, auto-refreshing";
    if (!m_lastSteamId.isEmpty())
        fetchOwnedGamesForId(m_lastSteamId);
    else
        refresh();
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
SteamLibraryModel::SteamLibraryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_nam,     &QNetworkAccessManager::finished,
            this,       &SteamLibraryModel::handleLibraryReply);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this,       &SteamLibraryModel::onWatchedDirChanged);
    refresh();
}

void SteamLibraryModel::setLoading(bool v)
{
    if (m_loading == v) return;
    m_loading = v;
    emit loadingChanged();
}

void SteamLibraryModel::setMergedGames(QList<SteamGame> games)
{
    beginResetModel();
    m_gamesMerged = std::move(games);
    m_installedCount = 0;
    for (const SteamGame &g : m_gamesMerged)
        if (g.installed) ++m_installedCount;
    endResetModel();
    emit countChanged();
}

void SteamLibraryModel::setFilterMode(int mode)
{
    if (mode == m_filterMode) return;
    m_filterMode = mode;
    beginResetModel();
    endResetModel();
    emit filterModeChanged();
    emit countChanged();
}

void SteamLibraryModel::refresh()
{
    setLoading(true);
    QList<SteamGame> local;
    for (const QString &root : findLibraryRoots())
        local << parseLibraryRoot(root);
    std::sort(local.begin(), local.end(), [](const SteamGame &a, const SteamGame &b) {
        return a.name.toLower() < b.name.toLower();
    });
    m_gamesLocal = local;
    setMergedGames(local);
    watchLibraryRoots();
    setLoading(false);
}

void SteamLibraryModel::fetchOwnedGamesForId(const QString &steamId)
{
    if (steamId.isEmpty()) return;
    m_lastSteamId = steamId;
    setLoading(true);

    QUrl url(backendUrl() + QStringLiteral("/library/owned"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("steamid"), steamId);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    m_nam.get(req);
}

void SteamLibraryModel::handleLibraryReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[SteamLibrary] backend error:" << reply->errorString();
        setMergedGames(m_gamesLocal);
        setLoading(false);
        emit errorOccurred(QStringLiteral("Could not reach backend: %1").arg(reply->errorString()));
        return;
    }

    QByteArray raw = reply->readAll();
    qDebug() << "[SteamLibrary] /library/owned response:" << raw.left(200);

    QJsonDocument doc = QJsonDocument::fromJson(raw);
    QJsonArray arr    = doc.object().value(QStringLiteral("games")).toArray();

    if (arr.isEmpty()) {
        qWarning() << "[SteamLibrary] backend returned empty games array";
        setMergedGames(m_gamesLocal);
        setLoading(false);
        return;
    }

    QHash<QString, SteamGame> localById;
    for (const SteamGame &g : m_gamesLocal)
        localById.insert(g.appId, g);

    QList<SteamGame> merged;
    merged.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        QJsonObject obj  = v.toObject();
        const QString id = obj.value(QStringLiteral("appId")).toString();
        const QString nm = obj.value(QStringLiteral("name")).toString();
        if (id.isEmpty() || nm.isEmpty()) continue;

        SteamGame g;
        if (localById.contains(id)) {
            g = localById.value(id);
        } else {
            g.appId     = id;
            g.name      = nm;
            g.installed = false;
            g.coverUrl  = obj.value(QStringLiteral("coverUrl")).toString(
                          QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/library_600x900.jpg").arg(id));
            g.logoUrl   = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/header.jpg").arg(id);
        }
        merged << g;
    }

    std::sort(merged.begin(), merged.end(), [](const SteamGame &a, const SteamGame &b) {
        return a.name.toLower() < b.name.toLower();
    });

    setMergedGames(merged.isEmpty() ? m_gamesLocal : merged);
    setLoading(false);
}

void SteamLibraryModel::launchGame(const QString &appId)
{
    QProcess::startDetached(QStringLiteral("steam"), { QStringLiteral("-applaunch"), appId });
}

void SteamLibraryModel::installGame(const QString &appId)
{
    // Look up game name for the toast signal.
    QString name;
    for (const SteamGame &g : m_gamesMerged)
        if (g.appId == appId) { name = g.name; break; }

    // Trigger the Steam install URI. The steam-install-confirm.sh watcher
    // service running in the background will intercept the dialog that
    // appears and auto-click "Install" using xdotool, so the user never
    // sees the confirmation popup.
    qDebug() << "[SteamLibrary] installGame:" << appId;
    QProcess::startDetached(QStringLiteral("steam"),
        { QStringLiteral("steam://install/") + appId });

    emit installRequested(appId, name);
}

void SteamLibraryModel::uninstallGame(const QString &appId)
{
    QProcess::startDetached(QStringLiteral("steam"),
        { QStringLiteral("steam://uninstall/") + appId });
}

int SteamLibraryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return (m_filterMode == InstalledOnly) ? m_installedCount : m_gamesMerged.size();
}

QVariant SteamLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) return {};
    const int row = index.row();
    const SteamGame *g = nullptr;

    if (m_filterMode == InstalledOnly) {
        int i = 0;
        for (const SteamGame &candidate : m_gamesMerged) {
            if (candidate.installed) {
                if (i == row) { g = &candidate; break; }
                ++i;
            }
        }
    } else {
        if (row >= 0 && row < m_gamesMerged.size())
            g = &m_gamesMerged.at(row);
    }

    if (!g) return {};
    switch (role) {
    case AppIdRole:      return g->appId;
    case NameRole:       return g->name;
    case CoverUrlRole:   return g->coverUrl;
    case LogoUrlRole:    return g->logoUrl;
    case InstalledRole:  return g->installed;
    case SizeRole:       return g->sizeOnDisk;
    case LastPlayedRole: return g->lastPlayed;
    }
    return {};
}

QHash<int, QByteArray> SteamLibraryModel::roleNames() const
{
    return {
        { AppIdRole,      "appId"      },
        { NameRole,       "name"       },
        { CoverUrlRole,   "coverUrl"   },
        { LogoUrlRole,    "logoUrl"    },
        { InstalledRole,  "installed"  },
        { SizeRole,       "sizeOnDisk" },
        { LastPlayedRole, "lastPlayed" },
    };
}
