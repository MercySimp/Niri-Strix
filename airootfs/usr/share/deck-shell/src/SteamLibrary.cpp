#include "SteamLibrary.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QDebug>
#include <algorithm>

// The Windows backend URL — all Steam API calls are made server-side.
// Override at runtime by setting DECK_BACKEND_URL in the environment.
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
// Local Steam library scanning (installed games only)
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
// Model
// ---------------------------------------------------------------------------
SteamLibraryModel::SteamLibraryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_nam, &QNetworkAccessManager::finished,
            this,   &SteamLibraryModel::handleLibraryReply);
    refresh();   // load local installed games at startup
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
    // beginResetModel/endResetModel forces the GridView to re-query rowCount()
    // and data(), so the visible set updates immediately when the filter changes.
    beginResetModel();
    endResetModel();
    emit filterModeChanged();
    emit countChanged();
}

// Scan local .acf manifests — no network needed.
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
    setMergedGames(local);   // show installed games while we wait for sign-in
    setLoading(false);
}

// Ask the Windows backend for the full owned-games list.
// The backend holds the Steam API key — Arch never needs one.
void SteamLibraryModel::fetchOwnedGamesForId(const QString &steamId)
{
    if (steamId.isEmpty()) return;
    setLoading(true);

    QUrl url(backendUrl() + QStringLiteral("/library/owned"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("steamid"), steamId);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    m_nam.get(req);
}

// Handle the JSON response from GET /library/owned
void SteamLibraryModel::handleLibraryReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[SteamLibrary] backend error:" << reply->errorString();
        setMergedGames(m_gamesLocal);   // fall back to installed-only
        setLoading(false);
        emit errorOccurred(QStringLiteral("Could not reach backend: %1").arg(reply->errorString()));
        return;
    }

    QByteArray raw = reply->readAll();
    qDebug() << "[SteamLibrary] /library/owned response:" << raw.left(200);

    QJsonDocument doc = QJsonDocument::fromJson(raw);
    QJsonArray arr    = doc.object().value(QStringLiteral("games")).toArray();

    if (arr.isEmpty()) {
        qWarning() << "[SteamLibrary] backend returned empty games array — showing local installed only";
        setMergedGames(m_gamesLocal);
        setLoading(false);
        return;
    }

    // Build a lookup of locally-installed games so we can tag them
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
            g = localById.value(id);   // keep local metadata (size, lastPlayed)
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
        int n = 0;
        for (const SteamGame &g : m_gamesMerged) if (g.installed) ++n;
        return n;
    }
    return m_gamesMerged.size();
}

QVariant SteamLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) return {};

    int row = index.row();
    if (m_filterMode == InstalledOnly) {
        int i = 0;
        for (int k = 0; k < m_gamesMerged.size(); ++k) {
            if (m_gamesMerged[k].installed) {
                if (i == row) { row = k; goto found; }
                ++i;
            }
        }
        return {};
    }
    found:
    if (row < 0 || row >= m_gamesMerged.size()) return {};
    const SteamGame &g = m_gamesMerged.at(row);

    switch (role) {
    case AppIdRole:      return g.appId;
    case NameRole:       return g.name;
    case CoverUrlRole:   return g.coverUrl;
    case LogoUrlRole:    return g.logoUrl;
    case InstalledRole:  return g.installed;
    case SizeRole:       return g.sizeOnDisk;
    case LastPlayedRole: return g.lastPlayed;
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
