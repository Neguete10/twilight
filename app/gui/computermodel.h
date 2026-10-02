#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QAbstractListModel>

class ComputerModel : public QAbstractListModel
{
    Q_OBJECT

    enum Roles
    {
        NameRole = Qt::UserRole,
        OnlineRole,
        PairedRole,
        BusyRole,
        WakeableRole,
        StatusUnknownRole,
        ServerSupportedRole,
        DetailsRole
    };

public:
    explicit ComputerModel(QObject* object = nullptr);

    // Must be called before any QAbstractListModel functions
    Q_INVOKABLE void initialize(ComputerManager* computerManager);

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void deleteComputer(int computerIndex);

    Q_INVOKABLE QString generatePinString();

    Q_INVOKABLE void pairComputer(int computerIndex, QString pin);

    Q_INVOKABLE void testConnectionForComputer(int computerIndex);

    Q_INVOKABLE void wakeComputer(int computerIndex);

    Q_INVOKABLE void renameComputer(int computerIndex, QString name);

    Q_INVOKABLE Session* createSessionForCurrentGame(int computerIndex);

    Q_INVOKABLE int computerCount() const;
    Q_INVOKABLE QString computerNameAt(int row) const;
    Q_INVOKABLE QString computerUuidAt(int row) const;
    Q_INVOKABLE bool computerOnlineAt(int row) const;
    Q_INVOKABLE bool computerPairedAt(int row) const;
    Q_INVOKABLE bool computerWakeableAt(int row) const;
    Q_INVOKABLE bool computerBusyAt(int row) const;
    Q_INVOKABLE bool computerStatusUnknownAt(int row) const;
    Q_INVOKABLE bool computerSupportedAt(int row) const;
    Q_INVOKABLE QString computerDetailsAt(int row) const;

signals:
    void pairingCompleted(QVariant error);
    void connectionTestCompleted(int result, QString blockedPorts);

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handlePairingCompleted(NvComputer* computer, QString error);

private:
    QVariant roleAt(int row, int role) const;

    QVector<NvComputer*> m_Computers;
    ComputerManager* m_ComputerManager;
};
