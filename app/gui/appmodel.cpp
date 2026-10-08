#include "appmodel.h"

#include <QReadWriteLock>

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_BoxArtManager, &BoxArtManager::boxArtLoadComplete,
            this, &AppModel::handleBoxArtLoaded);
}

void AppModel::initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames)
{
    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &AppModel::handleComputerStateChanged);

    Q_ASSERT(computerIndex < m_ComputerManager->getComputers().count());
    m_Computer = m_ComputerManager->getComputers().at(computerIndex);
    m_ShowHiddenGames = showHiddenGames;

    QVector<NvApp> appList;
    {
        QReadLocker lock(&m_Computer->lock);
        m_CurrentGameId = m_Computer->currentGameId;
        appList = m_Computer->appList;
    }
    updateAppList(appList);
}

int AppModel::getRunningAppId()
{
    return m_CurrentGameId;
}

QString AppModel::getRunningAppName()
{
    if (m_CurrentGameId != 0) {
        for (int i = 0; i < m_AllApps.count(); i++) {
            if (m_AllApps[i].id == m_CurrentGameId) {
                return m_AllApps[i].name;
            }
        }
    }

    return nullptr;
}

int AppModel::appCount() const
{
    return m_VisibleApps.count();
}

QString AppModel::appNameAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count()) {
        return QString();
    }
    return m_VisibleApps.at(row).name;
}

int AppModel::appIdAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count()) {
        return 0;
    }
    return m_VisibleApps.at(row).id;
}

bool AppModel::appRunningAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count() || m_CurrentGameId == 0) {
        return false;
    }
    return m_VisibleApps.at(row).id == m_CurrentGameId;
}

bool AppModel::appHiddenAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count()) {
        return false;
    }
    return m_VisibleApps.at(row).hidden;
}

bool AppModel::appDirectLaunchAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count()) {
        return false;
    }
    return m_VisibleApps.at(row).directLaunch;
}

QString AppModel::appBoxArtAt(int row) const
{
    if (row < 0 || row >= m_VisibleApps.count()) {
        return QString();
    }
    return data(index(row, 0), BoxArtRole).toString();
}

Session* AppModel::createSessionForApp(int appIndex)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(appIndex);

    Session* session = new Session(m_Computer, app);
    NvComputer* computer = m_Computer;
    ComputerManager* manager = m_ComputerManager;
    connect(session, &Session::runningGameChanged, manager,
            [manager, computer](int gameId) {
                manager->applyReportedRunningGame(computer, gameId);
            },
            Qt::QueuedConnection);
    return session;
}

int AppModel::getDirectLaunchAppIndex()
{
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        if (m_VisibleApps[i].directLaunch) {
            return i;
        }
    }

    return -1;
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    // For list models only the root node (an invalid parent) should return the list's size. For all
    // other (valid) parents, rowCount() should return 0 so that it does not become a tree model.
    if (parent.isValid())
        return 0;

    return m_VisibleApps.count();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    Q_ASSERT(index.row() < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(index.row());

    switch (role)
    {
    case NameRole:
        return app.name;
    case RunningRole:
        // Same cache requestQuitOnly and the desktop Quit button read.
        // The live computer field can disagree with that cache for a poll.
        return m_CurrentGameId == app.id;
    case BoxArtRole:
        // FIXME: const-correctness
        return const_cast<BoxArtManager&>(m_BoxArtManager).loadBoxArt(m_Computer, app);
    case HiddenRole:
        return app.hidden;
    case AppIdRole:
        return app.id;
    case DirectLaunchRole:
        return app.directLaunch;
    case AppCollectorGameRole:
        return app.isAppCollectorGame;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    QHash<int, QByteArray> names;

    names[NameRole] = "name";
    names[RunningRole] = "running";
    names[BoxArtRole] = "boxart";
    names[HiddenRole] = "hidden";
    names[AppIdRole] = "appid";
    names[DirectLaunchRole] = "directLaunch";
    names[AppCollectorGameRole] = "appCollectorGame";

    return names;
}

void AppModel::quitRunningApp()
{
    m_ComputerManager->quitRunningApp(m_Computer);
}

bool AppModel::isAppCurrentlyVisible(const NvApp& app)
{
    for (const NvApp& visibleApp : m_VisibleApps) {
        if (app.id == visibleApp.id) {
            return true;
        }
    }

    return false;
}

QVector<NvApp> AppModel::getVisibleApps(const QVector<NvApp>& appList)
{
    QVector<NvApp> visibleApps;

    for (const NvApp& app : appList) {
        // Don't immediately hide games that were previously visible. This
        // allows users to easily uncheck the "Hide App" checkbox if they
        // check it by mistake.
        if (m_ShowHiddenGames || !app.hidden || isAppCurrentlyVisible(app)) {
            visibleApps.append(app);
        }
    }

    return visibleApps;
}

void AppModel::updateAppList(QVector<NvApp> newList)
{
    m_AllApps = newList;

    QVector<NvApp> newVisibleList = getVisibleApps(newList);

    // Process removals and updates first
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        const NvApp& existingApp = m_VisibleApps.at(i);

        bool found = false;
        for (const NvApp& newApp : newVisibleList) {
            if (existingApp.id == newApp.id) {
                // If the data changed, update it in our list
                if (existingApp != newApp) {
                    m_VisibleApps.replace(i, newApp);
                    emit dataChanged(createIndex(i, 0), createIndex(i, 0));
                }

                found = true;
                break;
            }
        }

        if (!found) {
            beginRemoveRows(QModelIndex(), i, i);
            m_VisibleApps.removeAt(i);
            endRemoveRows();
            i--;
        }
    }

    // Process additions now
    for (const NvApp& newApp : newVisibleList) {
        int insertionIndex = m_VisibleApps.size();
        bool found = false;

        for (int i = 0; i < m_VisibleApps.count(); i++) {
            const NvApp& existingApp = m_VisibleApps.at(i);

            if (existingApp.id == newApp.id) {
                found = true;
                break;
            }
            else if (existingApp.name.toLower() > newApp.name.toLower()) {
                insertionIndex = i;
                break;
            }
        }

        if (!found) {
            beginInsertRows(QModelIndex(), insertionIndex, insertionIndex);
            m_VisibleApps.insert(insertionIndex, newApp);
            endInsertRows();
        }
    }

    Q_ASSERT(newVisibleList == m_VisibleApps);
}

void AppModel::setAppHidden(int appIndex, bool hidden)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (app.id == appId) {
                app.hidden = hidden;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::setAppDirectLaunch(int appIndex, bool directLaunch)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (directLaunch) {
                // We must clear direct launch from all other apps
                // to set it on the new app.
                app.directLaunch = app.id == appId;
            }
            else if (app.id == appId) {
                // If we're clearing direct launch, we're done once we
                // find our matching app ID.
                app.directLaunch = false;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::handleComputerStateChanged(NvComputer* computer)
{
    // Ignore updates for computers that aren't ours
    if (computer != m_Computer) {
        return;
    }

    int gameId = 0;
    bool lost = false;
    QVector<NvApp> appList;
    {
        QReadLocker lock(&computer->lock);
        gameId = computer->currentGameId;
        lost = computer->state == NvComputer::CS_OFFLINE ||
                computer->pairState == NvComputer::PS_NOT_PAIRED;
        if (!lost) {
            appList = computer->appList;
        }
    }

    // If the computer has gone offline or we've been unpaired,
    // signal the UI so we can go back to the PC view. Drop the running
    // cache first so a later read does not still say an app is live.
    if (lost) {
        const int previous = m_CurrentGameId;
        m_CurrentGameId = 0;
        if (previous != 0) {
            for (int i = 0; i < m_VisibleApps.count(); i++) {
                if (m_VisibleApps[i].id == previous) {
                    emit dataChanged(createIndex(i, 0),
                                     createIndex(i, 0),
                                     QVector<int>() << RunningRole);
                    break;
                }
            }
        }
        emit computerLost();
        return;
    }

    // First, process additions/removals from the app list. This
    // is required because the new game may now be running, so
    // we can't check that first.
    if (appList != m_AllApps) {
        updateAppList(appList);
    }

    // Finally, process changes to the active app. The cache moves first
    // so RunningRole and getRunningAppId() agree when the view re-reads.
    if (gameId != m_CurrentGameId) {
        const int previous = m_CurrentGameId;
        m_CurrentGameId = gameId;

        for (int i = 0; i < m_VisibleApps.count(); i++) {
            if (m_VisibleApps[i].id == gameId) {
                emit dataChanged(createIndex(i, 0),
                                 createIndex(i, 0),
                                 QVector<int>() << RunningRole);
                break;
            }
        }

        if (previous != 0) {
            for (int i = 0; i < m_VisibleApps.count(); i++) {
                if (m_VisibleApps[i].id == previous) {
                    emit dataChanged(createIndex(i, 0),
                                     createIndex(i, 0),
                                     QVector<int>() << RunningRole);
                    break;
                }
            }
        }
    }
}

void AppModel::handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl /* image */)
{
    Q_ASSERT(computer == m_Computer);

    int index = m_VisibleApps.indexOf(app);

    // Make sure we're not delivering a callback to an app that's already been removed
    if (index >= 0) {
        // Let our view know the box art data has changed for this app
        emit dataChanged(createIndex(index, 0),
                         createIndex(index, 0),
                         QVector<int>() << BoxArtRole);
    }
    else {
        qWarning() << "App not found for box art callback:" << app.name;
    }
}
