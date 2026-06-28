#include "SteamLibrary.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QProcess>
#include <QUrl>
#include <QDebug>
#include <algorithm>

// ────────────────────────────────────────────────────────────────────────────
// Tiny VDF key→value extractor  (handles both libraryfolders.vdf and .acf)
// Format:  "key"   "value"  (tab-separated, or any whitespace)
// ────────────────────────────────────────────────────────────────────────────
static QString vdfValue(const QStringList &lines, const QString &key)
{
    // Match:  "key"\s+"value"
    QRegularExpression re(
        QStringLiteral("^\\s*\"") + QRegularExpression::escape(key) +
        QStringLiteral("\"\\s+\"([^\"]*)\""));
    for (const QString &line : lines) {
        auto m = re.match(line);
        if (m.hasMatch()) return m.captured(1);
    }
    return {};
}

// ── Locate Steam base directory (~/.steam/steam or ~/.local/share/Steam) ────
QString SteamLibraryModel::steamBasePath()
{
    // Canonical symlink created by steam on every Linux install
    QString sym = QDir::homePath() + "/.steam/steam";
    if (QDir(sym).exists()) return sym;

    QString xdg = QDir::homePath() + "/.local/share/Steam";
    if (QDir(xdg).exists()) return xdg;

    // Flatpak path
    QString flat = QDir::homePath() + "/.var/app/com.valvesoftware.Steam/data/Steam";
    if (QDir(flat).exists()) return flat;

    return {};
}

// ── Parse libraryfolders.vdf → list of library root paths ───────────────────
// VDF v2 format (Steam ≥ 2021):
//   "1" { "path" "/media/games/SteamLibrary" … "apps" { "570" "…" } }
// Also handles legacy v1 ("1" "/path").
QStringList SteamLibraryModel::findLibraryRoots()
{
    QString base = steamBasePath();
    if (base.isEmpty()) return {};

    QStringList roots;
    roots << base + "/steamapps";  // default library always present

    QString vdfPath = base + "/steamapps/libraryfolders.vdf";
    QFile f(vdfPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return roots;

    QTextStream in(&f);
    QStringList lines;
    while (!in.atEnd()) lines << in.readLine();

    // v2: look for "path" keys inside numbered section blocks
    QRegularExpression pathRe(R"(^\s*"path"\s+"([^"]+)")");
    for (const QString &line : lines) {
        auto m = pathRe.match(line);
        if (m.hasMatch()) {
            QString candidate = m.captured(1) + "/steamapps";
            if (QDir(candidate).exists() && !roots.contains(candidate))
                roots << candidate;
        }
    }

    // v1 legacy: numeric key → path value
    QRegularExpression legacyRe(R"(^\s*"[0-9]+"\s+"(/[^"]+)")");
    for (const QString &line : lines) {
        auto m = legacyRe.match(line);
        if (m.hasMatch()) {
            QString candidate = m.captured(1) + "/steamapps";
            if (QDir(candidate).exists() && !roots.contains(candidate))
                roots << candidate;
        }
    }

    return roots;
}

// ── Parse a single appmanifest_<appid>.acf file ──────────────────────────────
SteamGame SteamLibraryModel::parseAppManifest(const QString &acfPath)
{
    QFile f(acfPath);
    SteamGame g;
    g.installed = false;
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

    // Steam CDN artwork URLs — no API key required
    // Portrait cover (library grid view): 600×900
    g.coverUrl = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/library_600x900.jpg")
                     .arg(g.appId);
    // Hero / logo for the detail overlay
    g.logoUrl  = QStringLiteral("https://cdn.steamstatic.com/steam/apps/%1/header.jpg")
                     .arg(g.appId);

    return g;
}

// ── Scan one library root for all appmanifest_*.acf files ────────────────────
QList<SteamGame> SteamLibraryModel::parseLibraryRoot(const QString &libraryPath)
{
    QList<SteamGame> games;
    QDir dir(libraryPath);
    if (!dir.exists()) return games;

    QStringList acfFiles = dir.entryList({"appmanifest_*.acf"}, QDir::Files);
    for (const QString &fn : acfFiles) {
        SteamGame g = parseAppManifest(dir.filePath(fn));
        if (g.installed) games << g;
    }
    return games;
}

// ── Model ────────────────────────────────────────────────────────────────────
SteamLibraryModel::SteamLibraryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    refresh();
}

void SteamLibraryModel::setLoading(bool v)
{
    if (m_loading == v) return;
    m_loading = v;
    emit loadingChanged();
}

void SteamLibraryModel::setGames(QList<SteamGame> games)
{
    beginResetModel();
    m_games = std::move(games);
    endResetModel();
    emit countChanged();
}

void SteamLibraryModel::refresh()
{
    setLoading(true);
    QList<SteamGame> all;
    for (const QString &root : findLibraryRoots())
        all << parseLibraryRoot(root);

    // Sort alphabetically by name
    std::sort(all.begin(), all.end(), [](const SteamGame &a, const SteamGame &b) {
        return a.name.toLower() < b.name.toLower();
    });

    setGames(all);
    setLoading(false);

    if (all.isEmpty())
        emit errorOccurred("No installed Steam games found. Is Steam installed?");
}

void SteamLibraryModel::launchGame(const QString &appId)
{
    // steam -applaunch <appid> is the canonical CLI launch method on Linux
    // It re-uses an already-running Steam instance or starts one.
    QProcess::startDetached("steam", {"-applaunch", appId});
}

void SteamLibraryModel::installGame(const QString &appId)
{
    // Opens the Steam store page via the steam:// URI protocol
    QProcess::startDetached("steam", {QStringLiteral("steam://store/%1").arg(appId)});
}

int SteamLibraryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_games.size();
}

QVariant SteamLibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_games.size()) return {};
    const SteamGame &g = m_games.at(index.row());
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
