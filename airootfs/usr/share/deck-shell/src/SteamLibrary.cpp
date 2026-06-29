#include "SteamLibrary.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QProcess>
#include <QUrl>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <algorithm>
#include <cstdlib>

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

QString SteamLibraryModel::steamBasePath()
{
    QString sym = QDir::homePath() + "/.steam/steam";
    if (QDir(sym).exists()) return sym;

    QString xdg = QDir::homePath() + "/.local/share/Steam";
    if (QDir(xdg).exists()) return xdg;

    QString flat = QDir::homePath() + "/.var/app/com.valvesoftware.Steam/data/Steam";
    if (QDir(flat).exists()) return flat;

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
        if (!roots.contains(canon))
            roots << canon;
    };

    addRoot(base + "/steamapps");

    QString vdfPath = base + "/steamapps/libraryfolders.vdf";
    QFile f(vdfPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return roots;

    QTextStream in(&f);
    QStringList lines;
    while (!in.atEnd()) lines << in.readLine();

    QRegularExpression pathRe(R"rx(^\s*"path"\s+"([^"]+)")rx");
    for (const QString &line : lines) {
        auto m = pathRe.match(line);
        if (m.hasMatch())
            addRoot(m.captured(1) + "/steamapps");
    }

    QRegularExpression legacyRe(R"rx(^\s*"[0-9]+"\s+"(/[^"]+)")rx");
    for (const QString &line : lines) {
        auto m = legacyRe.match(line);
        if (m.hasMatch())
            addRoot(m.captured(1) + "/steamapps");
    }

    return roots;
}

SteamGame SteamLibraryModel::parseAppManifest(const QString &acfPath)
{
    QFile f(acfPath);
    SteamGame g;
    g.installed = false;
    g.sizeOnDisk = 0;
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return g;

    QTextStream in(&f);
    QStringList lines;
    while (!in.atEnd()) lines << in.readLine();

    g.appId      = vdfValue(lines, "appid");
    g.name       = vdfValue(lines, "name");
    g.lastPlayed = vdfValue(lines, "LastPlayed");
    QString sizeStr = vdfValue(lines, "SizeOnDisk");
    g.sizeOnDisk = sizeStr.isEmpty() ? 0 : sizeStr.toLongLong();
    g.installed  = !g.appId.isEmpty() && !g.name.isEmpty();

    g.coverUrl = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/library_600x900.jpg").arg(g.appId);
    g.logoUrl  = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/header.jpg").arg(g.appId);

    return g;
}

QList<SteamGame> SteamLibraryModel::parseLibraryRoot(const QString &libraryPath)
{
    QList<SteamGame> games;
    QDir dir(libraryPath);
    if (!dir.exists()) return games;

    const QStringList acfFiles = dir.entryList({"appmanifest_*.acf"}, QDir::Files);
    for (const QString &fn : acfFiles) {
        SteamGame g = parseAppManifest(dir.filePath(fn));
        if (g.installed) games << g;
    }
    return games;
}

SteamLibraryModel::SteamLibraryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_nam, &QNetworkAccessManager::finished,
            this, &SteamLibraryModel::handleOwnedGamesReply);
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
    endResetModel();
    emit countChanged();
}

void SteamLibraryModel::setFilterMode(int mode)
{
    if (mode == m_filterMode) return;
    m_filterMode = mode;
    emit filterModeChanged();
    // Changing filter just affects what QML shows; the merged list stays the same
    emit countChanged();
    emit dataChanged(index(0,0), index(rowCount()-1,0));
}

void SteamLibraryModel::refresh()
{
    setLoading(true);

    QList<SteamGame> local;
    for (const QString &root : findLibraryRoots())
        local << parseLibraryRoot(root);

    // Sort local installed games alphabetically
    std::sort(local.begin(), local.end(), [](const SteamGame &a, const SteamGame &b) {
        return a.name.toLower() < b.name.toLower();
    });

    m_gamesLocal = local;

    // Start Web API request for owned titles; merged list set in reply handler
    fetchOwnedGames();
}

void SteamLibraryModel::fetchOwnedGames()
{
    const QByteArray key = qgetenv("STEAM_API_KEY");
    const QByteArray id  = qgetenv("STEAM_ID64");
    if (key.isEmpty() || id.isEmpty()) {
        // No Web API configuration; fall back to local installed only
        QList<SteamGame> merged = m_gamesLocal;
        setMergedGames(merged);
        setLoading(false);
        emit errorOccurred("STEAM_API_KEY/STEAM_ID64 not set; showing installed games only.");
        return;
    }

    QUrl url(QStringLiteral("https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"));
    QUrlQuery q;
    q.addQueryItem("key", QString::fromUtf8(key));
    q.addQueryItem("steamid", QString::fromUtf8(id));
    q.addQueryItem("include_appinfo", "1");
    q.addQueryItem("include_played_free_games", "1");
    url.setQuery(q);

    QNetworkRequest req(url);
    m_nam.get(req);
}

void SteamLibraryModel::handleOwnedGamesReply(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        QList<SteamGame> merged = m_gamesLocal;
        setMergedGames(merged);
        setLoading(false);
        emit errorOccurred(QStringLiteral("Steam Web API error: %1").arg(reply->errorString()));
        reply->deleteLater();
        return;
    }

    const QByteArray bytes = reply->readAll();
    reply->deleteLater();

    QJsonDocument doc = QJsonDocument::fromJson(bytes);
    QJsonObject rootObj = doc.object();
    QJsonObject responseObj = rootObj.value("response").toObject();
    QJsonArray gamesArr = responseObj.value("games").toArray();

    // Index local installed games by appId for quick lookup
    QHash<QString, SteamGame> localById;
    for (const SteamGame &g : m_gamesLocal)
        localById.insert(g.appId, g);

    QList<SteamGame> merged;

    for (const QJsonValue &v : gamesArr) {
        QJsonObject obj = v.toObject();
        const QString appId = QString::number(obj.value("appid").toInt());
        const QString name  = obj.value("name").toString();
        if (appId.isEmpty() || name.isEmpty()) continue;

        SteamGame g;
        if (localById.contains(appId)) {
            // Installed game: start from local manifest data
            g = localById.value(appId);
        } else {
            g.appId = appId;
            g.name  = name;
            g.installed   = false;
            g.sizeOnDisk  = 0;
            g.lastPlayed  = QString();
            g.coverUrl = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/library_600x900.jpg").arg(appId);
            g.logoUrl  = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/header.jpg").arg(appId);
        }

        merged << g;
    }

    // If Web API returned nothing, fall back to local only
    if (merged.isEmpty())
        merged = m_gamesLocal;

    std::sort(merged.begin(), merged.end(), [](const SteamGame &a, const SteamGame &b) {
        return a.name.toLower() < b.name.toLower();
    });

    setMergedGames(merged);
    setLoading(false);
}

void SteamLibraryModel::launchGame(const QString &appId)
{
    QProcess::startDetached("steam", {"-applaunch", appId});
}

void SteamLibraryModel::installGame(const QString &appId)
{
    QProcess::startDetached("steam", {QStringLiteral("steam://store/%1").arg(appId)});
}

int SteamLibraryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;

    if (m_filterMode == InstalledOnly) {
        int count = 0;
        for (const SteamGame &g : m_gamesMerged)
            if (g.installed)
                ++count;
        return count;
    }

    return m_gamesMerged.size();
}

QVariant SteamLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) return {};

    // Map view index to underlying merged list based on filter mode
    int row = index.row();
    if (m_filterMode == InstalledOnly) {
        int logical = -1;
        int i = 0;
        for (int k = 0; k < m_gamesMerged.size(); ++k) {
            if (m_gamesMerged[k].installed) {
                if (i == row) { logical = k; break; }
                ++i;
            }
        }
        if (logical < 0) return {};
        row = logical;
    }

    if (row < 0 || row >= m_gamesMerged.size()) return {};
    const SteamGame &g = m_gamesMerged.at(row);

    switch (role) {
    case AppIdRole:     return g.appId;
    case NameRole:      return g.name;
    case CoverUrlRole:  return g.coverUrl;
    case LogoUrlRole:   return g.logoUrl;
    case InstalledRole: return g.installed;
    case SizeRole:      return g.sizeOnDisk;
    case LastPlayedRole:return g.lastPlayed;
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
        { LastPlayedRole, "lastPlayed" }
    };
}
